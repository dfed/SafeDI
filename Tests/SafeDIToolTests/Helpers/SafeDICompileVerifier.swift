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

/// Compiles the combined test input + generated output with `swiftc` and
/// records an `Issue` if the combination fails to compile. The module is
/// compiled against the already-built `SafeDI` module and the `SafeDIMacros`
/// compiler plugin.
///
/// On the green path the verifier issues a single `swiftc` invocation for
/// inputs + generated output together. When that pass fails, the verifier
/// compiles the inputs alone as a fallback so the diagnostic can attribute
/// the failure to the fixture vs. the generated code.
///
/// See `compileSwift` for why the compile emits an object file rather than
/// stopping after type checking.
///
/// Fixtures must be self-contained Swift that compiles against SafeDI alone —
/// define stand-in types rather than importing platform frameworks that
/// aren't available on the host SDK (e.g., UIKit on macOS). Tests that rely
/// on cross-module references should opt out at the call site via
/// `skipCompileVerification` or by declaring additional imported modules.
///
/// Set the `SAFEDI_SKIP_COMPILE_CHECK` environment variable (to any value) to
/// disable the verification pass for faster local iteration.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func verifyGeneratedCodeCompiles(
	inputSwiftFiles: [URL],
	additionalDirectorySwiftFiles: [URL],
	generatedFiles: [String: String],
	activeCompilationConditions: [String] = [],
	mockConditionalCompilation: String?,
	filesToDelete: inout [URL],
	sourceLocation: SourceLocation = #_sourceLocation,
) throws {
	guard compileVerificationIsEnabled else { return }

	let inputURLs = inputSwiftFiles + additionalDirectorySwiftFiles

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

	let staged = try stageCompileSources(
		inputSwiftFiles: inputURLs,
		generatedFiles: generatedFiles,
		filesToDelete: &filesToDelete,
	)
	let inputCompileFiles = staged.inputFiles
	let combinedCompileFiles = staged.inputFiles + staged.generatedFiles
	// Generated mock code is wrapped in `#if <mockConditionalCompilation>`, so define that condition
	// to compile the mocks too, as the module's mock-enabled configuration does.
	let compilationConditions = activeCompilationConditions + [mockConditionalCompilation].compactMap(\.self)

	let combinedResult = try compileSwift(
		sources: combinedCompileFiles,
		outputDirectory: staged.directory,
		artifacts: artifacts,
		activeCompilationConditions: compilationConditions,
	)
	guard combinedResult.exitCode != 0 else { return }

	// Combined pass failed. Re-run inputs alone to attribute the failure.
	// The extra subprocess is only paid when something is broken.
	let inputsOnlyResult = try compileSwift(
		sources: inputCompileFiles,
		outputDirectory: staged.directory,
		artifacts: artifacts,
		activeCompilationConditions: compilationConditions,
	)
	if inputsOnlyResult.exitCode != 0 {
		Issue.record(
			"""
			Test inputs failed to compile on their own (before SafeDI codegen \
			runs). The fixture must be valid Swift against SafeDI alone. \
			Common causes: referencing types that aren't declared in the \
			fixture or stubbed out (define stand-ins instead of importing \
			platform frameworks like UIKit that are unavailable on the host \
			SDK), syntax errors in the fixture, or relying on symbols from \
			modules that aren't imported. If the failure is unavoidable for \
			the scenario under test, pass `skipCompileVerification: true` \
			and add a comment explaining why.
			\(inputsOnlyResult.stderr)
			""",
			sourceLocation: sourceLocation,
		)
		return
	}

	Issue.record(
		"""
		\(generatedCodeCompilationFailureMessage)
		\(combinedResult.stderr)
		""",
		sourceLocation: sourceLocation,
	)
}

private let generatedCodeCompilationFailureMessage = "Generated code failed to compile alongside test inputs."

extension Issue {
	/// Whether this is the issue `verifyGeneratedCodeCompiles` records when the fixture compiles on its own but
	/// fails to compile with the generated code, and the compiler's output includes `diagnostic`. A test that
	/// documents a known generator bug matches its known issue with this, so that any other failure, such as a
	/// fixture that does not compile, still fails the test.
	func isGeneratedCodeCompilationFailure(reporting diagnostic: String) -> Bool {
		comments.contains { comment in
			comment.rawValue.hasPrefix(generatedCodeCompilationFailureMessage)
				&& comment.rawValue.contains(diagnostic)
		}
	}
}

