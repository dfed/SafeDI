// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Testing

/// Invokes `swiftc -typecheck` on the combined test input + generated output
/// and records an `Issue` if the combination fails to compile. The resulting
/// module is typechecked against the already-built `SafeDI` module and the
/// `SafeDIMacros` compiler plugin.
///
/// Verification runs in two passes: the test inputs alone are typechecked
/// first, and only if they succeed does the verifier typecheck inputs plus
/// generated outputs. When the inputs are intentionally invalid (e.g.,
/// fixtures exercising SafeDITool's error-reporting paths, fixtures
/// referencing types declared in another module), the first pass fails and
/// the verifier exits silently — the point of the check is to guard against
/// regressions in *generated* code, not to police fixture hygiene.
///
/// Set the `SAFEDI_SKIP_COMPILE_CHECK` environment variable (to any value) to
/// disable the verification pass for faster local iteration.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func verifyGeneratedCodeCompiles(
	inputSwiftFiles: [URL],
	additionalDirectorySwiftFiles: [URL],
	generatedFiles: [String: String],
	filesToDelete: inout [URL],
	sourceLocation: SourceLocation = #_sourceLocation,
) throws {
	guard ProcessInfo.processInfo.environment["SAFEDI_SKIP_COMPILE_CHECK"] == nil else { return }

	// Skip fixtures that depend on platform-specific frameworks (UIKit, SwiftUI,
	// AppKit, WatchKit) — the SafeDI artifacts are built for the host macOS
	// target, and retargeting the verifier for iOS/watchOS/etc. would require
	// re-compiling the package for every OS in CI. The production user's build
	// (which has the right SDK) will still catch framework-level issues.
	let platformFrameworks = ["UIKit", "SwiftUI", "AppKit", "WatchKit", "Cocoa"]
	let inputURLs = inputSwiftFiles + additionalDirectorySwiftFiles
	var originalInputContents = [String]()
	for sourceFile in inputURLs {
		let contents = try String(contentsOf: sourceFile, encoding: .utf8)
		for framework in platformFrameworks {
			if contents.contains("import \(framework)") { return }
		}
		originalInputContents.append(contents)
	}

	guard let artifacts = SafeDIBuildArtifactLocator.locate() else {
		Issue.record(
			"""
			Could not locate SafeDI build artifacts for compilation verification. \
			Ensure the package is built before running tests, or set \
			SAFEDI_SKIP_COMPILE_CHECK=1 to skip.
			""",
			sourceLocation: sourceLocation,
		)
		return
	}

	let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-verify-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
	filesToDelete.append(scratchDirectory)

	// Figure out which `@Instantiable` types already declare conformance to
	// `Instantiable` somewhere in the fixture set. We only inject conformance
	// where neither the type's primary declaration nor any of its extensions
	// already declares it — otherwise we'd produce redundant conformance errors
	// when the same type is decorated from multiple files.
	let typesAlreadyDeclaringConformance = collectTypesDeclaringConformance(in: originalInputContents)

	// Prepend `import SafeDI` to inputs so that test-fixture sources — which
	// are authored without imports — can resolve the @Instantiable / @Received
	// / @Forwarded / @Instantiated macros and the Instantiable protocol. Test
	// fixtures also frequently omit the `: Instantiable` conformance on types
	// decorated with `@Instantiable` (SafeDITool's parser doesn't require it);
	// inject the conformance so the macro's conformance check passes.
	var inputCompileFiles = [URL]()
	for (index, sourceFile) in inputURLs.enumerated() {
		let contents = originalInputContents[index]
		let adjusted = try injectInstantiableConformance(
			in: contents,
			skippingTypes: typesAlreadyDeclaringConformance,
		)
		let wrapped = "import SafeDI\n" + adjusted
		let destination = scratchDirectory.appendingPathComponent("input_\(index)_\(sourceFile.lastPathComponent)")
		try wrapped.write(to: destination, atomically: true, encoding: .utf8)
		inputCompileFiles.append(destination)
	}

	// First pass: typecheck inputs alone. If the inputs can't compile on their
	// own (broken-on-purpose fixtures, cross-module references, etc.), skip
	// the output verification entirely — but if the failure looks like a
	// verifier infrastructure problem (missing SafeDI module, macro plugin
	// load failure, ABI mismatch), surface it so a regression in the verifier
	// itself doesn't silently disable compile checking everywhere.
	let inputsOnlyResult = try runSwiftTypecheck(
		sources: inputCompileFiles,
		artifacts: artifacts,
	)
	if inputsOnlyResult.exitCode != 0 {
		if looksLikeVerifierInfrastructureFailure(inputsOnlyResult.stderr) {
			Issue.record(
				"""
				Compile verifier could not typecheck even minimal inputs — this looks \
				like a verifier infrastructure failure (e.g., SafeDI module missing, \
				macro plugin failed to load, toolchain mismatch) rather than a \
				broken fixture. Set SAFEDI_SKIP_COMPILE_CHECK=1 to bypass.
				\(inputsOnlyResult.stderr)
				""",
				sourceLocation: sourceLocation,
			)
		}
		return
	}

	var combinedCompileFiles = inputCompileFiles
	for (fileName, contents) in generatedFiles {
		let destination = scratchDirectory.appendingPathComponent(fileName)
		// Generated files reference SafeDI types (Instantiator, SendableInstantiator,
		// etc.) but do not carry their own imports in production — they sit in the
		// same target as the user's code, which imports SafeDI once. Inject the
		// import here so each file typechecks in isolation.
		let wrapped = "import SafeDI\n" + contents
		try wrapped.write(to: destination, atomically: true, encoding: .utf8)
		combinedCompileFiles.append(destination)
	}

	let combinedResult = try runSwiftTypecheck(
		sources: combinedCompileFiles,
		artifacts: artifacts,
	)
	if combinedResult.exitCode != 0 {
		Issue.record(
			"""
			Generated code failed to compile alongside test inputs.
			\(combinedResult.stderr)
			""",
			sourceLocation: sourceLocation,
		)
	}
}

