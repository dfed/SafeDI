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

import SwiftParser
import SwiftSyntax

/// The access level each import of a file SafeDI generates spells (SE-0409).
///
/// The compiler constrains an import's level two ways. Without `InternalImportsByDefault`, an import that spells no
/// level is `public`, and the compiler rejects it as ambiguous when another file of the module imports the same module
/// with a level below `public`; with it, an import that spells none is `internal`, which a `public` or `package`
/// declaration cannot name a type through. And it warns at a `public` or `package` import that no declaration of that
/// level in the file uses. SafeDI cannot see whether `InternalImportsByDefault` is on, so each import of a generated
/// file spells a level that compiles either way, decided per file:
/// - When none of the module's own files spells a level on an import, no generated import spells one: what every file
///   of such a module already does.
/// - Otherwise an import of a module spells `public` when a `public` or `@usableFromInline` declaration of the file
///   names a type the module may declare, or when the import is `@_exported`, which only a `public` import can be.
/// - Else `package` when a `package` declaration of the file names one. When the module's own files import that module
///   at no level below `public`, one of them may import it with no level, which a `package` import would make ambiguous
///   without `InternalImportsByDefault`, so the import spells `package` only where that feature is on
///   (`#if hasFeature(InternalImportsByDefault)`) and no level otherwise.
/// - Else `internal` when the module's own files import that module with a level below `public`: without
///   `InternalImportsByDefault` every import of it must then spell a level.
/// - Else no level.
///
/// Generated mocks, and the configurations of public mocks, compile only where the module's mock condition is active.
/// Where it is not, a `public` or `package` import that only their declarations need is unused and draws the warning,
/// so a file that holds mock code spells such an import under the condition, and elsewhere as the file's code outside
/// it needs: `#if DEBUG` `public import Foundation` `#else` `internal import Foundation` `#endif`. Mocks generated
/// without a condition compile in every build, and an `@_exported` import, which is `public` everywhere, draws no
/// warning when unused.
///
/// The module's own files are those the build compiles into the module: a dependency's file, which a SwiftPM build
/// hands the tool too, says nothing of the module's own imports (`ImportStatement.sourceFilePath`).
///
/// A type a declaration names is attributed to the modules that declare it as SafeDI read them, to SafeDI for its
/// wrappers, to no module for the standard library's types, and to the module a qualified spelling names. A type SafeDI
/// read no declaration of in a module it knows may come from any module the file imports, so it is attributed to
/// Foundation for Foundation's well-known types and to each module the module's own files import at that declaration's
/// level or wider, but to no module they import only narrower, whose types none of their own declarations of that level
/// can name either. A generated declaration also names types a dependency's declarations name, such as a type a seam's
/// tree receives, whose module the module's own files need not import at all, so an unread type is also attributed to
/// each module that a dependency's file declaring an `@Instantiable` that names it, in a dependency or an initializer
/// parameter, imports at `package` or wider, the levels through which the declarations another module calls can name
/// it; but not a type Foundation is known to declare, which such a file's other imports say nothing about. Attributing a
/// type to a module that does not declare it costs a warning that the import is unused.
public struct GeneratedImportAccess: Sendable {
	// MARK: Initialization

