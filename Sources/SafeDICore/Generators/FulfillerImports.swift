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

/// The modules a generated file imports because it builds a type that its own declarations do not name.
///
/// A `fulfilledByType:` string or a `fulfillingAdditionalTypes:` entry lets a module build a type of a module that none of
/// its files imports, and generated code then names that type, and a `mockOnly` declaration in a third module lets a mock
/// call a method none of the module's files can see. Every other import of a generated file repeats what the files SafeDI
/// read import, so nothing else imports those modules. A file gains the import only when its own trees build such a type
/// (`ScopeGenerator.fulfillersOfTree(buildingMock:)`) or its mock's parameters default to one
/// (`ScopeGenerator.fulfillersOfMock(mockDefaults:)`), and no import that a file SafeDI read spells makes the type visible.
///
/// The trees decide, and not the names the file's code holds, because a name proves nothing: a file can name a type of a
/// module it imports, such as `os.Logger`, that shares its name with a fulfiller the file never builds, and importing the
/// fulfiller's module there would make that name ambiguous in a build that compiles.
///
/// The import is added beside the ones a file spells, none of which it replaces: a by-type import can carry attributes the
/// new import lacks, such as `@_spi`, or tell its type from a type of the same name in another module.
///
/// The compiler compares an import with every other import of its module in the module's files, and SafeDI reads only the
/// files that declare SafeDI content, so the added import is checked against the rest (`OwnFiles`). Where one of those files
/// imports the module at a level below `public`, the added import spells a level, since an import that spells none is
/// ambiguous beside it; a `public` import in one of them asks for none, so the added import then spells only what the
/// generated file's own declarations need (`GeneratedImportAccess`). The added import is `@_implementationOnly` where one of
/// them is, since the compiler warns at an import that is not. No import is added for a type whose name one of the module's
/// own types has where the generated file can see it: that type shadows every import, so the import could not make the
/// fulfiller visible.
///
/// SafeDI cannot see every other way a build already reaches the type, so a file can gain an import it did not need:
/// through a module that re-exports the fulfiller's module, or the one type (`@_exported import struct Impl.Thing`), or an
/// extension another file's import leaks, as it does in every language mode unless `MemberImportVisibility` is on. Such a
/// build still compiles unless a name collides: the added import is of the whole module, so it brings the module's other
/// public names in, and a name those collide on with another module imported whole becomes ambiguous. (A type imported by
/// itself shadows a whole-module import, so it collides with nothing.) A build in which another module imported whole has a
/// type of the fulfiller's name that fits where it is built does not compile either: its generated code had been building
/// that other type instead of the one the declarations name, and the compiler now reports the name as ambiguous. SafeDI
/// reads no declaration of such a type, so it cannot tell that build from one that needs the import.
public enum FulfillerImports {
	// MARK: Public

	/// What the module's own files, those SafeDI reads and those it does not, say that decides an added import. Read at most
	/// once a run, and only when a generated file would gain an import apart from a type of the module that shadows the
	/// fulfiller. Only this read can find such a type, so a module whose own types shadow every fulfiller still reads its
	/// files and gains no import. A module with no generated file that builds a fulfiller its imports miss reads nothing more.
	public struct OwnFiles: Sendable {
		/// - Parameters:
		///   - typeNames: The names, without backticks, of the types the files declare outside every other type that code in
		///     another file can name.
		///   - importStatements: The imports the files spell, in any order: what this keeps of them depends on no order.
		public init(typeNames: Set<String>, importStatements: [ImportStatement]) {
			self.typeNames = typeNames
			for importStatement in importStatements {
				let moduleName = importStatement.moduleName.spelledWithoutBackticks.spelledAsIdentifier
				if let accessLevel = importStatement.accessLevel {
					levelsByModuleName[moduleName, default: []].insert(accessLevel)
				}
				if importStatement.isImplementationOnly {
					implementationOnlyModuleNames.insert(moduleName)
				}
			}
		}

		let typeNames: Set<String>
		/// The access levels the files spell on their imports, by imported module as a generated file spells it.
		private(set) var levelsByModuleName = [String: Set<AccessLevel>]()
		/// The modules, as a generated file spells them, that one of the files imports `@_implementationOnly`.
		private(set) var implementationOnlyModuleNames = Set<String>()
	}

