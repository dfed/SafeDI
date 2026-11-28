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
#if canImport(Glibc)
	import Glibc
#endif

/// The compile checks that passed in earlier runs, kept in a file so that CI compiles only the checks it has not seen
/// pass.
///
/// A compile check is one call of `verifyGeneratedCodeCompiles`, or of `verifyModulesCompile` that records issues: the
/// modules it compiles, each with its files as staged, its module layout and its compiler settings. Each check that
/// passes, every module compiling with no warning in generated code, appends its key to the file, and a later check
/// whose key the file holds compiles nothing. A check that fails or draws a warning is never written, so it compiles,
/// and fails, on every run.
///
/// The key covers everything a check's result depends on: what the test process decides
/// (`key(of:fixtureRoots:build:)`), and what compiles it (`CompileCheckBuild`), which is the compiler and SDK the
/// process finds in its own environment, the bytes of the SafeDI module it loads, and the dependency versions the
/// macro plugin it loads was built from. So a pass
/// recorded under one Xcode, toolchain, container, SDK or build of SafeDI is never read under another, however a job
/// came to run it. CI keeps one file per hash of the sources that decide what a pass is, this verifier's among them
/// (`.github/scripts/compile-check-identity.sh`).
///
/// A run also lists the checks its own processes passed in a file of its own beside the first
/// (`fileOfPassesInThisRun`), which is what CI shares with other branches: the first file also holds whatever the
/// job restored into it.
///
/// The `SAFEDI_COMPILE_CHECK_PASSED_CACHE` environment variable names the file. When it is unset, as it is by default
/// and in "Build and Test on Latest Swift", every check compiles.
struct PassedCompileCheckCache: Sendable {
	/// The environment variable that names the file of passed checks.
	static let environmentVariable = "SAFEDI_COMPILE_CHECK_PASSED_CACHE"

	/// The cache the `SAFEDI_COMPILE_CHECK_PASSED_CACHE` environment variable names, or `nil` when it names none. A
	/// process that uses it prints, when it exits, how many checks it compiled and how many it skipped.
	static let current: PassedCompileCheckCache? = {
		guard let path = ProcessInfo.processInfo.environment[environmentVariable], !path.isEmpty else { return nil }
		atexit {
			PassedCompileCheckCache.current?.printTally()
		}
		return PassedCompileCheckCache(file: URL(fileURLWithPath: path))
	}()

	/// A cache of the checks `file` lists, which records each check that passes from now on in `file`. A missing or
	/// unreadable file lists none.
	///
	/// - Parameter run: A name for the run this process is part of, by default GitHub's identifier of the workflow run
	///   (`GITHUB_RUN_ID`), or `nil` outside one. Only letters, digits and hyphens name a run.
	init(file: URL, run: String? = ProcessInfo.processInfo.environment["GITHUB_RUN_ID"]) {
		self.file = file
		if let run = Self.nameOfRun(run) {
			fileOfPassesInThisRun = file.deletingLastPathComponent().appendingPathComponent("passed-in-run-\(run).txt")
		} else {
			fileOfPassesInThisRun = nil
		}
		keysOfChecksThatPassedBefore = Set(
			((try? String(contentsOf: file, encoding: .utf8)) ?? "")
				.split(separator: "\n")
				.map(String.init),
		)
	}