	/// - Parameters:
	///   - writtenLevels: The levels the files SafeDI read spell on their imports.
	///   - instantiables: The declarations SafeDI read, which attribute the types they declare to their modules.
	///   - plainTypeDeclarations: The declarations of types that are not `@Instantiable` SafeDI read, which do too.
	///   - emittingModuleName: The module the code is generated in, whose types need no import.
	///   - isOwnFile: Whether a file is one of the module's own, which tells a declaration of the module the code is
	///     generated in when SafeDI knows no module name, or `nil` when no file is.
	init(
		writtenLevels: WrittenLevels,
		instantiables: some Sequence<Instantiable>,
		plainTypeDeclarations: [PlainTypeDeclaration],
		emittingModuleName: String?,
		isOwnFile: ((String) -> Bool)?,
	) {
		ownLevelsByModuleName = writtenLevels.ownLevelsByModuleName
		guard !ownLevelsByModuleName.isEmpty else {
			// No generated import spells a level, so no type is attributed.
			declaringModulesByTypeName = [:]
			dependencyFileModuleNamesByTypeName = [:]
			return
		}
		/// The module a declaration in the file at `sourceFilePath` declares its type in, or `nil` for a module SafeDI does
		/// not know, which leaves the type as unattributed as one SafeDI read no declaration of.
		func declaringModule(moduleName: String?, sourceFilePath: String?) -> DeclaringModule? {
			if let moduleName {
				moduleName == emittingModuleName ? .emitting : .named(moduleName)
			} else if let sourceFilePath, isOwnFile?(sourceFilePath) == true {
				.emitting
			} else {
				nil
			}
		}
		var declaringModulesByTypeName = [String: Set<DeclaringModule>]()
		var dependencyFileModuleNamesByTypeName = [String: Set<String>]()
		for instantiable in instantiables {
			// An extension's `@Instantiable` declares no type: its extended type's own declaration, if SafeDI read it, is
			// a plain one.
			if !instantiable.declarationType.isExtension,
			   let typeName = instantiable.concreteInstantiable.outermostTypeName,
			   let declaringModule = declaringModule(moduleName: instantiable.moduleName, sourceFilePath: instantiable.sourceFilePath)
			{
				declaringModulesByTypeName[typeName, default: []].insert(declaringModule)
			}
			// A dependency's file that names a type imports the module that declares it.
			if let sourceFilePath = instantiable.sourceFilePath,
			   let moduleNames = writtenLevels.dependencyFileModuleNames(ofFileAt: sourceFilePath, declaredIn: instantiable.moduleName)
			{
				let namedTypes = instantiable.dependencies.map(\.property.typeDescription)
					+ (instantiable.initializer?.arguments.map(\.typeDescription) ?? [])
				for typeName in namedTypes.flatMap(TypeAccessProof.mentionedTypes(in:)).compactMap(\.outermostTypeName) {
					dependencyFileModuleNamesByTypeName[typeName, default: []].formUnion(moduleNames)
				}
			}
		}
		for plainTypeDeclaration in plainTypeDeclarations {
			if let typeName = plainTypeDeclaration.typeDescription.outermostTypeName,
			   let declaringModule = declaringModule(moduleName: plainTypeDeclaration.moduleName, sourceFilePath: plainTypeDeclaration.sourceFilePath)
			{
				declaringModulesByTypeName[typeName, default: []].insert(declaringModule)
			}
		}
		self.declaringModulesByTypeName = declaringModulesByTypeName
		self.dependencyFileModuleNamesByTypeName = dependencyFileModuleNamesByTypeName
	}

	// MARK: Public

	/// The levels the files SafeDI read spell on their imports: the module's own files', and each other file's.
	public struct WrittenLevels: Sendable {
		/// - Parameters:
		///   - ownImportStatements: The imports of the module's own files, among which `isOwnFile` finds them.
		///   - importStatements: The imports of every file SafeDI read, the module's own and its dependencies', each group
		///     with the module whose files hold it, or `nil` when the group's files belong to several modules or one SafeDI
		///     does not know: two modules can record files at one relative path, as two projects of a Tuist workspace do.
		///   - isOwnFile: Whether a file is one of the module's own.
		public init(ownImportStatements: [ImportStatement], importStatements: [(moduleName: String?, importStatements: [ImportStatement])], isOwnFile: (String) -> Bool) {
			var ownLevelsByModuleName = [String: Set<AccessLevel>]()
			for importStatement in ownImportStatements {
				if let accessLevel = importStatement.accessLevel,
				   let sourceFilePath = importStatement.sourceFilePath,
				   isOwnFile(sourceFilePath)
				{
					ownLevelsByModuleName[importStatement.moduleName, default: []].insert(accessLevel)
				}
			}
			var dependencyFileModuleNamesByDeclaringFile = [DeclaringFile: Set<String>]()
			var dependencyFileModuleNamesByFilePath = [String: Set<String>]()
			var moduleNamesWithFiles = Set<String>()
			for (moduleName, groupImportStatements) in importStatements {
				if let moduleName {
					moduleNamesWithFiles.insert(moduleName)
				}
				for importStatement in groupImportStatements {
					// Only an import of `package` or wider lets the file's declarations that another module calls name the
					// imported module's types.
					if let accessLevel = importStatement.accessLevel,
					   Self.levelsOtherModulesCanName.contains(accessLevel),
					   let sourceFilePath = importStatement.sourceFilePath,
					   !isOwnFile(sourceFilePath)
					{
						if let moduleName {
							dependencyFileModuleNamesByDeclaringFile[DeclaringFile(moduleName: moduleName, sourceFilePath: sourceFilePath), default: []].insert(importStatement.moduleName)
						}
						dependencyFileModuleNamesByFilePath[sourceFilePath, default: []].insert(importStatement.moduleName)
					}
				}
			}
			self.init(
				ownLevelsByModuleName: ownLevelsByModuleName,
				moduleNamesWithFiles: moduleNamesWithFiles,
				dependencyFileModuleNamesByDeclaringFile: dependencyFileModuleNamesByDeclaringFile,
				dependencyFileModuleNamesByFilePath: dependencyFileModuleNamesByFilePath,
			)
		}

