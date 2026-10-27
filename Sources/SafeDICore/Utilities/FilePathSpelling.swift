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

// This file is SafeDI's only place that normalizes, resolves, or relativizes a file path. The SafeDIGenerator
// plugin compiles it too, through a symbolic link, so the plugin and SafeDITool spell paths by the same rules.
// See "File path spelling" in CLAUDE.md for which spelling each consumer of a path receives.

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif
import Foundation

/// A file path in the one spelling SafeDI compares paths in: absolute, without `.` or `..` components or repeated
/// `/`, and, on Apple platforms, without the leading `/private` Foundation removes from paths such as
/// `/private/tmp/…` and `/private/var/…`. It resolves no symbolic link, so two spellings of one file through a
/// link other than `/tmp`, `/var`, or `/etc` stay distinct; `ProjectFilePaths` makes the project root's spellings
/// agree. Comparing paths as `NormalizedFilePath`s makes a comparison type-check only when both sides were
/// spelled by this rule.
public struct NormalizedFilePath: Hashable, Comparable, Sendable, CustomStringConvertible {
	/// - Parameters:
	///   - path: An absolute path, or one relative to `directory`.
	///   - directory: The directory a relative `path` is relative to, itself absolute or relative to the working
	///     directory. `nil` means the working directory.
	public init(_ path: String, relativeTo directory: String? = nil) {
		self.init(path, relativeTo: directory.map(Self.directoryURL(_:)))
	}

	init(_ path: String, relativeTo directoryURL: URL?) {
		self.path = URL(fileURLWithPath: path, relativeTo: directoryURL).standardizedFileURL.path
	}

	/// The normalized path.
	public let path: String

	public var description: String {
		path
	}

	/// This path relative to `directory`, or the whole path when the file does not lie inside `directory`.
	public func path(relativeTo directory: NormalizedFilePath) -> String {
		path(relativeToDirectoryPrefix: directory.directoryPrefix)
	}

	public static func < (lhs: NormalizedFilePath, rhs: NormalizedFilePath) -> Bool {
		lhs.path < rhs.path
	}

	/// The URL of the directory at `path`, against which relative paths are made absolute.
	static func directoryURL(_ path: String) -> URL {
		URL(fileURLWithPath: path, isDirectory: true)
	}

	/// This path followed by a `/`, which every path inside this directory starts with.
	fileprivate var directoryPrefix: String {
		path.hasSuffix("/") ? path : path + "/"
	}

	fileprivate func path(relativeToDirectoryPrefix directoryPrefix: String) -> String {
		if path.hasPrefix(directoryPrefix) {
			String(path.dropFirst(directoryPrefix.count))
		} else {
			path
		}
	}

	/// This path with the directory prefix `prefix` replaced by `replacement`, when it starts with `prefix`. Both are
	/// normalized, so the result is too.
	fileprivate func replacingDirectoryPrefix(_ prefix: String, with replacement: String) -> NormalizedFilePath {
		if prefix != replacement, path.hasPrefix(prefix) {
			NormalizedFilePath(normalizedPath: replacement + path.dropFirst(prefix.count))
		} else {
			self
		}
	}

	/// - Parameter normalizedPath: A path already spelled by this rule.
	private init(normalizedPath: String) {
		path = normalizedPath
	}
}

/// How SafeDI spells the paths of one project's files for each consumer, given the project root as a build system
/// reported it.
///
/// A build system may report the root through a symbolic link while the tool's working directory, which
/// `getcwd(3)` reports resolved, reaches the same files without it. The root is therefore resolved once, when this
/// is created, and every path inside it is compared, and named in the manifest, relative to the resolved root;
/// no other path is resolved, so the cost does not grow with the number of files.
public struct ProjectFilePaths: Sendable {
	/// - Parameter projectRoot: The project root as the build system reported it: absolute, or relative to the
	///   working directory.
	public init(projectRoot: String) {
		reportedProjectRoot = projectRoot
		let reportedRoot = NormalizedFilePath(projectRoot)
		let resolvedFilePath = realpath(projectRoot, nil)
		defer { free(resolvedFilePath) }
		let resolvedProjectRoot = resolvedFilePath.map { String(cString: $0) }
		reportsResolvedProjectRoot = resolvedProjectRoot == projectRoot
		normalizedProjectRoot = resolvedProjectRoot.map { NormalizedFilePath($0) } ?? reportedRoot
		reportedRootPrefix = reportedRoot.directoryPrefix
		rootPrefix = normalizedProjectRoot.directoryPrefix
		reportedRootURL = NormalizedFilePath.directoryURL(projectRoot)
	}

	/// The project root as the build system reported it, which is how the build system spells the paths inside it.
	public let reportedProjectRoot: String

	/// Whether the reported root is spelled exactly as `realpath(3)` resolves it: absolute, through no symbolic
	/// link, with no `.` or `..` component and no repeated or trailing `/`, and with each name in the case the file
	/// system stores. A root that names no file is not. Foundation cannot answer this on Apple platforms, where its
	/// resolution removes the leading `/private` that resolving `/tmp` adds.
	public let reportsResolvedProjectRoot: Bool

	/// The resolved project root, normalized. Every path inside the project is relative to it.
	public let normalizedProjectRoot: NormalizedFilePath

	/// The comparable spelling of `path`, an absolute path or one relative to the reported project root. A file
	/// inside the project has one comparable spelling whichever spelling of the root reaches it.
	public func normalizedPath(of path: String) -> NormalizedFilePath {
		normalizedPath(of: NormalizedFilePath(path, relativeTo: reportedRootURL))
	}

	/// The comparable spelling of `path`, such as a file found relative to the working directory.
	public func normalizedPath(of path: NormalizedFilePath) -> NormalizedFilePath {
		path.replacingDirectoryPrefix(reportedRootPrefix, with: rootPrefix)
	}

	/// How a manifest and scan's cache name the file at `path`: relative to the project root when the file lies
	/// inside the project, and otherwise absolute and normalized.
	public func manifestPath(of path: NormalizedFilePath) -> String {
		normalizedPath(of: path).path(relativeToDirectoryPrefix: rootPrefix)
	}

	/// How the build system spells the file at `path`, for the plugin to declare it as an input and for a
	/// `#sourceLocation` directive the compiler compares with its own paths: the reported project root joined with
	/// the file's path inside the project, or, for a file outside the project, its absolute normalized path. The
	/// build system hands the compiler the paths it reported to the plugin, which are inside the reported root.
	/// Normalizing the joined path would not keep that spelling: on Apple platforms, Foundation removes a leading
	/// `/private` from paths such as `/private/tmp/…`, which the compiler keeps.
	public func buildSystemPath(of path: NormalizedFilePath) -> String {
		let manifestPath = manifestPath(of: path)
		return if (manifestPath as NSString).isAbsolutePath {
			manifestPath
		} else {
			(reportedProjectRoot as NSString).appendingPathComponent(manifestPath)
		}
	}

	private let reportedRootPrefix: String
	private let rootPrefix: String
	private let reportedRootURL: URL
}