	/// `run` when it can name a file of the run: when it is not empty and holds only letters, digits and hyphens.
	/// Otherwise `nil`, and the process keeps no file of what its run did.
	static func nameOfRun(_ run: String?) -> String? {
		guard let run, !run.isEmpty, run.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }) else {
			return nil
		}
		return run
	}

	/// The file of passed checks: one key per line.
	let file: URL

	/// The file of the checks that the processes of this run passed, beside `file` and named for the run, or `nil`
	/// when the process is part of no run. `file` also lists what a job restored into it before the tests, from its
	/// branch's cache and from the list all branches share, so only this file says what this run itself saw compile.
	/// It is the one `.github/actions/upload-passed-compile-checks` uploads to share, so that no restored line, right
	/// or wrong, reaches the shared list through a run that did not compile it.
	let fileOfPassesInThisRun: URL?

	/// Whether the check whose key is `key` passed in an earlier run, as the file read when this cache was made lists
	/// it. A `true` answer counts the check as skipped.
	func holds(_ key: String) -> Bool {
		guard keysOfChecksThatPassedBefore.contains(key) else {
			tally.countCompiled()
			return false
		}
		tally.countSkipped()
		return true
	}

	/// Counts a check that compiled without a key, because what compiles it could not be described, so that the
	/// process's last line says why nothing was skipped.
	func countCompiledWithoutAKey() {
		tally.countCompiledWithoutAKey()
	}

	/// Appends `key` to the file, and to the file of this run's passes when there is one, making each file and its
	/// directory when they do not exist yet.
	func recordPass(of key: String) throws {
		try Self.append(key, to: file)
		if let fileOfPassesInThisRun {
			try Self.append(key, to: fileOfPassesInThisRun)
		}
	}

	/// The key of the check that compiles `modules` in order with `build`: the SHA-256 of a canonical description of
	/// what compiles it (`CompileCheckBuild.description`, or any text that names one) and of each module's name, package, dependencies, whether it emits a module, its conditions, language mode and upcoming features,
	/// and the name and contents of each staged file, inputs in order and generated files in name order.
	///
	/// A file's contents can spell paths under the test process's directory, as an older release's `#sourceLocation`
	/// directives do, and fixture directories are named by UUIDs, so the same check spells other text in
	/// each run. The description replaces each of `fixtureRoots` with one fixed path and each distinct UUID with
	/// `00000000-0000-0000-0000-000000000001`, `…002` and so on, in the order the description first spells it, which
	/// keeps every path's length, distinctness and which paths are the same. Whether a check compiles does not depend
	/// on what those paths spell beyond that, so the key is the same in every run of the same check. Text that differs
	/// between runs in another way only costs the check its cache hit.
	static func key(of modules: [CompileCheckModule], fixtureRoots: [String] = currentFixtureRoots, build: String) throws -> String {
		var normalization = CompileCheckTextNormalization(fixtureRoots: fixtureRoots)
		func files(_ urls: [URL]) throws -> [CompileCheckDescription.File] {
			try urls.map { url in
				try CompileCheckDescription.File(
					name: url.lastPathComponent,
					contents: normalization.normalizing(String(contentsOf: url, encoding: .utf8)),
				)
			}
		}
		var describedModules = [CompileCheckDescription.Module]()
		for module in modules {
			try describedModules.append(CompileCheckDescription.Module(
				name: module.sources.moduleName,
				packageName: module.sources.packageName,
				dependencyModuleNames: module.sources.dependencyModuleNames,
				emitsModule: module.emitsModule,
				definesDebug: module.sources.definesDebug,
				compilationConditions: Set(module.sources.compilationConditions).subtracting(["DEBUG"]).sorted(),
				swiftLanguageMode: module.sources.compilerSettings.swiftLanguageMode,
				upcomingFeatures: module.sources.compilerSettings.upcomingFeatures,
				defaultIsolation: module.sources.compilerSettings.defaultIsolation,
				memoryLimitInMegabytes: module.sources.compilerSettings.memoryLimitInMegabytes,
				inputFiles: files(module.staged.inputFiles),
				generatedFiles: files(module.staged.generatedFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }),
			))
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return try sha256HexDigest(of: encoder.encode(CompileCheckDescription(formatVersion: 2, build: build, modules: describedModules)))
	}

	/// The test process's directory, as spelled and with symbolic links resolved, under which every fixture and
	/// staged file lies.
	static var currentFixtureRoots: [String] {
		[TestTemporaryDirectory.root.path, TestTemporaryDirectory.root.resolvingSymlinksInPath().path]
	}

	// MARK: Private

	private let keysOfChecksThatPassedBefore: Set<String>
	private let tally = PassedCompileCheckTally()

	/// Appends `key` to `file`. One `write` of one line to a file opened for appending, so test processes that share
	/// the file do not interleave their lines.
	static func append(_ key: String, to file: URL) throws {
		try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard descriptor >= 0 else {
			throw PassedCompileCheckCacheError(description: "Could not open \(file.path) to record a passed compile check (errno \(errno)).")
		}
		defer { close(descriptor) }
		let line = Array((key + "\n").utf8)
		let writtenByteCount = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
		guard writtenByteCount == line.count else {
			throw PassedCompileCheckCacheError(description: "Could not record a passed compile check in \(file.path) (errno \(errno)).")
		}
	}

	/// What the process prints when it exits: how many checks compiled and how many were skipped, and how many
	/// compiled without a key when what compiles them could not be described.
	var tallyLine: String {
		let counts = tally.counts
		var line = "Compile checks: \(counts.compiled) compiled, \(counts.skipped) skipped because they passed in an earlier run"
		if counts.compiledWithoutAKey > 0 {
			line += ", \(counts.compiledWithoutAKey) compiled without being looked up or recorded because what compiles them could not be described"
		}
		line += " (\(Self.environmentVariable)=\(file.path))."
		return line
	}

	private func printTally() {
		FileHandle.standardError.write(Data((tallyLine + "\n").utf8))
	}
}