		private init(ownLevelsByModuleName: [String: Set<AccessLevel>], moduleNamesWithFiles: Set<String>, dependencyFileModuleNamesByDeclaringFile: [DeclaringFile: Set<String>], dependencyFileModuleNamesByFilePath: [String: Set<String>]) {
			self.ownLevelsByModuleName = ownLevelsByModuleName
			self.moduleNamesWithFiles = moduleNamesWithFiles
			self.dependencyFileModuleNamesByDeclaringFile = dependencyFileModuleNamesByDeclaringFile
			self.dependencyFileModuleNamesByFilePath = dependencyFileModuleNamesByFilePath
		}

		/// No file spells a level.
		public static let none = WrittenLevels(ownLevelsByModuleName: [:], moduleNamesWithFiles: [], dependencyFileModuleNamesByDeclaringFile: [:], dependencyFileModuleNamesByFilePath: [:])

		/// These levels with `levelsByModuleName` too, which the module's own files spell.
		func addingOwnLevels(_ levelsByModuleName: [String: Set<AccessLevel>]) -> WrittenLevels {
			WrittenLevels(
				ownLevelsByModuleName: ownLevelsByModuleName.merging(levelsByModuleName) { $0.union($1) },
				moduleNamesWithFiles: moduleNamesWithFiles,
				dependencyFileModuleNamesByDeclaringFile: dependencyFileModuleNamesByDeclaringFile,
				dependencyFileModuleNamesByFilePath: dependencyFileModuleNamesByFilePath,
			)
		}

		/// A file of a module whose module info SafeDI read.
		struct DeclaringFile: Hashable {
			let moduleName: String
			let sourceFilePath: String
		}

		/// The levels the module's own files spell on their imports, by imported module.
		let ownLevelsByModuleName: [String: Set<AccessLevel>]
		/// The modules whose module info SafeDI read, whose files' imports are grouped by module.
		let moduleNamesWithFiles: Set<String>
		/// The modules each file of a module whose module info SafeDI read imports at `package` or wider, by module and file.
		let dependencyFileModuleNamesByDeclaringFile: [DeclaringFile: Set<String>]
		/// The modules each file that is not one of the module's own imports at `package` or wider, by file, whichever
		/// module's it is.
		let dependencyFileModuleNamesByFilePath: [String: Set<String>]

		/// The modules the file at `sourceFilePath`, which the module named `moduleName` declares when SafeDI knows it,
		/// imports at `package` or wider: the file of that module, when SafeDI read that module's module info, so a file
		/// of another module at the same path never answers; otherwise any file at that path.
		func dependencyFileModuleNames(ofFileAt sourceFilePath: String, declaredIn moduleName: String?) -> Set<String>? {
			if let moduleName, moduleNamesWithFiles.contains(moduleName) {
				dependencyFileModuleNamesByDeclaringFile[DeclaringFile(moduleName: moduleName, sourceFilePath: sourceFilePath)]
			} else {
				dependencyFileModuleNamesByFilePath[sourceFilePath]
			}
		}

		/// The levels of an import through which a declaration another module calls can name the imported module's types.
		private static let levelsOtherModulesCanName: Set<AccessLevel> = [.open, .public, .package]
	}

	// MARK: Internal

