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

/// The declarations in a file that decide which files SafeDI generates, found in every clause of
/// every `#if` block whatever its condition.
///
/// A build system needs the list of a command's output files before the build runs, while the
/// compilation conditions that select an `#if` block's clause may be known only when the command
/// runs. Planning an output for a declaration in any clause lets the outputs stay the same whichever
/// clause the conditions select: a declaration in a clause that turns out inactive gets a generated
/// file without code.
public struct OutputFileDeclarations: Codable, Sendable {
	// MARK: Initialization

	public init() {}

	// MARK: Public

	/// Whether the file declares an `@Instantiable(isRoot: true)` type, whose dependency tree gets its own file.
	public private(set) var declaresRoot = false
	/// Whether the file declares an `@Instantiable(generateMock: true)` type or extension, whose mock gets its own file.
	public private(set) var declaresMockGeneratingType = false
	/// Whether the file declares a `#SafeDIConfiguration`.
	public private(set) var declaresConfiguration = false
	/// Every type name the file's configurations list in `additionalMocksToGenerate`, sorted and without duplicates.
	/// Each listed type's mock gets its own file.
	public private(set) var additionalMocksToGenerate = [String]()
	/// Every directory the file's configurations list in `additionalDirectoriesToInclude`, sorted and without
	/// duplicates. The files in them can declare roots, and are inputs of the command that generates code.
	public private(set) var additionalDirectoriesToInclude = [String]()

	/// Records an `@Instantiable` declaration.
	/// - Parameters:
	///   - isRoot: Whether the declaration is a root.
	///   - generatesMock: Whether the declaration sets `generateMock: true`.
	public mutating func recordInstantiable(isRoot: Bool, generatesMock: Bool) {
		declaresRoot = declaresRoot || isRoot
		declaresMockGeneratingType = declaresMockGeneratingType || generatesMock
	}

	/// Records a `#SafeDIConfiguration` declaration.
	public mutating func record(_ configuration: SafeDIConfiguration) {
		declaresConfiguration = true
		additionalMocksToGenerate = Set(additionalMocksToGenerate + configuration.additionalMocksToGenerate).sorted()
		additionalDirectoriesToInclude = Set(additionalDirectoriesToInclude + configuration.additionalDirectoriesToInclude).sorted()
	}

	/// Records every declaration `other` records.
	public mutating func formUnion(_ other: OutputFileDeclarations) {
		declaresRoot = declaresRoot || other.declaresRoot
		declaresMockGeneratingType = declaresMockGeneratingType || other.declaresMockGeneratingType
		declaresConfiguration = declaresConfiguration || other.declaresConfiguration
		additionalMocksToGenerate = Set(additionalMocksToGenerate + other.additionalMocksToGenerate).sorted()
		additionalDirectoriesToInclude = Set(additionalDirectoriesToInclude + other.additionalDirectoriesToInclude).sorted()
	}
}