/// Whether `verifyGeneratedCodeCompiles` compiles generated code: `false` when the `SAFEDI_SKIP_COMPILE_CHECK`
/// environment variable is set. A test that expects a compilation failure as a known issue expects it only when
/// this is `true`.
var compileVerificationIsEnabled: Bool {
	ProcessInfo.processInfo.environment["SAFEDI_SKIP_COMPILE_CHECK"] == nil
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
				guard !isDirectory.boolValue else { continue }
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
		// The native build system lays products out as `.build/<platform>/<config>/`.
		// The `swiftbuild` build system (the default starting with Swift 6.4) lays
		// them out as `.build/out/Products/<Config>/` and symlinks
		// `.build/<config>` to that directory, so probe the symlinks directly too.
		let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let buildRoot = cwd.appendingPathComponent(".build")
		append(buildRoot.appendingPathComponent("debug"))
		append(buildRoot.appendingPathComponent("release"))
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

struct SwiftCompileResult {
	let exitCode: Int32
	let stdout: String
	let stderr: String
}

/// Fixture and generated files written into a scratch directory the way the compiler will see them.
struct StagedCompileSources {
	/// The scratch directory holding the files, where the compiler also writes its output.
	let directory: URL
	let inputFiles: [URL]
	let generatedFiles: [URL]
}

/// Writes the fixture and generated files into a scratch directory the way the compiler will see them.
///
/// `import SafeDI` is prepended to each file. Fixture files are authored without imports to keep
/// them compact, and the import is added at this layer rather than inside the fixture string
/// because SafeDITool propagates user imports into generated output, so adding it to the fixture
/// would rewrite every test's expected output to include a `#if canImport(SafeDI)` block. Generated
/// files reference SafeDI types but carry no imports in production, where they sit in the same
/// target as the user's code, which imports SafeDI once.
func stageCompileSources(
	inputSwiftFiles: [URL],
	generatedFiles: [String: String],
	filesToDelete: inout [URL],
) throws -> StagedCompileSources {
	let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("safedi-verify-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
	filesToDelete.append(scratchDirectory)

	let inputCompileFiles = try inputSwiftFiles.enumerated().map { index, sourceFile in
		let destination = scratchDirectory.appendingPathComponent("input_\(index)_\(sourceFile.lastPathComponent)")
		try ("import SafeDI\n" + String(contentsOf: sourceFile, encoding: .utf8)).write(to: destination, atomically: true, encoding: .utf8)
		return destination
	}
	let generatedCompileFiles = try generatedFiles.map { fileName, contents in
		let destination = scratchDirectory.appendingPathComponent(fileName)
		try ("import SafeDI\n" + contents).write(to: destination, atomically: true, encoding: .utf8)
		return destination
	}
	return StagedCompileSources(
		directory: scratchDirectory,
		inputFiles: inputCompileFiles,
		generatedFiles: generatedCompileFiles,
	)
}

/// Compiles `sources` as one module and writes the object file into `outputDirectory`.
///
/// The compile emits an object file rather than stopping after type checking because some errors
/// in generated code are reported only once the compiler lowers the module to SIL: a nested
/// function that captures a local declared after it ("closure captures 'x' before it is
/// declared") is diagnosed while generating SIL, and `self` used before `self.init` or a constant
/// read before it is initialized is diagnosed by definite initialization, one of the mandatory SIL
/// passes. `-typecheck` reports none of these. Whole-module mode runs one frontend job for the
/// module instead of one per file, so the macro plugin and the `SafeDI` module load once; that
/// saves more than emitting the object file costs, so this is cheaper than per-file `-typecheck`.
///
/// - Parameter activeCompilationConditions: Conditions defined for the compile, mirroring what the
///   test supplied to SafeDITool. `DEBUG` is always defined, as it is in a debug build.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func compileSwift(
	sources: [URL],
	outputDirectory: URL,
	artifacts: SafeDIBuildArtifacts,
	activeCompilationConditions: [String] = [],
) throws -> SwiftCompileResult {
	let process = Process()
	#if os(Linux)
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		var arguments = ["swiftc"]
	#else
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		var arguments = ["swiftc"]
	#endif
	arguments.append(contentsOf: [
		"-emit-object",
		"-whole-module-optimization",
		"-o", outputDirectory.appendingPathComponent("SafeDICodegenVerification.o").path,
		"-module-name", "SafeDICodegenVerification",
		"-I", artifacts.swiftModuleSearchPath.path,
		"-load-plugin-executable", "\(artifacts.safeDIMacrosToolPath.path)#SafeDIMacros",
		"-DDEBUG",
		"-swift-version", "6",
	])
	arguments.append(contentsOf: Set(activeCompilationConditions).subtracting(["DEBUG"]).sorted().map { "-D\($0)" })
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

	return SwiftCompileResult(
		exitCode: process.terminationStatus,
		stdout: String(data: stdoutData.read(), encoding: .utf8) ?? "",
		stderr: String(data: stderrData.read(), encoding: .utf8) ?? "",
	)
}

/// Thread-safe `Data` accumulator used by `compileSwift` to collect pipe
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