	/// How a generated file spells its import of a module.
	indirect enum Spelling: Equatable {
		/// No level.
		case noLevel
		/// The level.
		case level(AccessLevel)
		/// `package` where `InternalImportsByDefault` is on, and no level otherwise.
		case packageWhereImportsAreInternalByDefault
		/// `whereActive` where `condition`, the module's mock condition, is active, and `otherwise` elsewhere.
		case underMockCondition(String, whereActive: Spelling, otherwise: Spelling)

		/// The source of `importStatement`, guarded by `#if canImport`, as this spells it.
		func source(of importStatement: ImportStatement) -> String {
			"""
			#if canImport(\(importStatement.moduleName))
			\(importSource(of: importStatement))
			#endif
			"""
		}

		private func importSource(of importStatement: ImportStatement) -> String {
			switch self {
			case .noLevel:
				importStatement.asSource(spelling: nil)
			case let .level(accessLevel):
				importStatement.asSource(spelling: accessLevel)
			case .packageWhereImportsAreInternalByDefault:
				"""
				#if hasFeature(InternalImportsByDefault)
				\(importStatement.asSource(spelling: .package))
				#else
				\(importStatement.asSource(spelling: nil))
				#endif
				"""
			case let .underMockCondition(condition, whereActive, otherwise):
				"""
				#if \(condition)
				\(whereActive.importSource(of: importStatement))
				#else
				\(otherwise.importSource(of: importStatement))
				#endif
				"""
			}
		}
	}

	/// The types a generated file's declarations name where an import's level matters.
	struct NamedTypes {
		/// The outermost names of the types the file's `public` and `@usableFromInline` declarations name.
		let publicTypeNames: Set<String>
		/// The outermost names of the types the file's `package` declarations name.
		let packageTypeNames: Set<String>

		/// The types these and `other` name.
		func union(_ other: NamedTypes) -> NamedTypes {
			NamedTypes(publicTypeNames: publicTypeNames.union(other.publicTypeNames), packageTypeNames: packageTypeNames.union(other.packageTypeNames))
		}
	}

	/// The types a generated file's declarations name where an import's level matters, apart by where they compile.
	struct FileNamedTypes {
		/// The types the declarations every build compiles name.
		let unconditional: NamedTypes
		/// The module's mock condition, and the types the declarations only builds in which it is active compile name;
		/// `nil` when the file holds no such declaration.
		let underMockCondition: (condition: String, namedTypes: NamedTypes)?
	}

	/// Whether a generated file's imports spell levels: whether any of the module's own files spells one.
	var spellsAccessLevels: Bool {
		!ownLevelsByModuleName.isEmpty
	}

	/// The types the declarations of `code`, a generated file's code, name where an import's level matters.
	func namedTypes(inGeneratedCode code: String) -> NamedTypes {
		// Only a declaration that spells one of these can name a type through a `public` or `package` import.
		guard code.contains("public ") || code.contains("package ") || code.contains("@usableFromInline") else {
			return NamedTypes(publicTypeNames: [], packageTypeNames: [])
		}
		let visitor = SignatureTypeNameVisitor(viewMode: .sourceAccurate)
		visitor.walk(Parser.parse(source: code))
		return NamedTypes(publicTypeNames: visitor.publicTypeNames, packageTypeNames: visitor.packageTypeNames)
	}

	/// How a generated file whose declarations name `namedTypes`, and which imports the modules named
	/// `importedModuleNames`, spells its import of the module named `moduleName`: under the mock condition as the
	/// declarations every build compiles and those under the condition need together, and elsewhere as the former need.
	/// - Parameter isExported: Whether the import the file writes is `@_exported`.
	func spelling(
		ofImportOf moduleName: String,
		isExported: Bool,
		namedTypes: FileNamedTypes,
		importedModuleNames: Set<String>,
	) -> Spelling {
		let elsewhere = spelling(ofImportOf: moduleName, isExported: isExported, namedTypes: namedTypes.unconditional, importedModuleNames: importedModuleNames)
		guard let (condition, mockNamedTypes) = namedTypes.underMockCondition else {
			return elsewhere
		}
		let whereMocksCompile = spelling(ofImportOf: moduleName, isExported: isExported, namedTypes: namedTypes.unconditional.union(mockNamedTypes), importedModuleNames: importedModuleNames)
		return whereMocksCompile == elsewhere ? elsewhere : .underMockCondition(condition, whereActive: whereMocksCompile, otherwise: elsewhere)
	}