/// One module of a compile check: what it is given, its files as staged, and whether its compile emits a module.
struct CompileCheckModule {
	let sources: ModuleCompileSources
	let staged: StagedCompileSources
	let emitsModule: Bool
}

struct PassedCompileCheckCacheError: Error, CustomStringConvertible {
	let description: String
}

/// What compiles this process's checks, which every check's key includes: the compiler and SDK, as the compiler
/// itself reports them, the SafeDI module each check imports, by its bytes, and the versions of the packages the
/// macro plugin each check loads was built from.
///
/// The compiler is asked through `swiftCompilerCommand` in this process's environment, as each check's compile is,
/// so the description names the compiler a check would run under whatever chose it: the selected Xcode,
/// `DEVELOPER_DIR`, `TOOLCHAINS`, `SDKROOT`, a container's image or the runner's. The module is read where the
/// verifier loads it, so it names what was built whatever built it: another job, other flags, another build system.
/// Nothing a workflow says about either is hashed in their place, so a workflow edit that changes none of this keeps
/// every passed check, and one that changes any of it compiles every check again without anyone listing which lines
/// count.
///
/// The plugin is not described by its bytes, because they are not the same in two builds of the same sources: two
/// clean release builds on Linux's Swift 6.2 differ in the build identifier, the `.swift_modhash` section and
/// debugging information, so a key made from them would never be found again after a build from nothing. Its
/// sources are SafeDI's, which CI's hash of the list covers (`.github/scripts/compile-check-identity.sh`), and
/// swift-syntax's, which the build's own record of what it resolved names (`workspace-state.json` in the build
/// directory), whatever `Package.resolved` says.
///
/// Two things about the plugin are deliberately not in the key, and `.claude/rules/passed-compile-checks.md` says
/// so too. The compiler that built the plugin is not: CI builds it with the compiler that compiles the checks, and
/// a job that built it with another would have to be written to. And of a build directory that holds two
/// configurations, the description names which one the verifier chose but not when it was built, so a plugin left
/// by an older build of the same configuration, beside a current SafeDI module, is read as current; a build of the
/// tests rebuilds both.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum CompileCheckBuild {
	/// What `describe(artifacts:)` returns for the build artifacts the verifier locates, asked once per process, or
	/// `nil` when it could not be asked, twice, which is said once on standard error. A check is then compiled without
	/// a key: nothing is skipped and nothing recorded, and the cache counts it (`countCompiledWithoutAKey()`).
	static var description: String? {
		get async {
			try? await shared.value
		}
	}

	/// What the compiler reports of itself in `environment` (its version, its target information, which names its
	/// default target, its runtime's compatibility version and the paths it compiles against, and on Apple platforms
	/// the version and build of the SDK `xcrun` compiles with), on Linux the distribution the process runs on
	/// (`/etc/os-release`), whose libraries a check compiles against, the SHA-256 of `artifacts`' SafeDI module, and
	/// the configuration directory that holds `artifacts`' macro plugin, by its last two names, and each package the
	/// build that made the plugin resolved, with the version and revision it resolved it at.
	static func describe(
		artifacts: SafeDIBuildArtifacts,
		environment: [String: String] = ProcessInfo.processInfo.environment,
	) async throws -> String {
		var commands = [
			(swiftCompilerCommand.executable, swiftCompilerCommand.arguments + ["--version"]),
			(swiftCompilerCommand.executable, swiftCompilerCommand.arguments + ["-print-target-info"]),
		]
		#if !os(Linux)
			commands.append((URL(fileURLWithPath: "/usr/bin/xcrun"), ["--show-sdk-version"]))
			commands.append((URL(fileURLWithPath: "/usr/bin/xcrun"), ["--show-sdk-build-version"]))
		#endif
		var description = ""
		for (executable, arguments) in commands {
			let result = try await runProcess(executable, arguments: arguments, environment: environment)
			guard result.exitCode == 0 else {
				throw PassedCompileCheckCacheError(description: """
				Could not describe the compiler that compiles the checks: \(executable.path) \(arguments.joined(separator: " ")) \
				exited with \(result.exitCode).
				\(result.stderr)
				""")
			}
			description += result.stdout
			description += result.stderr
		}
		#if os(Linux)
			description += try String(contentsOf: URL(fileURLWithPath: "/etc/os-release"), encoding: .utf8)
		#endif
		let module = artifacts.swiftModuleSearchPath.appendingPathComponent("SafeDI.swiftmodule")
		description += "SafeDI.swiftmodule\n"
		for file in try regularFiles(at: module) {
			description += try "\(file.name) \(sha256HexDigest(of: Data(contentsOf: file.url)))\n"
		}
		// Which of a build directory's configurations the verifier chose, so that a pass with one's plugin is not read
		// with another's.
		let products = artifacts.safeDIMacrosToolPath.deletingLastPathComponent()
		description += "Products \(products.deletingLastPathComponent().lastPathComponent)/\(products.lastPathComponent)\n"
		description += "Resolved packages\n"
		description += try resolvedPackages(ofTheBuildThatMade: artifacts.safeDIMacrosToolPath)
		return description
	}

	/// One line per package the build that made `product` depends on, in name order: its identity and the state the
	/// build resolved it to, which for a package under source control is its revision and version. Read from
	/// `workspace-state.json`, which SwiftPM keeps in the build directory, above a product by as many directories as
	/// the build system's layout has (two with the native build system, four with Swift Build); a job that runs the
	/// tests of another job's build carries the file with the products. The search stops at a directory named
	/// `.build` or one that holds a `Package.swift`. Fails when it finds none, as in a build Xcode made in its own
	/// derived data: a key that leaves the dependencies out would stand for every version of them.
	private static func resolvedPackages(ofTheBuildThatMade product: URL) throws -> String {
		var directory = product.deletingLastPathComponent().standardizedFileURL
		var workspaceState: URL?
		while true {
			let candidate = directory.appendingPathComponent("workspace-state.json")
			if FileManager.default.fileExists(atPath: candidate.path) {
				workspaceState = candidate
				break
			}
			// No further than the build directory or the package, so that no other package's record is read.
			let isThePackage = FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path)
			let parent = directory.deletingLastPathComponent().standardizedFileURL
			guard directory.lastPathComponent != ".build", !isThePackage, parent.path != directory.path else { break }
			directory = parent
		}
		guard let workspaceState,
		      let state = try JSONSerialization.jsonObject(with: Data(contentsOf: workspaceState)) as? [String: Any],
		      let object = state["object"] as? [String: Any],
		      let dependencies = object["dependencies"] as? [[String: Any]]
		else {
			throw PassedCompileCheckCacheError(description: "Found no workspace-state.json that lists dependencies above \(product.path) to describe the build that compiles the checks.")
		}
		var lines = [String]()
		for dependency in dependencies {
			guard let package = dependency["packageRef"] as? [String: Any],
			      let identity = package["identity"] as? String,
			      let resolved = dependency["state"]
			else {
				throw PassedCompileCheckCacheError(description: "\(workspaceState.path) lists a dependency without an identity or a state.")
			}
			let spelledState = try String(decoding: JSONSerialization.data(withJSONObject: resolved, options: [.sortedKeys]), as: UTF8.self)
			lines.append("\(identity) \(spelledState)\n")
		}
		return lines.sorted().joined()
	}

	/// `url` itself when it is a file, named by its last path component, or every regular file under it when it is a
	/// directory, as Xcode and Swift Build write a module (one file per architecture), each named by its path under
	/// `url`, in name order. Fails when there is none.
	private static func regularFiles(at url: URL) throws -> [(name: String, url: URL)] {
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
			throw PassedCompileCheckCacheError(description: "Found no SafeDI module at \(url.path) to describe the build that compiles the checks.")
		}
		guard isDirectory.boolValue else {
			return [(url.lastPathComponent, url)]
		}
		var files = [(name: String, url: URL)]()
		for name in try FileManager.default.subpathsOfDirectory(atPath: url.path).sorted() {
			let file = url.appendingPathComponent(name)
			var isDirectory: ObjCBool = false
			if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue {
				files.append((name, file))
			}
		}
		guard !files.isEmpty else {
			throw PassedCompileCheckCacheError(description: "Found no file in the SafeDI module at \(url.path) to describe the build that compiles the checks.")
		}
		return files
	}

	private static let shared = SharedTestWork<String?> {
		guard let artifacts = SafeDIBuildArtifactLocator.locate() else {
			// The verifier records an issue for every check when it finds no build.
			return nil
		}
		do {
			return try await describe(artifacts: artifacts)
		} catch {
			// Once more, since one failed launch of the compiler would otherwise cost the process every skip.
			do {
				return try await describe(artifacts: artifacts)
			} catch {
				FileHandle.standardError.write(Data("""
				Compile checks: none skipped or recorded, because what compiles them could not be described.
				\(error)

				""".utf8))
				return nil
			}
		}
	}
}

