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

// The SafeDIGenerator plugin compiles this file too, through a symbolic link, so the plugin encodes and SafeDITool
// decodes the same declaration. It must need nothing but Foundation.

import Foundation

/// The targets whose Swift files the SafeDIGenerator plugin lists in its input CSV, as the plugin writes them beside
/// that CSV, in a file named after it with `fileNameSuffix` appended, for `generate` to read the module and package
/// that declare each file. The Xcode project plugin knows no targets and writes none.
struct PluginTargetGraph: Codable {
	/// The target the plugin generates code for.
	let target: Target
	/// Every other target whose Swift files the input CSV lists: the target's first-party dependencies, directly or
	/// through another target, by the rule that decides which files the CSV lists. Sorted by module name and package.
	let dependencyTargets: [Target]

	/// A target of a Swift package.
	struct Target: Codable {
		/// The name of the module the target compiles.
		let moduleName: String
		/// SwiftPM's identity of the package that declares the target, from which SwiftPM derives the
		/// `-package-name` it hands the compiler, or `nil` when the plugin found the target in no package.
		let packageID: String?
		/// The target's Swift files, each spelled exactly as the input CSV spells it, which the plugin spells with the
		/// same code: relative to the package directory SwiftPM reports when the file lies inside it, and normalized
		/// otherwise. Sorted.
		let sourceFilePaths: [String]
		/// The modules the target depends on directly, through a target or a product, sorted.
		let dependencyModuleNames: [String]
	}

	/// What the plugin appends to the input CSV's path to name the file it writes the target graph to.
	static let fileNameSuffix = ".targets.json"
}