	// MARK: Private

	/// How a generated file whose declarations name `namedTypes`, and which imports the modules named
	/// `importedModuleNames`, spells its import of the module named `moduleName`.
	/// - Parameter isExported: Whether the import the file writes is `@_exported`.
	private func spelling(
		ofImportOf moduleName: String,
		isExported: Bool,
		namedTypes: NamedTypes,
		importedModuleNames: Set<String>,
	) -> Spelling {
		let ownLevels = ownLevelsByModuleName[moduleName] ?? []
		let ownFilesSpellLevelBelowPublic = ownLevels.contains { $0 != .public && $0 != .open }
		if isExported || names(moduleName, amongTypesNamed: namedTypes.publicTypeNames, atLevel: .public, importedModuleNames: importedModuleNames) {
			return .level(.public)
		} else if names(moduleName, amongTypesNamed: namedTypes.packageTypeNames, atLevel: .package, importedModuleNames: importedModuleNames) {
			return ownFilesSpellLevelBelowPublic ? .level(.package) : .packageWhereImportsAreInternalByDefault
		} else {
			return ownFilesSpellLevelBelowPublic ? .level(.internal) : .noLevel
		}
	}

	/// The module that declares a type, as SafeDI read the declaration.
	private enum DeclaringModule: Hashable {
		/// The module the code is generated in, whose types need no import.
		case emitting
		/// Another module, by name.
		case named(String)
	}

	/// The levels the module's own files spell on their imports, by imported module.
	private let ownLevelsByModuleName: [String: Set<AccessLevel>]
	/// The modules declaring each type SafeDI read a declaration of in a module it knows, by the type's outermost name.
	private let declaringModulesByTypeName: [String: Set<DeclaringModule>]
	/// The modules that the dependencies' files declaring an `@Instantiable` that names a type import at `package` or
	/// wider, by the type's outermost name.
	private let dependencyFileModuleNamesByTypeName: [String: Set<String>]

	/// Whether one of the types named `typeNames`, which declarations of `level` or wider name, may be declared by the
	/// module named `moduleName`.
	private func names(_ moduleName: String, amongTypesNamed typeNames: Set<String>, atLevel level: AccessLevel, importedModuleNames: Set<String>) -> Bool {
		typeNames.contains { typeName in
			if let declaringModules = declaringModulesByTypeName[typeName] {
				declaringModules.contains(.named(moduleName))
			} else if WellKnownTypeNames.safeDI.contains(typeName) {
				moduleName == "SafeDI"
			} else if WellKnownTypeNames.swift.contains(typeName) {
				false
			} else if importedModuleNames.contains(typeName) {
				// A type qualified by its module's name.
				moduleName == typeName
			} else {
				mayDeclareUnreadType(named: typeName, moduleName: moduleName, atLevel: level)
			}
		}
	}

	/// Whether the module named `moduleName` may declare the type named `typeName`, which no declaration SafeDI read
	/// declares in a module it knows, named by a declaration of `level` or wider: Foundation for its well-known types,
	/// and any module but SafeDI, whose types SafeDI knows, that the module's own files import at `level` or wider, or,
	/// for a type that is not one of Foundation's well-known types, that a dependency's file declaring an `@Instantiable`
	/// that names it imports at `package` or wider.
	private func mayDeclareUnreadType(named typeName: String, moduleName: String, atLevel level: AccessLevel) -> Bool {
		if moduleName == "SafeDI" {
			false
		} else if WellKnownTypeNames.foundation.contains(typeName) {
			// A dependency's file that names one of Foundation's types says nothing of which other module declares it.
			moduleName == "Foundation" || ownFilesImport(moduleName, atLevelOrWider: level)
		} else {
			ownFilesImport(moduleName, atLevelOrWider: level)
				|| dependencyFileModuleNamesByTypeName[typeName]?.contains(moduleName) == true
		}
	}

	/// Whether the module's own files import the module named `moduleName` at `level` or wider.
	private func ownFilesImport(_ moduleName: String, atLevelOrWider level: AccessLevel) -> Bool {
		let widerLevels: Set<AccessLevel> = level == .package ? [.open, .public, .package] : [.open, .public]
		return !(ownLevelsByModuleName[moduleName] ?? []).isDisjoint(with: widerLevels)
	}
}

