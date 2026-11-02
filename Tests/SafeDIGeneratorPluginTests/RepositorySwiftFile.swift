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

/// A Swift file of this repository, read by a check of the rules SafeDI's own code follows.
struct RepositorySwiftFile {
	/// The file's path relative to the repository root, such as `Sources/SafeDICore/Models/ReservedName.swift`.
	let path: String
	/// The file's text.
	let source: String

	/// The file's name, such as `ReservedName.swift`.
	var name: String {
		URL(fileURLWithPath: path).lastPathComponent
	}

	/// The Swift files under each of `directories`, which are relative to the repository root, in path order. A
	/// symbolic link compiles a file that is checked where it lives, so no file reached through one is listed.
	static func files(under directories: [String]) throws -> [RepositorySwiftFile] {
		let repositoryRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		var files = [RepositorySwiftFile]()
		for directory in directories {
			let directoryURL = repositoryRoot.appendingPathComponent(directory)
			// Relative paths, so a path's spelling never depends on where the checkout lives.
			guard let enumerator = FileManager.default.enumerator(atPath: directoryURL.path) else {
				throw CouldNotEnumerateDirectoryError(directory: directory)
			}
			for case let relativePath as String in enumerator {
				let fileURL = directoryURL.appendingPathComponent(relativePath)
				let fileType = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.type] as? FileAttributeType
				if fileType == .typeSymbolicLink {
					enumerator.skipDescendants()
				} else if fileURL.pathExtension == "swift" {
					try files.append(RepositorySwiftFile(
						path: "\(directory)/\(relativePath)",
						source: String(contentsOf: fileURL, encoding: .utf8),
					))
				}
			}
		}
		return files.sorted { $0.path < $1.path }
	}

	private struct CouldNotEnumerateDirectoryError: Error {
		let directory: String
	}
}