	// MARK: Internal

	/// A type a generated file builds that its declarations do not name, with a module it needs the import of.
	public struct Fulfiller: Hashable, Sendable {
		/// - Parameter instantiable: The declaration that fulfills the property, or `nil` when SafeDI knows no module for it.
		init?(instantiable: Instantiable) {
			guard let moduleName = instantiable.moduleName,
			      let outermostTypeName = instantiable.concreteInstantiable.outermostTypeName
			else { return nil }
			self.moduleName = moduleName
			self.outermostTypeName = outermostTypeName.spelledWithoutBackticks
			isMadeVisibleByImportOfItsType = true
		}

		/// The declaration whose hand-written mock a mock calls, when a declaration in another module than the one that
		/// declares `instantiable` writes that mock (`Instantiable.mergedWithMockProvider`).
		private init?(mergedMockOf instantiable: Instantiable) {
			guard let moduleName = instantiable.mockDeclarationModuleName,
			      moduleName != instantiable.moduleName,
			      let outermostTypeName = instantiable.concreteInstantiable.outermostTypeName
			else { return nil }
			self.moduleName = moduleName
			self.outermostTypeName = outermostTypeName.spelledWithoutBackticks
			isMadeVisibleByImportOfItsType = false
		}

		/// What generated code that builds `instantiable` for a property of the type `propertyType` needs imported: the
		/// declaration's module when the property does not name the type, and, when the code calls the hand-written mock,
		/// the module that writes it when that is another, which no property's declaration ever names.
		static func fulfillers(building instantiable: Instantiable, forPropertyOfType propertyType: TypeDescription, callingHandWrittenMock: Bool) -> Set<Fulfiller> {
			var fulfillers = Set<Fulfiller>()
			if propertyType != instantiable.concreteInstantiable, let fulfiller = Fulfiller(instantiable: instantiable) {
				fulfillers.insert(fulfiller)
			}
			if callingHandWrittenMock, let fulfiller = Fulfiller(mergedMockOf: instantiable) {
				fulfillers.insert(fulfiller)
			}
			return fulfillers
		}

		/// The module of the declaration, without backticks.
		let moduleName: String

		/// The name of the type, or of the outermost type enclosing it, without backticks.
		fileprivate let outermostTypeName: String

		/// Whether an import of the type by itself gives generated code what it needs of this module: it does for the module
		/// that declares the type, and not for one that writes a mock of it, whose method such an import does not bring in.
		fileprivate let isMadeVisibleByImportOfItsType: Bool

		/// Whether `importStatement` makes the type visible: it imports the whole module, or, through any module, since one
		/// can re-export the type, that outermost type. A read file's import can spell the module in backticks.
		fileprivate func isMadeVisible(by importStatement: ImportStatement) -> Bool {
			if importStatement.type.isEmpty {
				importStatement.moduleName.spelledWithoutBackticks == moduleName
			} else {
				isMadeVisibleByImportOfItsType && importStatement.type.spelledWithoutBackticks == outermostTypeName
			}
		}
	}

	/// The fulfillers among `fulfillers` that no import among `importStatements` makes visible, in other modules than the
	/// one named `emittingModuleName`, which alone can need the module's own files read.
	static func fulfillers(among fulfillers: Set<Fulfiller>, notMadeVisibleBy importStatements: [ImportStatement], emittingModuleName: String?) -> [Fulfiller] {
		fulfillers.filter { fulfiller in
			fulfiller.moduleName != emittingModuleName && !importStatements.contains(where: fulfiller.isMadeVisible(by:))
		}
	}

	/// The imports that make `fulfillers` visible, given what the module's own files say.
	static func importStatements(for fulfillers: [Fulfiller], ownFiles: OwnFiles) -> [ImportStatement] {
		var moduleNames = Set<String>()
		for fulfiller in fulfillers where !ownFiles.typeNames.contains(fulfiller.outermostTypeName) {
			moduleNames.insert(fulfiller.moduleName.spelledAsIdentifier)
		}
		return moduleNames.map { moduleName in
			ImportStatement(attribute: ownFiles.implementationOnlyModuleNames.contains(moduleName) ? ImportStatement.implementationOnlyAttribute : "", moduleName: moduleName)
		}
	}
}
