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
	for sourceFile in inputURLs {
		let contents = try String(contentsOf: sourceFile, encoding: .utf8)
		for framework in platformFrameworks {
			if contents.contains("import \(framework)") { return }
		}
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

	// Prepend `import SafeDI` to each fixture file so test sources — which are
	// authored without imports to keep them compact — can resolve the
	// @Instantiable / @Received / @Forwarded / @Instantiated macros and the
	// Instantiable protocol. The import is added at the wrapper layer (rather
	// than inside the fixture string itself) because SafeDITool propagates
	// user imports into generated output, and adding `import SafeDI` to the
	// fixture string would rewrite every test's expected output to include a
	// `#if canImport(SafeDI)` block.
	var inputCompileFiles = [URL]()
	for (index, sourceFile) in inputURLs.enumerated() {
		let contents = try String(contentsOf: sourceFile, encoding: .utf8)
		let wrapped = "import SafeDI\n" + contents
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

	// Drain both pipes via readability handlers into lock-protected
	// accumulators so a chatty `swiftc` failure (many diagnostics across
	// generated files) can't deadlock the verifier by filling the OS pipe
	// buffer before we get a chance to read it. Mirrors the
	// readability-handler-plus-lock pattern from swift-shell's `Process.swift`,
	// which sidesteps Swift 6 strict-Sendable closure-capture errors that
	// arise when accumulating into a captured `var`.
	let stdoutData = LockedData()
	let stderrData = LockedData()
	stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
		stdoutData.append(handle.availableData)
	}
	stderrPipe.fileHandleForReading.readabilityHandler = { handle in
		stderrData.append(handle.availableData)
	}

	try process.run()
	process.waitUntilExit()

	stdoutPipe.fileHandleForReading.readabilityHandler = nil
	stderrPipe.fileHandleForReading.readabilityHandler = nil
	if let remaining = try? stdoutPipe.fileHandleForReading.readToEnd() {
		stdoutData.append(remaining)
	}
	if let remaining = try? stderrPipe.fileHandleForReading.readToEnd() {
		stderrData.append(remaining)
	}

	return SwiftTypecheckResult(
		exitCode: process.terminationStatus,
		stdout: String(data: stdoutData.read(), encoding: .utf8) ?? "",
		stderr: String(data: stderrData.read(), encoding: .utf8) ?? "",
	)
}

/// Thread-safe `Data` accumulator used by `runSwiftTypecheck` to collect pipe
/// output from a background readability handler without tripping Swift 6
/// strict-Sendable closure-capture diagnostics.
private final class LockedData: @unchecked Sendable {
	private let lock = NSLock()
	private var value = Data()

	func append(_ other: Data) {
		lock.lock()
		defer { lock.unlock() }
		value.append(other)
	}

	func read() -> Data {
		lock.lock()
		defer { lock.unlock() }
		return value
	}
}
