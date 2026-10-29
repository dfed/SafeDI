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
@testable import SafeDICore

struct FilePathSpellingTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: fixtureDirectory.appendingPathComponent("Project/Sources"), withIntermediateDirectories: true)
		// On Apple platforms, Foundation removes a leading `/private` only from a path that names an existing file.
		try "".write(to: fixtureDirectory.appendingPathComponent("Project/Sources/File.swift"), atomically: true, encoding: .utf8)
		try FileManager.default.createSymbolicLink(
			at: fixtureDirectory.appendingPathComponent("Link"),
			withDestinationURL: fixtureDirectory.appendingPathComponent("Project"),
		)
	}

	deinit {
		try! FileManager.default.removeItem(at: fixtureDirectory)
	}

	// MARK: Tests

	@Test
	func normalizedFilePath_removesDotComponentsAndRepeatedSeparators() {
		#expect(NormalizedFilePath("/Project/./Sources//../Sources/File.swift").path == "/Project/Sources/File.swift")
	}

	@Test
	func normalizedFilePath_makesPathAbsolute_whenPathIsRelativeToDirectory() {
		#expect(NormalizedFilePath("Sources/File.swift", relativeTo: "/Project").path == "/Project/Sources/File.swift")
	}

	@Test
	func normalizedFilePath_ordersByPath() {
		#expect([NormalizedFilePath("/B.swift"), NormalizedFilePath("/A.swift")].sorted() == [NormalizedFilePath("/A.swift"), NormalizedFilePath("/B.swift")])
	}

	@Test
	func pathRelativeTo_returnsRelativePath_whenPathIsInsideDirectory() {
		#expect(NormalizedFilePath("/Project/Sources/File.swift").path(relativeTo: NormalizedFilePath("/Project")) == "Sources/File.swift")
	}

	@Test
	func pathRelativeTo_returnsWholePath_whenPathIsOutsideDirectory() {
		// A sibling whose name starts with the directory's name is outside it.
		#expect(NormalizedFilePath("/ProjectSibling/File.swift").path(relativeTo: NormalizedFilePath("/Project")) == "/ProjectSibling/File.swift")
	}

	@Test
	func pathUnder_spellsPathUnderDirectoryAsSpelled_whenPathIsInsideDirectory() {
		// The caller's spelling of the directory is kept, with or without a trailing `/`, and the file follows it.
		#expect(NormalizedFilePath("/Project/Sources/File.swift").path(under: NormalizedFilePath("/Project/Sources"), spelled: "Sources/") == "Sources/File.swift")
		#expect(NormalizedFilePath("/Project/Sources/Nested/File.swift").path(under: NormalizedFilePath("/Project/Sources"), spelled: "../Project/Sources") == "../Project/Sources/Nested/File.swift")
	}

	@Test
	func pathUnder_returnsNormalizedPath_whenPathIsOutsideDirectory() {
		// A file the directory does not contain cannot be spelled under it.
		#expect(NormalizedFilePath("/ProjectSibling/File.swift").path(under: NormalizedFilePath("/Project"), spelled: "Project") == "/ProjectSibling/File.swift")
	}

	@Test
	func reportsResolvedProjectRoot_isTrue_whenRootIsSpelledAsResolved() throws {
		#expect(try ProjectFilePaths(projectRoot: resolvedProjectRoot).reportsResolvedProjectRoot)
	}

	@Test
	func reportsResolvedProjectRoot_isFalse_whenRootIsReportedThroughSymbolicLink() {
		#expect(!ProjectFilePaths(projectRoot: linkedProjectRoot).reportsResolvedProjectRoot)
	}

	@Test
	func reportsResolvedProjectRoot_isFalse_whenRootDoesNotExist() {
		#expect(!ProjectFilePaths(projectRoot: "/\(UUID().uuidString)").reportsResolvedProjectRoot)
	}

	@Test
	func reportedProjectRoot_isAbsoluteWithoutTrailingSlash_whenRootIsRelativeOrEndsInSlash() {
		#expect(ProjectFilePaths(projectRoot: ".").reportedProjectRoot == FileManager.default.currentDirectoryPath)
		#expect(ProjectFilePaths(projectRoot: "\(linkedProjectRoot)/").reportedProjectRoot == linkedProjectRoot)
	}

	@Test
	func projectFilePath_isTheSame_whenProjectRootIsReportedThroughSymbolicLinkOrResolved() throws {
		let throughSymbolicLink = ProjectFilePaths(projectRoot: linkedProjectRoot)
		let resolved = try ProjectFilePaths(projectRoot: resolvedProjectRoot)

		// A path relative to the root, an absolute path through the link, and an absolute path resolved all name
		// the same file.
		let spellings = try [
			throughSymbolicLink.projectFilePath(of: "Sources/File.swift"),
			throughSymbolicLink.projectFilePath(of: "\(linkedProjectRoot)/Sources/File.swift"),
			throughSymbolicLink.projectFilePath(of: NormalizedFilePath("\(resolvedProjectRoot)/Sources/File.swift")),
			resolved.projectFilePath(of: "Sources/File.swift"),
		]
		#expect(Set(spellings).count == 1)
	}

	@Test
	func projectFilePath_isResolvedRoot_whenPathIsProjectRootReportedThroughSymbolicLink() throws {
		let projectFilePaths = ProjectFilePaths(projectRoot: linkedProjectRoot)

		#expect(try projectFilePaths.projectFilePath(of: ".") == projectFilePaths.projectFilePath(of: resolvedProjectRoot))
		#expect(projectFilePaths.projectFilePath(of: ".").path == projectFilePaths.normalizedProjectRoot.path)
	}

	@Test
	func projectFilePath_ordersByPath() {
		let projectFilePaths = ProjectFilePaths(projectRoot: "/Project")

		#expect([projectFilePaths.projectFilePath(of: "B.swift"), projectFilePaths.projectFilePath(of: "A.swift")].sorted().map(\.path) == ["/Project/A.swift", "/Project/B.swift"])
	}

	@Test
	func manifestPath_isRelativeToProjectRoot_whenFileIsInsideProject() {
		let projectFilePaths = ProjectFilePaths(projectRoot: linkedProjectRoot)

		#expect(projectFilePaths.manifestPath(of: projectFilePaths.projectFilePath(of: "Sources/File.swift")) == "Sources/File.swift")
	}

	@Test
	func manifestPath_isAbsolute_whenFileIsOutsideProject() {
		let projectFilePaths = ProjectFilePaths(projectRoot: linkedProjectRoot)

		#expect(projectFilePaths.manifestPath(of: projectFilePaths.projectFilePath(of: "/Elsewhere/File.swift")) == "/Elsewhere/File.swift")
	}

	@Test
	func buildSystemPath_joinsReportedProjectRoot_whenFileIsInsideProject() throws {
		let projectFilePaths = ProjectFilePaths(projectRoot: linkedProjectRoot)

		// However the file was found, the build system spells it under the root it reported.
		#expect(try projectFilePaths.buildSystemPath(of: projectFilePaths.projectFilePath(of: NormalizedFilePath("\(resolvedProjectRoot)/Sources/File.swift"))) == "\(linkedProjectRoot)/Sources/File.swift")
	}

	@Test
	func buildSystemPath_isAbsolute_whenFileIsOutsideProject() {
		let projectFilePaths = ProjectFilePaths(projectRoot: linkedProjectRoot)

		#expect(projectFilePaths.buildSystemPath(of: projectFilePaths.projectFilePath(of: "/Elsewhere/File.swift")) == "/Elsewhere/File.swift")
	}

	// MARK: Private

	private let fixtureDirectory: URL

	private var linkedProjectRoot: String {
		fixtureDirectory.appendingPathComponent("Link").path
	}

	private var resolvedProjectRoot: String {
		get throws {
			guard let resolvedPath = realpath(fixtureDirectory.appendingPathComponent("Project").path, nil) else {
				throw CocoaError(.fileNoSuchFile)
			}
			defer { free(resolvedPath) }
			return String(cString: resolvedPath)
		}
	}
}