/// The names of the types every module can name without declaring them: Swift's, Foundation's and Dispatch's, and
/// SafeDI's own.
enum WellKnownTypeNames {
	/// The standard library's types, which no import provides.
	static let swift: Set<String> = [
		"Int", "Bool", "String", "Double", "Void", "Optional", "Array", "Dictionary", "Set",
		"Result", "Error", "Never", "Float", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
		"Character", "Substring", "AnyHashable", "Range", "ClosedRange", "Duration", "Clock", "ContinuousClock", "SuspendingClock",
		"Any", "AnyObject", "Sendable", "Actor", "Hashable", "Equatable", "Comparable", "Codable", "Encodable", "Decodable", "Identifiable",
	]

	/// Foundation's types, and Dispatch's, which Foundation re-exports.
	static let foundation: Set<String> = [
		"Date", "URL", "UUID", "Decimal", "TimeInterval", "Data", "Calendar", "Locale", "TimeZone", "Bundle", "UserDefaults",
		"NotificationCenter", "FileManager", "JSONEncoder", "JSONDecoder", "URLSession", "URLRequest", "URLComponents",
		"OperationQueue", "ProcessInfo", "DateFormatter", "NumberFormatter", "ISO8601DateFormatter", "IndexPath", "IndexSet",
		"CharacterSet", "DispatchQueue",
	]

	/// SafeDI's wrappers, which generated declarations name.
	static let safeDI: Set<String> = [
		"Instantiator", "ErasedInstantiator", "SendableInstantiator", "SendableErasedInstantiator", "LazilyInstantiated", "SendableLazilyInstantiated",
	]
}

/// Collects the outermost names of the types the `public`, `@usableFromInline`, and `package` declarations of a
/// generated file name in their signatures: parameter types and default values, result types, and stored property
/// types. Generated code spells each declaration's level on the declaration itself, never on an enclosing extension.
private final class SignatureTypeNameVisitor: SyntaxVisitor {
	var publicTypeNames = Set<String>()
	var packageTypeNames = Set<String>()

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		record(node.signature, modifiers: node.modifiers, attributes: node.attributes)
		return .skipChildren
	}

	override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		record(node.signature, modifiers: node.modifiers, attributes: node.attributes)
		return .skipChildren
	}

	override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		for binding in node.bindings {
			if let typeAnnotation = binding.typeAnnotation {
				record(typeAnnotation, modifiers: node.modifiers, attributes: node.attributes)
			}
		}
		return .skipChildren
	}

	/// A case's associated values are spelled at the access of the enum that declares it: a `public` enum of a generated scope
	/// names the inner seams whose enums it holds.
	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		for member in node.memberBlock.members {
			guard let enumCase = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
			for element in enumCase.elements {
				if let parameterClause = element.parameterClause {
					record(parameterClause, modifiers: node.modifiers, attributes: node.attributes)
				}
			}
		}
		return .visitChildren
	}

	private func record(_ signature: some SyntaxProtocol, modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax) {
		let isUsableFromInline = attributes.contains { attribute in
			attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "usableFromInline"
		}
		switch modifiers.spelledAccessLevel {
		case .open, .public:
			publicTypeNames.formUnion(TypeNameCollector.typeNames(in: signature))
		case .package:
			packageTypeNames.formUnion(TypeNameCollector.typeNames(in: signature))
		case .internal, .fileprivate, .private, nil:
			if isUsableFromInline {
				publicTypeNames.formUnion(TypeNameCollector.typeNames(in: signature))
			}
		}
	}
}

/// Collects the outermost name of each type a signature names: each identifier type, which for a qualified type is
/// its first component, and the base of each member access in a default value.
private final class TypeNameCollector: SyntaxVisitor {
	static func typeNames(in node: some SyntaxProtocol) -> Set<String> {
		let collector = TypeNameCollector(viewMode: .sourceAccurate)
		collector.walk(node)
		return collector.typeNames
	}

	override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
		typeNames.insert(node.name.identifier?.name ?? node.name.text)
		return .visitChildren
	}

	override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
		if let base = node.base?.as(DeclReferenceExprSyntax.self) {
			typeNames.insert(base.baseName.identifier?.name ?? base.baseName.text)
		}
		return .visitChildren
	}

	private var typeNames = Set<String>()
}
