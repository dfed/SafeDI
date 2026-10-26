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
	/// `scan` lists a file that declares a root in any clause of its `#if` blocks, and `generate`
	/// writes every listed output, without code when no root is active.
	public var dependencyTreeGeneration: [InputOutputMap]

	/// The list of input-to-output file mappings for mock code generation.
	/// Each entry maps a Swift file containing `@Instantiable` to the
	/// output file where the generated `mock()` extension should be written.
	/// `scan` lists a file that declares `@Instantiable(generateMock: true)` in any clause of its
	/// `#if` blocks, and `generate` writes every listed output, without code when no such type is active.
	public var mockGeneration: [InputOutputMap]

	/// Source file paths of `#SafeDIConfiguration` invocations found in the current module, in any
	/// clause of their `#if` blocks. Used to scope configuration selection.
	public var configurationFilePaths: [String]

	/// The output file path for the shared mock configuration extensions.
	/// When set, configuration structs and build methods are generated into this file.
	public var mockConfigurationOutputFilePath: String?

	/// Type names from other modules to generate additional mocks for.
	/// These types must be known to the dependency tree via module info.
	/// `scan` lists those of every configuration in any clause of its `#if` block, and `generate` then
	/// generates the mocks the active configuration lists and writes the others without code.
	public var additionalMocksToGenerate: [String]

	/// Swift file paths discovered from `additionalDirectoriesToInclude` in `#SafeDIConfiguration`.
	/// The plugin uses these as additional build inputs so edits trigger rebuilds.
	/// Only populated by the `scan` subcommand; ignored by `generate`.
	public var additionalInputFiles: [String]

	/// Compilation conditions supplied to `scan`, which `generate` treats as active too unless the
	/// build settings it is handed replace them.
	/// `nil` in a hand-written manifest that omits them, where no conditions are recorded.
	public var activeCompilationConditions: [String]?

	/// The current module's own source files, written like `inputFilePath`s: the files whose
	/// `@Instantiable(generateMock: true)` types `mockGeneration` must list. `generate` rejects such a
	/// type in a file `mockGeneration` omits, which happens when the file changed after `scan` ran.
	/// `nil` in a hand-written manifest, where nothing is checked.
	public var mockScopedFilePaths: [String]?

	/// The directory `scan` resolved input paths against when writing `configurationFilePaths`
	/// and `inputFilePath`s, so `generate` can resolve its own input paths the same way.
	/// `nil` in a hand-written manifest, where paths are taken as written.
	public var projectRoot: String?

	public init(
		dependencyTreeGeneration: [InputOutputMap],
		mockGeneration: [InputOutputMap] = [],
		configurationFilePaths: [String] = [],
		mockConfigurationOutputFilePath: String? = nil,
		additionalMocksToGenerate: [String] = [],
		additionalInputFiles: [String] = [],
		activeCompilationConditions: [String]? = nil,
		mockScopedFilePaths: [String]? = nil,
		projectRoot: String? = nil,
	) {
		self.dependencyTreeGeneration = dependencyTreeGeneration
		self.mockGeneration = mockGeneration
		self.configurationFilePaths = configurationFilePaths
		self.mockConfigurationOutputFilePath = mockConfigurationOutputFilePath
		self.additionalMocksToGenerate = additionalMocksToGenerate
		self.additionalInputFiles = additionalInputFiles
		self.activeCompilationConditions = activeCompilationConditions
		self.mockScopedFilePaths = mockScopedFilePaths
		self.projectRoot = projectRoot
	}
}
