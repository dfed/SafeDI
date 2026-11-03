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

	public init(
		declaresRoot: Bool,
		declaresDependencyTreeType: Bool = false,
		declaresMockGeneratingType: Bool,
		declaresConfiguration: Bool,
		instantiableTypeNames: Set<String>,
		extendedTypeNames: Set<String> = [],
		additionalMocksToGenerate: [String],
		additionalDirectoriesToInclude: [String],
	) {
		self.declaresRoot = declaresRoot
		self.declaresDependencyTreeType = declaresDependencyTreeType
		self.declaresMockGeneratingType = declaresMockGeneratingType
		self.declaresConfiguration = declaresConfiguration
		self.instantiableTypeNames = instantiableTypeNames
		self.extendedTypeNames = extendedTypeNames
		self.additionalMocksToGenerate = additionalMocksToGenerate
		self.additionalDirectoriesToInclude = additionalDirectoriesToInclude
	}

	// MARK: Public

	/// Whether the file declares an `@Instantiable(isRoot: true)` type, whose dependency tree gets its own file.
	public private(set) var declaresRoot = false
	/// Whether the file declares an `@Instantiable(generateDependencyTree: true)` type, whose generated dependency
	/// tree gets its own file in the module that declares it, as a root's does.
	public private(set) var declaresDependencyTreeType = false
	/// Whether the file declares an `@Instantiable(generateMock: true)` type or extension, whose mock gets its own file.
	public private(set) var declaresMockGeneratingType = false
	/// Whether the file declares a `#SafeDIConfiguration`.
	public private(set) var declaresConfiguration = false
	/// The type each `@Instantiable` declaration in the file declares, named as `additionalMocksToGenerate` names
	/// it. A configuration may list any of them: the listed type's mock gets its file even when the conditions
	/// leave the declaration inactive, and the file is then written without code.
	public private(set) var instantiableTypeNames = Set<String>()
	/// The outermost name of each type an extension extends that is, or declares, an `@Instantiable` declaration: a
	/// type that can be declared in a file SafeDI otherwise skips, whose access bounds the type the declaration
	/// declares.
	public private(set) var extendedTypeNames = Set<String>()
	/// Every type name the file's configurations list in `additionalMocksToGenerate`, sorted and without duplicates.
	/// Each listed type's mock gets its own file.
	public private(set) var additionalMocksToGenerate = [String]()
	/// Every directory the file's configurations list in `additionalDirectoriesToInclude`, sorted and without
	/// duplicates. The files in them can declare roots, and are inputs of the command that generates code.
	public private(set) var additionalDirectoriesToInclude = [String]()

	/// Records an `@Instantiable` declaration.
	/// - Parameters:
	///   - typeName: The type the declaration declares, with its enclosing types: the type a type definition
	///     defines, or the type an extension extends.
	///   - extendedType: The type the extension that is the declaration, or that encloses it, extends, if one does.
	///   - isRoot: Whether the declaration is a root.
	///   - generatesDependencyTree: Whether the declaration sets `generateDependencyTree: true`.
	///   - generatesMock: Whether the declaration sets `generateMock: true`.
	public mutating func recordInstantiable(named typeName: String, inExtensionOf extendedType: TypeDescription?, isRoot: Bool, generatesDependencyTree: Bool, generatesMock: Bool) {
		instantiableTypeNames.insert(typeName)
		// The outermost type is the one a declaration in another file spells at its top level.
		if let extendedTypeName = extendedType?.outermostTypeName {
			extendedTypeNames.insert(extendedTypeName)
		}
		declaresRoot = declaresRoot || isRoot
		declaresDependencyTreeType = declaresDependencyTreeType || generatesDependencyTree
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
		declaresDependencyTreeType = declaresDependencyTreeType || other.declaresDependencyTreeType
		declaresMockGeneratingType = declaresMockGeneratingType || other.declaresMockGeneratingType
		declaresConfiguration = declaresConfiguration || other.declaresConfiguration
		instantiableTypeNames.formUnion(other.instantiableTypeNames)
		extendedTypeNames.formUnion(other.extendedTypeNames)
		additionalMocksToGenerate = Set(additionalMocksToGenerate + other.additionalMocksToGenerate).sorted()
		additionalDirectoriesToInclude = Set(additionalDirectoriesToInclude + other.additionalDirectoriesToInclude).sorted()
	}
}