/// Returns the set of base type names that already declare conformance to
/// `Instantiable` somewhere in any fixture file. Covers both primary
/// declarations (`struct X: Instantiable`) and extensions
/// (`extension X: Foo, Instantiable`). Handles generic declarations
/// (`struct Foo<T>: Instantiable`) and module-qualified extensions
/// (`extension MyModule.Container: Instantiable`) by reducing to the bare
/// trailing identifier so the result keys match what
/// `injectInstantiableConformance` looks up.
func collectTypesDeclaringConformance(in fixtureContents: [String]) -> Set<String> {
	let pattern = #"(?:struct|final\s+class|class|actor|extension)\s+((?:\w+\.)*\w+)(?:\s*<[^>]*>)?\s*:\s*([^{]*)\{"#
	guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
		return []
	}

	var result = Set<String>()
	for source in fixtureContents {
		let nsSource = source as NSString
		let fullRange = NSRange(location: 0, length: nsSource.length)
		regex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
			guard let match else { return }
			let nameRange = match.range(at: 1)
			let conformanceRange = match.range(at: 2)
			guard nameRange.location != NSNotFound, conformanceRange.location != NSNotFound else { return }
			let conformance = nsSource.substring(with: conformanceRange)
			guard conformance.range(of: #"\bInstantiable\b"#, options: .regularExpression) != nil else { return }
			let qualifiedName = nsSource.substring(with: nameRange)
			result.insert(extractBaseTypeName(from: qualifiedName))
		}
	}
	return result
}

/// Strips a module qualifier and any generic parameter list from a captured
/// type-declaration name, leaving the bare identifier (`MyModule.Container<T>`
/// → `Container`). Used as the canonical key for the
/// `typesAlreadyDeclaringConformance` skip set.
private func extractBaseTypeName(from qualified: String) -> String {
	let withoutGenerics = qualified.split(separator: "<", maxSplits: 1, omittingEmptySubsequences: false)[0]
	if let lastDot = withoutGenerics.lastIndex(of: ".") {
		return String(withoutGenerics[withoutGenerics.index(after: lastDot)...])
	}
	return String(withoutGenerics)
}

