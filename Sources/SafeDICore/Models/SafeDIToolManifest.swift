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

/// A manifest that describes the desired outputs of the SafeDITool.
/// All input file paths are relative to the working directory where the tool is invoked.
/// Output file paths may be absolute or relative to the working directory.
public struct SafeDIToolManifest: Codable, Sendable {
	/// A mapping from an input Swift file to an output file.
	public struct InputOutputMap: Codable, Sendable {
		/// The path to the input Swift file containing one or more root `@Instantiable` declarations.
		/// This path is relative to the working directory where the tool is invoked.
		public var inputFilePath: String

		/// The path where the generated Swift code should be written.
		/// This path may be absolute or relative to the working directory.
		public var outputFilePath: String

		public init(inputFilePath: String, outputFilePath: String) {
			self.inputFilePath = inputFilePath
			self.outputFilePath = outputFilePath
		}
	}

	/// The list of input-to-output file mappings for dependency tree code generation.
	/// Each entry maps a Swift file containing `@Instantiable(isRoot: true)` to the
	/// output file where the generated `public init()` extension should be written.
	public var dependencyTreeGeneration: [InputOutputMap]

	/// The list of input-to-output file mappings for mock code generation.
	/// Each entry maps a Swift file containing `@Instantiable` to the
	/// output file where the generated `mock()` extension should be written.
	public var mockGeneration: [InputOutputMap]

	/// All Swift source file paths that belong to the current module (target).
	/// Used to scope configuration selection to the current module in multi-module builds.
	public var currentModuleSourceFilePaths: [String]

	public init(
		dependencyTreeGeneration: [InputOutputMap],
		mockGeneration: [InputOutputMap] = [],
		currentModuleSourceFilePaths: [String] = [],
	) {
		self.dependencyTreeGeneration = dependencyTreeGeneration
		self.mockGeneration = mockGeneration
		self.currentModuleSourceFilePaths = currentModuleSourceFilePaths
	}
}