/// What a compile check's key is the hash of. `JSONEncoder` with sorted keys gives it one spelling.
private struct CompileCheckDescription: Encodable {
	struct File: Encodable {
		let name: String
		let contents: String
	}

	struct Module: Encodable {
		let name: String
		let packageName: String?
		let dependencyModuleNames: [String]
		let emitsModule: Bool
		let definesDebug: Bool
		let compilationConditions: [String]
		let swiftLanguageMode: String
		let upcomingFeatures: [String]
		/// Encoded only when set, so that a check that sets none keeps the key it had before the setting existed.
		let defaultIsolation: String?
		/// Encoded only when set, as `defaultIsolation` is: a limit decides whether a compile that needs more memory passes.
		let memoryLimitInMegabytes: Int?
		let inputFiles: [File]
		let generatedFiles: [File]
	}

	let formatVersion: Int
	let build: String
	let modules: [Module]
}

/// Rewrites the text of one compile check so that what differs between runs of it does not: each fixture root
/// becomes `/safedi-test-root`, and each distinct UUID becomes the next of `00000000-0000-0000-0000-000000000001`,
/// `…002` and so on, in the order the check first spells it.
struct CompileCheckTextNormalization {
	init(fixtureRoots: [String]) {
		// The longest first, so that a root that holds another is replaced whole.
		self.fixtureRoots = Set(fixtureRoots.filter { !$0.isEmpty }).sorted { ($0.count, $0) > ($1.count, $1) }
	}