/// Returns a copy of `source` where the inner contents of every
/// `@Instantiable(...)` argument list are replaced with spaces (newlines
/// preserved). Lengths are preserved so any regex match on the result maps
/// back to the original by NSRange. This lets the conformance-injection
/// regex use a simple `\([^)]*\)` matcher even when arguments contain
/// nested parentheses (e.g.,
/// `@Instantiable(fulfillingAdditionalTypes: [(any P).self])`).
private func scrubInstantiableArguments(_ source: String) -> String {
	let attributeName = "@Instantiable"
	var scalars = Array(source.unicodeScalars)
	let attributeScalars = Array(attributeName.unicodeScalars)
	var index = 0
	while index <= scalars.count - attributeScalars.count {
		var matches = true
		for offset in 0..<attributeScalars.count where scalars[index + offset] != attributeScalars[offset] {
			matches = false
			break
		}
		guard matches else {
			index += 1
			continue
		}
		// Word boundary check on both ends.
		if index > 0, isIdentifierContinuation(scalars[index - 1]) {
			index += 1
			continue
		}
		var cursor = index + attributeScalars.count
		if cursor < scalars.count, isIdentifierContinuation(scalars[cursor]) {
			index += 1
			continue
		}
		// Skip whitespace between `@Instantiable` and an optional `(`.
		while cursor < scalars.count, isWhitespaceScalar(scalars[cursor]) {
			cursor += 1
		}
		guard cursor < scalars.count, scalars[cursor] == "(" else {
			index += attributeScalars.count
			continue
		}
		let argumentListStart = cursor
		var depth = 1
		cursor += 1
		while cursor < scalars.count, depth > 0 {
			let scalar = scalars[cursor]
			if scalar == "(" {
				depth += 1
			} else if scalar == ")" {
				depth -= 1
			}
			cursor += 1
		}
		guard depth == 0 else {
			index += attributeScalars.count
			continue
		}
		let argumentListEnd = cursor - 1
		if argumentListEnd > argumentListStart + 1 {
			for replaceIndex in (argumentListStart + 1)..<argumentListEnd where !isNewlineScalar(scalars[replaceIndex]) {
				scalars[replaceIndex] = Unicode.Scalar(" ")
			}
		}
		index = cursor
	}
	return String(String.UnicodeScalarView(scalars))
}

private func isIdentifierContinuation(_ scalar: Unicode.Scalar) -> Bool {
	if scalar == "_" { return true }
	if scalar.value < 128 {
		let asciiValue = scalar.value
		return (asciiValue >= 0x30 && asciiValue <= 0x39) // 0-9
			|| (asciiValue >= 0x41 && asciiValue <= 0x5A) // A-Z
			|| (asciiValue >= 0x61 && asciiValue <= 0x7A) // a-z
	}
	return false
}

private func isWhitespaceScalar(_ scalar: Unicode.Scalar) -> Bool {
	scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
}

private func isNewlineScalar(_ scalar: Unicode.Scalar) -> Bool {
	scalar == "\n" || scalar == "\r"
}

/// Heuristic detector for verifier infrastructure failures (vs. fixture-only
/// compile errors). Catches the common "verifier is broken" symptoms — missing
/// SafeDI module, macro plugin failed to load, toolchain ABI mismatch — so
/// they surface as test failures instead of being silently swallowed by the
/// inputs-only early-return path.
private func looksLikeVerifierInfrastructureFailure(_ stderr: String) -> Bool {
	let signals = [
		"no such module 'SafeDI'",
		"failed to load plugin",
		"could not load plugin",
		"could not be found in plugin",
		"compiler plugin",
		"module compiled with Swift",
		"unable to find module dependency",
	]
	for signal in signals where stderr.contains(signal) {
		return true
	}
	return false
}

