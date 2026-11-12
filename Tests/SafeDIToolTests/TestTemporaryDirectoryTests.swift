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
@testable import SafeDIToolTestSupport

/// Where the tests put their temporary files, and how a test process deletes what killed test processes left there.
struct TestTemporaryDirectoryTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		parentDirectory = TestTemporaryDirectory.uniquePath(prefix: "safedi-temporary-directory-tests-")
		try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
	}

	deinit {
		try? FileManager.default.removeItem(at: parentDirectory)
	}

	// MARK: Tests – The tests' temporary directory

	@Test
	func root_isADirectoryOfThisProcessOutsideTheSystemTemporaryDirectory() {
		let systemTemporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().pathComponents
		let root = TestTemporaryDirectory.root.resolvingSymlinksInPath().pathComponents

		#expect(TestTemporaryDirectory.root.lastPathComponent.hasPrefix("\(TestTemporaryDirectory.rootNamePrefix)\(ProcessInfo.processInfo.processIdentifier)-"))
		#expect(!root.starts(with: systemTemporaryDirectory))
	}

	// MARK: Tests – Removing abandoned directories

	@Test
	func removeAbandonedRoots_removesTheDirectory_whenItsProcessNoLongerRuns() throws {
		let root = try makeRoot(processIdentifier: exitedProcessIdentifier())

		TestTemporaryDirectory.removeAbandonedRoots(in: parentDirectory)

		#expect(!FileManager.default.fileExists(atPath: root.path))
	}

	@Test
	func removeAbandonedRoots_keepsTheDirectory_whenItsProcessRuns() throws {
		let root = try makeRoot(processIdentifier: ProcessInfo.processInfo.processIdentifier)

		TestTemporaryDirectory.removeAbandonedRoots(in: parentDirectory)

		#expect(FileManager.default.fileExists(atPath: root.path))
	}

	@Test
	func removeAbandonedRoots_removesTheDirectory_whenItsProcessRunsButItWentUnmodifiedForADay() throws {
		let root = try makeRoot(processIdentifier: ProcessInfo.processInfo.processIdentifier)

		TestTemporaryDirectory.removeAbandonedRoots(in: parentDirectory, now: Date().addingTimeInterval(25 * 60 * 60))

		#expect(!FileManager.default.fileExists(atPath: root.path))
	}

	@Test
	func removeAbandonedRoots_keepsAnEntryNotNamedAsATestProcessDirectory() throws {
		let directory = parentDirectory.appendingPathComponent("heavy-\(try exitedProcessIdentifier())")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		TestTemporaryDirectory.removeAbandonedRoots(in: parentDirectory, now: Date().addingTimeInterval(25 * 60 * 60))

		#expect(FileManager.default.fileExists(atPath: directory.path))
	}

	// MARK: Tests – Running a process

	@Test
	func runProcess_givesTheProcessATemporaryDirectoryUnderTheRoot() throws {
		let result = try runProcess(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf %s \"$TMPDIR\""])

		#expect(result.stdout.hasPrefix(TestTemporaryDirectory.root.path + "/"), "Unexpected TMPDIR \(result.stdout)")
	}

	@Test
	func runProcess_deletesWhatTheProcessWroteToItsTemporaryDirectory_whenTheProcessExits() throws {
		let result = try runProcess(
			URL(fileURLWithPath: "/bin/sh"),
			arguments: ["-c", "mkdir \"${TMPDIR}TemporaryDirectory.test\" && printf %s \"${TMPDIR}TemporaryDirectory.test\""],
		)

		#expect(result.exitCode == 0)
		#expect(!result.stdout.isEmpty)
		#expect(!FileManager.default.fileExists(atPath: result.stdout), "\(result.stdout) outlived its process")
	}

	// MARK: Private

	private let parentDirectory: URL

	/// Makes, in `parentDirectory`, a directory named as the process with `processIdentifier` names its own.
	private func makeRoot(processIdentifier: Int32) throws -> URL {
		let root = parentDirectory.appendingPathComponent("\(TestTemporaryDirectory.rootNamePrefix)\(processIdentifier)-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Fixture"), withIntermediateDirectories: true)
		return root
	}

	/// The identifier of a process that has exited, which no other process takes in the moment before the test reads it.
	private func exitedProcessIdentifier() throws -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", "exit 0"]
		process.environment = TestTemporaryDirectory.environment(withTemporaryDirectory: parentDirectory)
		try process.run()
		process.waitUntilExit()
		return process.processIdentifier
	}
}