	mutating func normalizing(_ text: String) -> String {
		var text = text
		for fixtureRoot in fixtureRoots {
			text = text.replacingOccurrences(of: fixtureRoot, with: "/safedi-test-root")
		}
		// A UUID is ASCII, and so is its replacement, which has the same length, so the text is rewritten byte by byte.
		var bytes = Array(text.utf8)
		var index = 0
		while index + Self.uuidLength <= bytes.count {
			let candidate = index..<(index + Self.uuidLength)
			guard Self.isUUID(bytes[candidate]) else {
				index += 1
				continue
			}
			let uuid = String(decoding: bytes[candidate], as: UTF8.self)
			let number = numberByUUID[uuid] ?? numberByUUID.count + 1
			numberByUUID[uuid] = number
			let digits = String(number)
			let replacement = "00000000-0000-0000-0000-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits
			bytes.replaceSubrange(candidate, with: Array(replacement.utf8))
			index += Self.uuidLength
		}
		return String(decoding: bytes, as: UTF8.self)
	}

	private let fixtureRoots: [String]
	private var numberByUUID = [String: Int]()

	/// The length of a UUID's text, such as `E621E1F8-C36C-495A-93FC-0C247A3E6E5F`.
	private static let uuidLength = 36
	private static let hyphenOffsets: Set = [8, 13, 18, 23]

