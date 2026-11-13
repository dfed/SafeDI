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
/// The key covers everything about a check that the test process decides (`key(of:fixtureRoots:)`), and nothing
/// about what compiles it: the SafeDI module, the macro plugin, the compiler and the SDK. So a file is valid only for
/// one build of those. CI keys its cache of the file on a hash of them (`.github/scripts/compile-check-identity.sh`)
/// and the sources of this verifier, and starts from an empty file whenever any of them changes.
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
	init(file: URL) {
		self.file = file
		keysOfChecksThatPassedBefore = Set(
			((try? String(contentsOf: file, encoding: .utf8)) ?? "")
				.split(separator: "\n")
				.map(String.init),
		)
	}

	/// The file of passed checks: one key per line.
	let file: URL

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

	/// Appends `key` to the file, making the file and its directory when they do not exist yet. One `write` of one
	/// line to a file opened for appending, so test processes that share the file do not interleave their lines.
	func recordPass(of key: String) throws {
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

	/// The key of the check that compiles `modules` in order: the SHA-256 of a canonical description of each module's
	/// name, package, dependencies, whether it emits a module, its conditions, language mode and upcoming features,
	/// and the name and contents of each staged file, inputs in order and generated files in name order.
	///
	/// A file's contents spell paths under the test process's directory, as `#sourceLocation` directives and
	/// `// Declared at` comments do, and fixture directories are named by UUIDs, so the same check spells other text in
	/// each run. The description replaces each of `fixtureRoots` with one fixed path and each distinct UUID with
	/// `00000000-0000-0000-0000-000000000001`, `…002` and so on, in the order the description first spells it, which
	/// keeps every path's length, distinctness and which paths are the same. Whether a check compiles does not depend
	/// on what those paths spell beyond that, so the key is the same in every run of the same check. Text that differs
	/// between runs in another way only costs the check its cache hit.
	static func key(of modules: [CompileCheckModule], fixtureRoots: [String] = currentFixtureRoots) throws -> String {
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
				concurrencyArguments: module.sources.compilerSettings.concurrencyArguments.isEmpty ? nil : module.sources.compilerSettings.concurrencyArguments,
				inputFiles: files(module.staged.inputFiles),
				generatedFiles: files(module.staged.generatedFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }),
			))
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return try sha256HexDigest(of: encoder.encode(CompileCheckDescription(formatVersion: 1, modules: describedModules)))
	}

	/// The test process's directory, as spelled and with symbolic links resolved, under which every fixture and
	/// staged file lies.
	static var currentFixtureRoots: [String] {
		[TestTemporaryDirectory.root.path, TestTemporaryDirectory.root.resolvingSymlinksInPath().path]
	}

	// MARK: Private

	private let keysOfChecksThatPassedBefore: Set<String>
	private let tally = PassedCompileCheckTally()

	private func printTally() {
		let counts = tally.counts
		FileHandle.standardError.write(Data("""
		Compile checks: \(counts.compiled) compiled, \(counts.skipped) skipped because they passed in an earlier run \
		(\(Self.environmentVariable)=\(file.path)).

		""".utf8))
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
		/// Encoded only when there are some, for `defaultIsolation`'s reason.
		let concurrencyArguments: [String]?
		let inputFiles: [File]
		let generatedFiles: [File]
	}

	let formatVersion: Int
	let modules: [Module]
}

/// Rewrites the text of one compile check so that what differs between runs of it does not: each fixture root
/// becomes `/safedi-test-root`, and each distinct UUID becomes the next of `00000000-0000-0000-0000-000000000001`,
/// `…002` and so on, in the order the check first spells it.
private struct CompileCheckTextNormalization {
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
	var counts: (compiled: Int, skipped: Int) {
		lock.withLock { (compiled, skipped) }
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