/// Rewrites test-fixture source so that `@Instantiable`-decorated types and
/// extensions explicitly declare conformance to `Instantiable`. SafeDITool's
/// parser does not require the conformance, so many fixtures omit it — but
/// the macro enforces it. Injecting here keeps fixtures terse while letting
/// the verifier compile them.
func injectInstantiableConformance(
	in source: String,
	skippingTypes: Set<String> = [],
) throws -> String {
	// Matches:
	//   @Instantiable[(optional arg list)]
	//   [attributes/whitespace/newlines]
	//   [access modifier] [final] (class|struct|actor|extension) TypeName[<...>][: conformances][where ...] {
	//
	// We match against a *scrubbed* copy of the source where `@Instantiable`
	// arg-list contents have been replaced with spaces, so the simple
	// `\([^)]*\)` matcher works even when arguments contain nested parens
	// (e.g., `@Instantiable(fulfillingAdditionalTypes: [(any P).self])`).
	// Length is preserved by the scrubber so NSRange offsets map back to the
	// original `source` directly.
	//
	// The type-name capture admits module qualifiers (`MyModule.Container`)
	// and a trailing single-level generic parameter list (`Foo<T>`) so we can
	// inject conformance on generic and module-qualified declarations.
	let pattern = #"(@Instantiable(?:\s*\([^)]*\))?)(\s+(?:[^{]*?))((?:public|internal|open|package|fileprivate|private)?\s*(?:final\s+)?(?:class|struct|actor|extension)\s+((?:\w+\.)*\w+(?:\s*<[^>]*>)?)(\s*:\s*[^{]*)?\s*\{)"#
	let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
	let scrubbedSource = scrubInstantiableArguments(source)
	let nsScrubbed = scrubbedSource as NSString
	let nsSource = source as NSString
	let fullRange = NSRange(location: 0, length: nsScrubbed.length)

	var result = source
	var offset = 0
	regex.enumerateMatches(in: scrubbedSource, options: [], range: fullRange) { match, _, _ in
		guard let match else { return }
		let headerRange = match.range(at: 3)
		let typeNameRange = match.range(at: 4)
		let conformanceRange = match.range(at: 5)

		// Pull the captures from the *original* source so we preserve exact
		// argument-list text in the rewritten header (the scrubbed copy is
		// only used to anchor the regex match positions).
		let header = nsSource.substring(with: headerRange)
		let qualifiedTypeName = nsSource.substring(with: typeNameRange)
		let baseTypeName = extractBaseTypeName(from: qualifiedTypeName)
		let conformanceText = conformanceRange.location == NSNotFound
			? nil
			: nsSource.substring(with: conformanceRange)
		let alreadyConforms = conformanceText?.range(of: #"\bInstantiable\b"#, options: .regularExpression) != nil
		guard !alreadyConforms else { return }
		// Don't inject when conformance has already been declared on the same
		// type in another fixture file — Swift would treat it as redundant.
		guard !skippingTypes.contains(baseTypeName) else { return }

		var rewrittenHeader = header
		if let conformanceText {
			// Conformance text may carry a trailing `where` clause; the new
			// conformance has to be inserted into the conformance list itself
			// (before any `where`), not appended after it.
			let (conformanceList, trailingClause) = splitConformanceAndWhereClause(conformanceText)
			let trimmedList = conformanceList.trimmingCharacters(in: .whitespaces)
			let replacement = trimmedList + ", Instantiable" + (trailingClause.isEmpty ? "" : " " + trailingClause) + " "
			guard let replaceRange = rewrittenHeader.range(of: conformanceText) else { return }
			rewrittenHeader.replaceSubrange(replaceRange, with: replacement)
		} else {
			// No conformance clause: insert one after `TypeName[<...>]`. We
			// search for the captured qualifiedTypeName so we land *after*
			// any generic parameter list, which keeps the resulting header
			// well-formed (`Container<T>: Instantiable {`, not
			// `Container: Instantiable <T> {`).
			guard let nameRange = rewrittenHeader.range(of: qualifiedTypeName) else { return }
			let insertIndex = nameRange.upperBound
			rewrittenHeader.insert(contentsOf: ": Instantiable ", at: insertIndex)
		}

		let adjustedHeaderRange = NSRange(
			location: headerRange.location + offset,
			length: headerRange.length,
		)
		let nsResult = result as NSString
		result = nsResult.replacingCharacters(in: adjustedHeaderRange, with: rewrittenHeader)
		offset += (rewrittenHeader as NSString).length - headerRange.length
	}
	return result
}

/// Splits a captured conformance clause (everything from the leading `:` up
/// to the opening `{`) into the conformance list portion and any trailing
/// generic `where` clause. New conformances must be appended to the list
/// portion; appending after the `where` clause would produce invalid Swift
/// (`: Foo where T: Sendable, Instantiable`).
private func splitConformanceAndWhereClause(_ conformanceText: String) -> (list: String, whereClause: String) {
	guard let whereRange = conformanceText.range(of: #"(?:^|\s)where\s"#, options: .regularExpression) else {
		return (conformanceText, "")
	}
	// The match begins on either start-of-string or the whitespace preceding
	// `where`; advance past leading whitespace so the trailing clause begins
	// with the `where` keyword itself.
	var keywordStart = whereRange.lowerBound
	while keywordStart < whereRange.upperBound, conformanceText[keywordStart].isWhitespace {
		keywordStart = conformanceText.index(after: keywordStart)
	}
	let listPortion = String(conformanceText[..<keywordStart])
	let wherePortion = String(conformanceText[keywordStart...]).trimmingCharacters(in: .whitespaces)
	return (listPortion, wherePortion)
}

struct SafeDIBuildArtifacts {
	let swiftModuleSearchPath: URL
	let safeDIMacrosToolPath: URL
}

enum SafeDIBuildArtifactLocator {
	static func locate() -> SafeDIBuildArtifacts? {
		for configurationDirectory in candidateConfigurationDirectories() {
			// `swift build` places the swiftmodule in a `Modules/` subdirectory;
			// Xcode places it directly in the configuration (e.g.,
			// `Build/Products/Debug/SafeDI.swiftmodule`). Check both layouts and
			// use the parent of the swiftmodule as the `-I` search path so
			// swiftc resolves `import SafeDI` either way.
			let searchPathCandidates = [
				configurationDirectory.appendingPathComponent("Modules"),
				configurationDirectory,
			]
			var moduleSearchPath: URL?
			for candidate in searchPathCandidates {
				let safeDISwiftmodule = candidate.appendingPathComponent("SafeDI.swiftmodule")
				if FileManager.default.fileExists(atPath: safeDISwiftmodule.path) {
					moduleSearchPath = candidate
					break
				}
			}
			guard let moduleSearchPath else { continue }

			// `swift build` names the macro plugin executable `SafeDIMacros-tool`;
			// Xcode names it `SafeDIMacros`. Match either.
			for toolName in ["SafeDIMacros-tool", "SafeDIMacros-tool.exe", "SafeDIMacros"] {
				let toolURL = configurationDirectory.appendingPathComponent(toolName)
				guard FileManager.default.fileExists(atPath: toolURL.path) else { continue }
				var isDirectory: ObjCBool = false
				_ = FileManager.default.fileExists(atPath: toolURL.path, isDirectory: &isDirectory)
				// Xcode writes a `SafeDIMacros.swiftmodule` directory alongside
				// the executable — skip directory matches so we only return the
				// compiled plugin binary.
				if isDirectory.boolValue { continue }
				return SafeDIBuildArtifacts(
					swiftModuleSearchPath: moduleSearchPath,
					safeDIMacrosToolPath: toolURL,
				)
			}
		}
		return nil
	}

	private static func candidateConfigurationDirectories() -> [URL] {
		var results = [URL]()
		var seen = Set<String>()

		func append(_ url: URL) {
			let standardized = url.standardizedFileURL.path
			if seen.insert(standardized).inserted {
				results.append(url)
			}
		}

		// Xcode's test runner is the shared `xctest` binary from the toolchain,
		// so `Bundle.main.executablePath` lives outside DerivedData. Xcode
		// exports the real build-products directory via these environment
		// variables — use them first when present.
		let environment = ProcessInfo.processInfo.environment
		if let builtProductsDirectoryPaths = environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] {
			for path in builtProductsDirectoryPaths.split(separator: ":") where !path.isEmpty {
				append(URL(fileURLWithPath: String(path)))
			}
		}
		if let xctestBundlePath = environment["XCTestBundlePath"] {
			// `<config>/SafeDIToolTests.xctest` — the config directory is its parent.
			append(URL(fileURLWithPath: xctestBundlePath).deletingLastPathComponent())
		}

		// Walk up from the test binary's executable path. Xcode's test runner
		// lives inside `<config>/SafeDIToolTests.xctest/Contents/MacOS/` —
		// four levels deep from the config directory — while `swift test` runs
		// directly from `.build/<platform>/<config>/`. Keep the walk deep
		// enough to cover both.
		if let executablePath = Bundle.main.executablePath {
			var directory = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
			for _ in 0..<10 {
				append(directory)
				directory = directory.deletingLastPathComponent()
			}
		}

		// Also probe the standard `.build` locations relative to the cwd
		// (helps when tests are driven from `swift test` at the project root).
		let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let buildRoot = cwd.appendingPathComponent(".build")
		if let platformDirectories = try? FileManager.default.contentsOfDirectory(
			at: buildRoot,
			includingPropertiesForKeys: nil,
		) {
			for platformDirectory in platformDirectories {
				append(platformDirectory.appendingPathComponent("debug"))
				append(platformDirectory.appendingPathComponent("release"))
			}
		}

		return results
	}
}