	/// Whether `bytes` spell a UUID: hexadecimal digits in groups of 8, 4, 4, 4 and 12, joined by hyphens.
	private static func isUUID(_ bytes: ArraySlice<UInt8>) -> Bool {
		for (offset, byte) in bytes.enumerated() {
			let isHexadecimalDigit = (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
				|| (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
				|| (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
			guard hyphenOffsets.contains(offset) ? byte == UInt8(ascii: "-") : isHexadecimalDigit else { return false }
		}
		return true
	}
}

/// How many checks a cache compiled and skipped, counted from the tests that run in parallel.
private final class PassedCompileCheckTally: Sendable {
	var counts: (compiled: Int, skipped: Int, compiledWithoutAKey: Int) {
		lock.withLock { (compiled, skipped, compiledWithoutAKey) }
	}

	func countCompiledWithoutAKey() {
		lock.withLock { compiledWithoutAKey += 1 }
	}

	func countCompiled() {
		lock.withLock { compiled += 1 }
	}

	func countSkipped() {
		lock.withLock { skipped += 1 }
	}

	private let lock = NSLock()
	nonisolated(unsafe) private var compiled = 0
	nonisolated(unsafe) private var skipped = 0
	nonisolated(unsafe) private var compiledWithoutAKey = 0
}

/// The SHA-256 digest (FIPS 180-4) of `data`, as 64 lowercase hexadecimal digits. Foundation offers no SHA-256 on
/// Linux, and the test targets depend on no cryptography package. `a` through `h` and the round constants are the
/// standard's names.
func sha256HexDigest(of data: Data) -> String {
	var hash: [UInt32] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
	var message = [UInt8](data)
	let bitCount = UInt64(message.count) * 8
	message.append(0x80)
	while message.count % 64 != 56 {
		message.append(0)
	}
	for shift in stride(from: 56, through: 0, by: -8) {
		message.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
	}
	func rotatedRight(_ value: UInt32, by count: UInt32) -> UInt32 {
		(value >> count) | (value << (32 - count))
	}
	var schedule = [UInt32](repeating: 0, count: 64)
	for blockStart in stride(from: 0, to: message.count, by: 64) {
		for index in 0..<16 {
			let byteIndex = blockStart + index * 4
			schedule[index] = UInt32(message[byteIndex]) << 24 | UInt32(message[byteIndex + 1]) << 16 | UInt32(message[byteIndex + 2]) << 8 | UInt32(message[byteIndex + 3])
		}
		for index in 16..<64 {
			let sigma0 = rotatedRight(schedule[index - 15], by: 7) ^ rotatedRight(schedule[index - 15], by: 18) ^ (schedule[index - 15] >> 3)
			let sigma1 = rotatedRight(schedule[index - 2], by: 17) ^ rotatedRight(schedule[index - 2], by: 19) ^ (schedule[index - 2] >> 10)
			schedule[index] = schedule[index - 16] &+ sigma0 &+ schedule[index - 7] &+ sigma1
		}
		var a = hash[0], b = hash[1], c = hash[2], d = hash[3], e = hash[4], f = hash[5], g = hash[6], h = hash[7]
		for index in 0..<64 {
			let sum1 = rotatedRight(e, by: 6) ^ rotatedRight(e, by: 11) ^ rotatedRight(e, by: 25)
			let choice = (e & f) ^ (~e & g)
			let temporary1 = h &+ sum1 &+ choice &+ sha256RoundConstants[index] &+ schedule[index]
			let sum0 = rotatedRight(a, by: 2) ^ rotatedRight(a, by: 13) ^ rotatedRight(a, by: 22)
			let majority = (a & b) ^ (a & c) ^ (b & c)
			let temporary2 = sum0 &+ majority
			h = g
			g = f
			f = e
			e = d &+ temporary1
			d = c
			c = b
			b = a
			a = temporary1 &+ temporary2
		}
		for (index, value) in [a, b, c, d, e, f, g, h].enumerated() {
			hash[index] &+= value
		}
	}
	return hash.map { word in
		let digits = String(word, radix: 16)
		return String(repeating: "0", count: 8 - digits.count) + digits
	}.joined()
}

private let sha256RoundConstants: [UInt32] = [
	0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
	0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
	0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
	0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
	0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
	0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
	0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
	0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
]
