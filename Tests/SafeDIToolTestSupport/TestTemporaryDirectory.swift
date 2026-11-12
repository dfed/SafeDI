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

// `SafeDICoreTests` and `SafeDIGeneratorPluginTests`, which do not depend on `SafeDIToolTestSupport`, compile this
// file through symbolic links, so it imports nothing but Foundation and the C library.
import Foundation
#if canImport(Glibc)
	import Glibc
#endif

/// The directory every temporary file a test makes goes under, instead of the system temporary directory.
///
/// macOS empties the user's temporary directory (`$TMPDIR`) at every startup, before login, and a folder holding
/// millions of entries left by test runs that were killed before their cleanup ran made a Mac hang at the Apple logo
/// for hours. So no test, test helper, or process a test launches writes there: each test process makes one directory
/// of its own, `test-run-<process identifier>-<UUID>`, under the directory the `SAFEDI_TEST_TEMPORARY_DIRECTORY`
/// environment variable names, or else under `SafeDITests` in the user's caches directory (`~/Library/Caches` on
/// macOS, `~/.cache` on Linux), which nothing empties at startup. The default is outside every checkout because the
/// tests put fixtures outside the working directory, as the system temporary directory was: a fixture under the
/// working directory, which `swift test` sets to the package's root, would lie inside the project that `scan` and
/// `generate` take the working directory to be, which changes what the tests of additional directories see. The
/// process deletes its directory when it exits normally; a killed process cannot, so each process, when it makes its
/// own, deletes the directories of processes that no longer run.
enum TestTemporaryDirectory {
	/// The environment variable that names the directory to make each test process's directory in, in place of
	/// `SafeDITests` in the user's caches directory.
	static let parentDirectoryEnvironmentVariable = "SAFEDI_TEST_TEMPORARY_DIRECTORY"

	/// This test process's directory, made the first time a test asks for it. Every temporary path a test or a test
	/// helper makes is under it.
	///
	/// When the directory cannot be made, the first write under it fails, naming the path.
	static let root: URL = makeRoot()

	/// A new path under `root`, named by a UUID after `prefix`, with `pathExtension` when it is not `nil`. Nothing is
	/// made at the path.
	static func uniquePath(prefix: String = "", pathExtension: String? = nil) -> URL {
		let path = root.appendingPathComponent(prefix + UUID().uuidString)
		guard let pathExtension else { return path }
		return path.appendingPathExtension(pathExtension)
	}

	/// The environment of a process a test launches, which is this process's environment with `TMPDIR` set to
	/// `temporaryDirectory`, so that what the process writes to its temporary directory, as the `TemporaryDirectory.*`
	/// folders `swiftc` leaves behind, lands under `root` and goes when the caller deletes `temporaryDirectory`.
	static func environment(
		withTemporaryDirectory temporaryDirectory: URL,
		from environment: [String: String] = ProcessInfo.processInfo.environment,
	) -> [String: String] {
		var environment = environment
		environment["TMPDIR"] = temporaryDirectory.path + "/"
		return environment
	}

	/// The prefix of the name of each test process's directory.
	static let rootNamePrefix = "test-run-"

	/// How long a test process's directory may go unmodified before a later process deletes it although the process
	/// that made it seems to still run: a process identifier can be reused, and a running test process adds and
	/// removes entries in its directory all the time.
	private static let abandonedRootAge: TimeInterval = 24 * 60 * 60

	private static func makeRoot() -> URL {
		let parentDirectory = parentDirectoryOfRoots()
		removeAbandonedRoots(in: parentDirectory)
		let processIdentifier = ProcessInfo.processInfo.processIdentifier
		let root = parentDirectory.appendingPathComponent("\(rootNamePrefix)\(processIdentifier)-\(UUID().uuidString)", isDirectory: true)
		try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		atexit {
			try? FileManager.default.removeItem(at: TestTemporaryDirectory.root)
		}
		return root
	}

	/// The directory named by `SAFEDI_TEST_TEMPORARY_DIRECTORY`, or else `SafeDITests` in the user's caches directory.
	private static func parentDirectoryOfRoots() -> URL {
		if let path = ProcessInfo.processInfo.environment[parentDirectoryEnvironmentVariable], !path.isEmpty {
			URL(fileURLWithPath: path, isDirectory: true)
		} else {
			(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".cache", isDirectory: true))
				.appendingPathComponent("SafeDITests", isDirectory: true)
		}
	}

	/// Deletes each test process's directory in `parentDirectory` whose process no longer runs, or that has gone
	/// unmodified for a day as of `now`. Nothing else in `parentDirectory` is touched.
	static func removeAbandonedRoots(in parentDirectory: URL, now: Date = Date()) {
		guard let entries = try? FileManager.default.contentsOfDirectory(
			at: parentDirectory,
			includingPropertiesForKeys: [.contentModificationDateKey],
		) else {
			return
		}
		for entry in entries where entry.lastPathComponent.hasPrefix(rootNamePrefix) {
			let modificationDate = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
			let isOld = modificationDate.map { now.timeIntervalSince($0) > abandonedRootAge } ?? false
			guard isOld || !processRuns(identifiedIn: entry.lastPathComponent) else { continue }
			try? FileManager.default.removeItem(at: entry)
		}
	}

	/// Whether the process whose identifier the name of a test process's directory holds still runs. A name that holds
	/// no identifier is treated as a running process's, so that the directory goes only once it is old.
	private static func processRuns(identifiedIn rootName: String) -> Bool {
		let identifierAndUUID = rootName.dropFirst(rootNamePrefix.count)
		guard let identifierText = identifierAndUUID.split(separator: "-", maxSplits: 1).first,
		      let processIdentifier = pid_t(identifierText),
		      processIdentifier > 0
		else {
			return true
		}
		// A signal of 0 checks only that the process exists. `EPERM` means it exists but belongs to another user.
		return kill(processIdentifier, 0) == 0 || errno == EPERM
	}
}
