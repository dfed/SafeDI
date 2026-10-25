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

/// Compute a path string relative to a base directory, for use in the CSV and manifest.
/// Falls back to the absolute path if the URL is not under the base directory.
public func relativePath(for url: URL, relativeTo base: URL) -> String {
	RelativePathBase(base).relativePath(for: url)
}

/// A base directory that paths are expressed relative to, for use in the CSV and manifest.
///
/// Standardizing a URL is far costlier than comparing strings, and `scan` expresses every file
/// it parses relative to the same project root, so the base's path is standardized once.
public struct RelativePathBase {
	public init(_ base: URL) {
		let standardizedBasePath = base.standardizedFileURL.path
		basePath = standardizedBasePath.hasSuffix("/")
			? standardizedBasePath
			: standardizedBasePath + "/"
	}

	/// `url`'s path relative to the base, or its absolute path if it is not under the base.
	public func relativePath(for url: URL) -> String {
		relativePath(forStandardizedPath: url.standardizedFileURL.path)
	}

	/// The path of a standardized file URL, relative to the base, or as given if it is not under
	/// the base. Standardizing again would return the same path.
	public func relativePath(forStandardizedPath path: String) -> String {
		if path.hasPrefix(basePath) {
			String(path.dropFirst(basePath.count))
		} else {
			path
		}
	}

	private let basePath: String
}