struct SwiftTypecheckResult {
	let exitCode: Int32
	let stdout: String
	let stderr: String
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func runSwiftTypecheck(
	sources: [URL],
	artifacts: SafeDIBuildArtifacts,
) throws -> SwiftTypecheckResult {
	let process = Process()
	#if os(Linux)
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		var arguments = ["swiftc"]
	#else
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		var arguments = ["swiftc"]
	#endif
	arguments.append(contentsOf: [
		"-typecheck",
		"-module-name", "SafeDICodegenVerification",
		"-I", artifacts.swiftModuleSearchPath.path,
		"-load-plugin-executable", "\(artifacts.safeDIMacrosToolPath.path)#SafeDIMacros",
		"-DDEBUG",
	])
	arguments.append(contentsOf: sources.map(\.path))
	process.arguments = arguments

	let stdoutPipe = Pipe()
	let stderrPipe = Pipe()
	process.standardOutput = stdoutPipe
	process.standardError = stderrPipe

	// Drain both pipes on background queues so a chatty `swiftc` failure
	// (many diagnostics across generated files) can't deadlock the verifier
	// by filling the OS pipe buffer before we get a chance to read it.
	let stdoutQueue = DispatchQueue(label: "safedi.verifier.stdout")
	let stderrQueue = DispatchQueue(label: "safedi.verifier.stderr")
	let drainGroup = DispatchGroup()
	var stdoutData = Data()
	var stderrData = Data()
	drainGroup.enter()
	stdoutQueue.async {
		stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
		drainGroup.leave()
	}
	drainGroup.enter()
	stderrQueue.async {
		stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
		drainGroup.leave()
	}

	try process.run()
	process.waitUntilExit()
	drainGroup.wait()

	return SwiftTypecheckResult(
		exitCode: process.terminationStatus,
		stdout: String(data: stdoutData, encoding: .utf8) ?? "",
		stderr: String(data: stderrData, encoding: .utf8) ?? "",
	)
}
