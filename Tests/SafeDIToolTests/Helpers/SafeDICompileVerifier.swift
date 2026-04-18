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
	// the output verification entirely.
	let inputsOnlyResult = try runSwiftTypecheck(
		sources: inputCompileFiles,
		artifacts: artifacts,
	)
	if inputsOnlyResult.exitCode != 0 { return }

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

/// Returns the set of type names that already declare conformance to
/// `Instantiable` somewhere in any fixture file. Covers both primary
/// declarations (`struct X: Instantiable`) and extensions
/// (`extension X: Foo, Instantiable`).
func collectTypesDeclaringConformance(in fixtureContents: [String]) -> Set<String> {
	// Match any `struct/class/actor/extension X: <conformance-list including Instantiable>`.
	// The capture isolates the type name; we keep the match broad so we pick up
	// conformance declared in either a primary type or an extension.
	let pattern = #"(?:struct|final\s+class|class|actor|extension)\s+(\w+)\s*:\s*([^{]*)\{"#
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
			result.insert(nsSource.substring(with: nameRange))
		}
	}
	return result
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
	//   [access modifier] [final] (class|struct|actor|extension) TypeName[: conformances]? {
	//
	// Captures the header up through the opening `{` so we can inspect the
	// conformance clause without swallowing the body.
	let pattern = #"(@Instantiable(?:\s*\([^)]*\))?)(\s+(?:[^{]*?))((?:public|internal|open|package|fileprivate|private)?\s*(?:final\s+)?(?:class|struct|actor|extension)\s+(\w+)(\s*:\s*[^{]*)?\s*\{)"#
	let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
	let nsSource = source as NSString
	let fullRange = NSRange(location: 0, length: nsSource.length)

	var result = source
	var offset = 0
	regex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
		guard let match else { return }
		let headerRange = match.range(at: 3)
		let typeNameRange = match.range(at: 4)
		let conformanceRange = match.range(at: 5)

		let header = nsSource.substring(with: headerRange)
		let typeName = nsSource.substring(with: typeNameRange)
		let conformanceText = conformanceRange.location == NSNotFound
			? nil
			: nsSource.substring(with: conformanceRange)
		let alreadyConforms = conformanceText?.range(of: #"\bInstantiable\b"#, options: .regularExpression) != nil
		guard !alreadyConforms else { return }
		// Don't inject when conformance has already been declared on the same
		// type in another fixture file — Swift would treat it as redundant.
		guard !skippingTypes.contains(typeName) else { return }

		var rewrittenHeader = header
		if let conformanceText {
			// Append ", Instantiable" to the existing conformance list.
			let trimmed = conformanceText.trimmingCharacters(in: .whitespaces)
			let replacement = trimmed + ", Instantiable "
			guard let replaceRange = rewrittenHeader.range(of: conformanceText) else { return }
			rewrittenHeader.replaceSubrange(replaceRange, with: replacement)
		} else {
			// No conformance clause: insert one after `TypeName`.
			guard let nameRange = rewrittenHeader.range(of: typeName) else { return }
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

struct SafeDIBuildArtifacts {
	let swiftModuleSearchPath: URL
	let safeDIMacrosToolPath: URL
}

enum SafeDIBuildArtifactLocator {
	static func locate() -> SafeDIBuildArtifacts? {
		for configurationDirectory in candidateConfigurationDirectories() {
			let modulesDirectory = configurationDirectory.appendingPathComponent("Modules")
			let safeDISwiftmodule = modulesDirectory.appendingPathComponent("SafeDI.swiftmodule")
			guard FileManager.default.fileExists(atPath: safeDISwiftmodule.path) else { continue }
			for toolName in ["SafeDIMacros-tool", "SafeDIMacros-tool.exe", "SafeDIMacros"] {
				let toolURL = configurationDirectory.appendingPathComponent(toolName)
				if FileManager.default.fileExists(atPath: toolURL.path) {
					return SafeDIBuildArtifacts(
						swiftModuleSearchPath: modulesDirectory,
						safeDIMacrosToolPath: toolURL,
					)
				}
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

		// Walk up from the test binary's executable path.
		if let executablePath = Bundle.main.executablePath {
			var directory = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
			for _ in 0..<8 {
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

	try process.run()
	process.waitUntilExit()

	let stdoutData = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
	let stderrData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
	return SwiftTypecheckResult(
		exitCode: process.terminationStatus,
		stdout: String(data: stdoutData, encoding: .utf8) ?? "",
		stderr: String(data: stderrData, encoding: .utf8) ?? "",
	)
}
