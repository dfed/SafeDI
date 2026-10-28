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

/// A declaration that unqualified lookup of a type name can reach: a type, a generic parameter, or an extension that
/// adds conformances, each with its path from the module scope, such as `Feature.Configuration` for
/// `struct Configuration` declared in `enum Feature` or in `extension Feature`.
public struct NestedTypeDeclaration: Codable, Hashable, Sendable {
	public init(
		path: String,
		kind: Kind,
		access: Access,
		superclassCandidate: String? = nil,
		isCompilerDetermined: Bool = false,
		isAbsent: Bool = false,
		consultedCompilationConditions: [String] = [],
		conditionalCompilationDecisions: [ConditionalCompilationDecision] = [],
		filePath: String = "",
	) {
		self.path = path
		self.kind = kind
		self.access = access
		self.superclassCandidate = superclassCandidate
		self.isCompilerDetermined = isCompilerDetermined
		self.isAbsent = isAbsent
		self.consultedCompilationConditions = consultedCompilationConditions
		self.conditionalCompilationDecisions = conditionalCompilationDecisions
		self.filePath = filePath
	}

	public enum Kind: Codable, Hashable, Sendable {
		case classType
		case protocolType
		/// A struct, enum, actor, or type alias.
		case otherType
		/// A generic parameter of the type at the path without its last name.
		case genericParameter
	}

	/// The access level that decides which code can spell the declaration, ordered from the narrowest.
	public enum Access: Codable, Hashable, Sendable, Comparable {
		/// `private` or `fileprivate`: generated code, in other files, cannot spell it.
		case file
		/// `internal`: visible within its module.
		case module
		/// `package`: visible within its package, which SafeDI cannot see.
		case package
		/// `public` or `open`.
		case exported
	}

	/// The declaration's path from the module scope, without backticks or generic arguments.
	public let path: String
	public let kind: Kind
	/// The effective access level: a member of a `private` type is no more visible than the type.
	public let access: Access
	/// For a class or an actor, the first type its inheritance clause names, which is its superclass when it is a
	/// class, as written without backticks, or an empty string for one not spelled as a path of names, or with
	/// generic arguments. `nil` for a class or actor that names none, and for every other declaration.
	public let superclassCandidate: String?
	/// Whether the declaration is in an `#if` clause that only the compiler and destination can select, such as
	/// one guarded by `os(iOS)`, so that SafeDI cannot know whether it exists.
	public let isCompilerDetermined: Bool
	/// Whether the declaration is in an `#if` clause the conditions did not select, so that it does not exist under
	/// them. It still records the conditions and decisions that left it out, which decide generated code as much as
	/// those of a declaration that exists.
	public let isAbsent: Bool
	/// The bare conditions whose values decided whether the declaration exists, sorted.
	public let consultedCompilationConditions: [String]
	/// How the `#if` conditions that decided whether the declaration exists were evaluated. Generated code that a
	/// lookup reading the declaration decides asserts these.
	public let conditionalCompilationDecisions: [ConditionalCompilationDecision]
	/// The file the declaration is in, as the module names it.
	public internal(set) var filePath: String

	/// A key that orders every distinct declaration.
	fileprivate var sortKey: [String] {
		[
			path,
			"\(kind)",
			"\(access)",
			superclassCandidate ?? "",
			"\(isCompilerDetermined)",
			"\(isAbsent)",
			consultedCompilationConditions.joined(separator: ","),
			conditionalCompilationDecisions.map { "\($0.condition)=\($0.isActive)" }.joined(separator: ","),
			filePath,
		]
	}

	/// This declaration, in the file at `filePath`.
	func located(at filePath: String) -> NestedTypeDeclaration {
		var located = self
		located.filePath = filePath
		return located
	}

	/// The last name of the declaration's path: its own name.
	fileprivate var name: Substring {
		path[(path.lastIndex(of: ".").map { path.index(after: $0) } ?? path.startIndex)...]
	}

	fileprivate var isTypeDeclaration: Bool {
		kind != .genericParameter && !isAbsent
	}
}

/// The declarations that unqualified lookup of the names generated code spells can reach.
///
/// Generated code spells a dependency's type outside the declaration that wrote it, such as in an extension of
/// another type, where Swift does not search the declaring type's enclosing types. SafeDI therefore spells each name
/// that resolves to a nested type by its path from the module scope, as Swift resolves the name where it is written.
public struct NestedTypeDeclarations: Codable, Equatable, Sendable {
	// MARK: Initialization

	public init() {}

	public init(_ declarations: some Sequence<NestedTypeDeclaration>) {
		self.declarations = Array(declarations)
	}

	// MARK: Public

	/// The declarations, which may repeat one: walking a file records thousands that a lookup never reads, and
	/// collecting them unhashed costs far less than keeping them unique.
	public private(set) var declarations = [NestedTypeDeclaration]()

	/// The declarations, each once, in an order that depends only on them, so files that hold them are the same
	/// bytes whenever the declarations are the same.
	public var sortedDeclarations: [NestedTypeDeclaration] {
		Set(declarations).sorted { lhs, rhs in
			// Comparing the paths first spares building every other key for most pairs.
			lhs.path != rhs.path ? lhs.path < rhs.path : lhs.sortKey.lexicographicallyPrecedes(rhs.sortKey)
		}
	}

	public static func == (lhs: NestedTypeDeclarations, rhs: NestedTypeDeclarations) -> Bool {
		Set(lhs.declarations) == Set(rhs.declarations)
	}

	public var isEmpty: Bool {
		declarations.isEmpty
	}

	public init(from decoder: any Decoder) throws {
		try self.init(decoder.container(keyedBy: CodingKeys.self).decode([NestedTypeDeclaration].self, forKey: .declarations))
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(sortedDeclarations, forKey: .declarations)
	}

	private enum CodingKeys: String, CodingKey {
		case declarations
	}

	public mutating func record(_ declaration: NestedTypeDeclaration) {
		declarations.append(declaration)
	}

	public mutating func formUnion(_ other: NestedTypeDeclarations) {
		declarations += other.declarations
	}

	public func union(_ other: NestedTypeDeclarations) -> NestedTypeDeclarations {
		var union = self
		union.formUnion(other)
		return union
	}

	/// These declarations, each in the file at `filePath`.
	public func located(at filePath: String) -> NestedTypeDeclarations {
		NestedTypeDeclarations(declarations.map { $0.located(at: filePath) })
	}

	/// These declarations, each once and in the order `sortedDeclarations` gives, without those no lookup in `lookups`
	/// reaches, which change no qualification. The order is the one a cache that holds them reads back.
	public func restricted(to lookups: NestedTypeLookups) -> NestedTypeDeclarations {
		NestedTypeDeclarations(NestedTypeDeclarations(declarations.filter { declaration in
			lookups.paths.contains(declaration.path)
				|| lookups.typePaths.contains(declaration.path)
				|| (!lookups.inheritedNames.isEmpty && lookups.inheritedNames.contains(String(declaration.name)))
		}).sortedDeclarations)
	}

	/// The conditions that decided whether these declarations exist, which decided what lookups read.
	public var consultedCompilationConditions: Set<String> {
		Set(declarations.flatMap(\.consultedCompilationConditions))
	}

	/// The decisions that decided whether these declarations exist, which generated code asserts.
	public var conditionalCompilationDecisions: [ConditionalCompilationDecision] {
		declarations.flatMap(\.conditionalCompilationDecisions)
	}

	/// The last name of every declaration's path.
	fileprivate var lastNames: Set<String> {
		Set(declarations.map { String($0.name) })
	}
}

/// Every path that `NestedTypeDeclarations` can be asked about while `generate` qualifies the type names of some
/// instantiables. A declaration at no other path changes no qualification, so SafeDI keeps only these, and parses a
/// file that mentions no SafeDI declaration only when its text can declare one of them.
public struct NestedTypeLookups: Equatable, Sendable {
	/// - Parameters:
	///   - instantiables: The instantiables whose types `generate` qualifies.
	///   - declarations: The declarations known so far. The searched classes' and actors' first inherited names,
	///     which they hold, are looked up too.
	public init(instantiables: some Sequence<Instantiable>, declarations: NestedTypeDeclarations) {
		self.init(searchedNames: SearchedNames(instantiables: instantiables), declarations: declarations)
	}

	/// The names each type the instantiables' scopes search is asked for, which do not depend on declarations, so
	/// lookups computed again as declarations are found reuse them.
	public struct SearchedNames: Sendable {
		public init(instantiables: some Sequence<Instantiable>) {
			for instantiable in instantiables {
				let lexicalScope = LexicalScope(
					declaringType: instantiable.concreteInstantiable,
					unsearchedEnclosingTypeCount: instantiable.unsearchedEnclosingTypeCount,
				)
				var instantiableNames = Set<String>()
				for typeDescription in instantiable.typeDescriptionsQualifiedByLexicalLookup {
					typeDescription.forEachNameReference { instantiableNames.insert($0.withoutBackticks) }
				}
				names.formUnion(instantiableNames)
				for searchedType in lexicalScope.searchedTypes {
					namesBySearchedPath[searchedType.path, default: []].formUnion(instantiableNames)
				}
			}
		}

		fileprivate var names = Set<String>()
		fileprivate var namesBySearchedPath = [String: Set<String>]()
	}

	public init(searchedNames: SearchedNames, declarations: NestedTypeDeclarations) {
		names = searchedNames.names
		namesByTypePath = searchedNames.namesBySearchedPath
		typePaths = Set(namesByTypePath.keys)
		for (typePath, typeNames) in namesByTypePath {
			for name in typeNames {
				paths.insert(typePath + "." + name)
			}
		}
		// A searched class or actor whose first inherited type may be a class stops lookup unless that type is provably
		// a protocol, which every declaration of its name decides.
		for declaration in declarations.declarations where declaration.isTypeDeclaration && typePaths.contains(declaration.path) {
			if let inheritedName = declaration.superclassCandidate.flatMap(NestedTypeResolver.provablyProtocolCandidate) {
				inheritedNamesByTypePath[declaration.path, default: []].insert(inheritedName)
			}
		}
		inheritedNames = inheritedNamesByTypePath.values.reduce(into: Set()) { $0.formUnion($1) }
		outermostTypeNames = Set(typePaths.map { String($0.prefix { $0 != "." }) })
		typeNames = Set(typePaths.compactMap { $0.split(separator: ".").last.map(String.init) })
	}

	/// The path of every type, generic parameter, or member type a lookup can ask about: each name the
	/// instantiables' types spell, inside each type in `typePaths`.
	public private(set) var paths = Set<String>()
	/// The types lookups search: the types the instantiables' scopes search.
	public private(set) var typePaths = Set<String>()
	/// The first inherited name of each searched class or actor that may be a protocol: whether it is one depends on
	/// every declaration of the name.
	public private(set) var inheritedNames = Set<String>()
	/// The names the instantiables' types spell, which lookups ask for.
	public private(set) var names = Set<String>()
	/// The top-level types whose declarations and extensions can declare something a lookup reads.
	public private(set) var outermostTypeNames = Set<String>()
	/// The last name of every type lookups search, whose declarations decide whether it is a class.
	public private(set) var typeNames = Set<String>()

	/// Whether these lookups read only declarations `other`'s read too.
	public func isCovered(by other: NestedTypeLookups) -> Bool {
		paths.isSubset(of: other.paths)
			&& typePaths.isSubset(of: other.typePaths)
			&& inheritedNames.isSubset(of: other.inheritedNames)
	}

	/// The names lookups ask for that some declaration among `declarations` is a member type or generic parameter of.
	/// A lookup of any other name finds nothing, so the name keeps its spelling whatever the searched types are.
	public func declaredNames(among declarations: NestedTypeDeclarations) -> Set<String> {
		Set(declarations.declarations.lazy.filter { paths.contains($0.path) }.compactMap { $0.path.split(separator: ".").last.map(String.init) })
			.intersection(names)
	}

	/// These lookups, reading only the declarations at the paths of `declaredNames` and those of the types asked for
	/// them: every other lookup finds nothing whatever those types' declarations say, so most modules keep none.
	public func readingOnly(_ declaredNames: Set<String>) -> NestedTypeLookups {
		var readLookups = self
		// Every type in `typePaths` is asked for the names `namesByTypePath` holds for it.
		let readNamesByTypePath = namesByTypePath.mapValues { $0.intersection(declaredNames) }.filter { !$0.value.isEmpty }
		readLookups.typePaths = Set(readNamesByTypePath.keys)
		readLookups.paths = Set(readNamesByTypePath.flatMap { typePath, names in names.map { typePath + "." + $0 } })
		readLookups.inheritedNames = readLookups.typePaths.reduce(into: Set()) { inheritedNames, typePath in
			inheritedNames.formUnion(inheritedNamesByTypePath[typePath] ?? [])
		}
		return readLookups
	}

	// MARK: Private

	/// The names each type in `typePaths` is asked for.
	private var namesByTypePath = [String: Set<String>]()
	/// The first inherited names that may be protocols of the classes and actors at each path in `typePaths`.
	private var inheritedNamesByTypePath = [String: Set<String>]()
}

/// Resolves the type names an instantiable's types spell as Swift does where they are written, among the
/// declarations the instantiable's module can see.
public struct NestedTypeResolver {
	/// - Parameters:
	///   - declarations: The declarations of the instantiable's module and, unless `otherModuleDeclarations` lists
	///     them, of the modules it depends on.
	///   - otherModuleDeclarations: The declarations of each module the instantiable's module depends on, which it sees
	///     only when they are public.
	///   - moduleFilePaths: The files of the instantiable's module among the files `declarations` name, when one
	///     input list holds every module's files, or `nil` when every file `declarations` name is the module's.
	public init(
		declarations: NestedTypeDeclarations,
		otherModuleDeclarations: [NestedTypeDeclarations] = [],
		moduleFilePaths: Set<String>? = nil,
	) {
		var declarationsByPath = [String: [Located]]()
		var declarationsByName = [Substring: [Located]]()
		func add(_ declaration: NestedTypeDeclaration, isInModule: Bool, origin: Origin) {
			let located = Located(declaration: declaration, isInModule: isInModule, origin: origin)
			declarationsByPath[declaration.path, default: []].append(located)
			declarationsByName[declaration.name, default: []].append(located)
		}
		// The same declaration can arrive more than once, as when generate adds what a file walked again declares to
		// what scan kept, and counts once: two declarations of a type are different modules' types.
		for declaration in Set(declarations.declarations) where !declaration.isAbsent {
			if let moduleFilePaths, !moduleFilePaths.contains(declaration.filePath) {
				// One input list holds every module's files, and nothing says which module a dependency file is in.
				add(declaration, isInModule: false, origin: .file(declaration.filePath))
			} else {
				add(declaration, isInModule: true, origin: .module)
			}
		}
		for (index, moduleDeclarations) in otherModuleDeclarations.enumerated() {
			for declaration in Set(moduleDeclarations.declarations) where !declaration.isAbsent {
				add(declaration, isInModule: false, origin: .otherModule(index))
			}
		}
		self.declarationsByPath = declarationsByPath
		self.declarationsByName = declarationsByName
		self.moduleFilePaths = moduleFilePaths
		memberNames = otherModuleDeclarations.reduce(into: declarations.lastNames) { $0.formUnion($1.lastNames) }
	}

	public var isEmpty: Bool {
		declarationsByPath.isEmpty
	}

	/// `typeDescription` with each name that names a nested type spelled from the module scope, as Swift resolves it
	/// inside the scope of `instantiable`, or `nil` when no name changes.
	public func qualifying(_ typeDescription: TypeDescription, within instantiable: Instantiable) -> TypeDescription? {
		// Most modules declare nothing any lookup reads, and most names are no declaration's.
		guard !isEmpty else { return nil }
		var spellsMemberName = false
		typeDescription.forEachNameReference { name in
			spellsMemberName = spellsMemberName || memberNames.contains(name.withoutBackticks)
		}
		guard spellsMemberName else { return nil }
		let observer = Observer(
			filePath: instantiable.sourceFilePath,
			// An instantiable without a source file is found in no file of the module.
			isInModule: moduleFilePaths.map { moduleFilePaths in instantiable.sourceFilePath.map(moduleFilePaths.contains) == true } ?? true,
		)
		let lexicalScope = LexicalScope(
			declaringType: instantiable.concreteInstantiable,
			unsearchedEnclosingTypeCount: instantiable.unsearchedEnclosingTypeCount,
		)
		var isQualified = false
		let qualified = typeDescription.mappingNameReferences { name, generics in
			guard memberNames.contains(name.withoutBackticks),
			      let enclosingType = enclosingType(ofTypeNamed: name.withoutBackticks, searching: lexicalScope, as: observer)
			else {
				return .simple(name: name, generics: generics)
			}
			isQualified = true
			return .nested(name: name, parentType: enclosingType, generics: generics)
		}
		return isQualified ? qualified : nil
	}

	/// The name `candidate`, a class's or actor's first inherited type as `NestedTypeDeclaration.superclassCandidate`
	/// spells it, when it may be provably a protocol, or `nil` when it cannot be: a path of names, or a type SafeDI
	/// cannot spell as one, could name a class whatever the declarations say.
	static func provablyProtocolCandidate(_ candidate: String) -> String? {
		!candidate.isEmpty && !candidate.contains(".") ? candidate : nil
	}

	// MARK: Private

	/// The instantiable whose types are resolved.
	private struct Observer {
		let filePath: String?
		let isInModule: Bool
	}

	/// Where a declaration came from, which decides whose type its path names.
	private enum Origin: Hashable {
		/// The instantiable's module.
		case module
		/// A file of a module the instantiable's module depends on, when one input list holds every module's files.
		case file(String)
		/// The module info of the module at this index among those the instantiable's module depends on.
		case otherModule(Int)
	}

	private struct Located {
		let declaration: NestedTypeDeclaration
		let isInModule: Bool
		let origin: Origin
	}

	/// What the members of a type with one name are.
	private enum MemberLookup: Equatable {
		/// The type that declares the member, which spells it from the module scope.
		case declared(by: TypeDescription)
		/// Lookup stops here, and the name keeps its spelling: the member is a generic parameter or one generated code
		/// cannot spell, or SafeDI cannot see every member that could match.
		case unqualifiable
		/// The type has no member of that name, so lookup continues outward unless the type inherits one.
		case absent(inheritedTypeName: String?)
	}

	private enum Visibility {
		case visible
		case invisible
		/// Lookup cannot know whether the declaration is visible.
		case unknown
	}

	private let declarationsByPath: [String: [Located]]
	private let declarationsByName: [Substring: [Located]]
	private let moduleFilePaths: Set<String>?
	/// The last name of every declaration's path. Lookup of any other name finds no member type or generic
	/// parameter anywhere, so the name keeps its spelling.
	private let memberNames: Set<String>

	/// The type at whose level `name` resolves to a nested type, searching outward from the innermost type of
	/// `scope`, or `nil` when the name keeps its spelling.
	private func enclosingType(ofTypeNamed name: String, searching scope: LexicalScope, as observer: Observer) -> TypeDescription? {
		for searchedType in scope.searchedTypes {
			switch member(named: name, of: searchedType.path, type: searchedType.type, as: observer) {
			case let .declared(type):
				return type
			case .unqualifiable:
				return nil
			case let .absent(inheritedTypeName):
				// A class's superclass's nested types are members too, found before those of the types enclosing it.
				// SafeDI does not follow superclasses: a class whose first inherited type may be a class keeps every
				// name it does not declare itself as written. A protocol's members never change a spelling: swiftc
				// finds a protocol's associated types and type aliases only when no type of the name is in scope.
				guard inheritedTypeName.map({ isProvablyProtocol(named: $0, as: observer) }) ?? true else {
					return nil
				}
			}
		}
		return nil
	}

	private func member(
		named name: String,
		of path: String,
		type: TypeDescription,
		as observer: Observer,
	) -> MemberLookup {
		var typeDeclarations = [Located]()
		for located in declarationsByPath[path] ?? [] where located.declaration.isTypeDeclaration {
			switch visibility(of: located, as: observer) {
			case .visible:
				typeDeclarations.append(located)
			case .invisible:
				break
			case .unknown:
				return .unqualifiable
			}
		}
		// With no declaration, the type is declared where SafeDI cannot see its generic parameters or whether it is a
		// class, and with more than one, they are different modules' types of the same name.
		guard typeDeclarations.count == 1, let typeDeclaration = typeDeclarations.first, !typeDeclaration.declaration.isCompilerDetermined else {
			return .unqualifiable
		}

		// The declarations at the path decide together, whatever order they are in: a generic parameter hides a member
		// type of the same name, unless SafeDI cannot know whether it exists or is visible. Only a declaration from
		// where the type is declared is the type's: another module's declaration at the same path is of its own type
		// of that name, or of one SafeDI cannot tell apart from it.
		var memberDeclarations = [NestedTypeDeclaration]()
		for located in declarationsByPath[path + "." + name] ?? [] where located.origin == typeDeclaration.origin {
			switch visibility(of: located, as: observer) {
			case .visible:
				memberDeclarations.append(located.declaration)
			case .invisible:
				break
			case .unknown:
				return .unqualifiable
			}
		}
		if memberDeclarations.contains(where: { $0.kind == .genericParameter }) {
			return .unqualifiable
		}
		if !memberDeclarations.isEmpty {
			return memberDeclarations.contains(where: \.isCompilerDetermined) ? .unqualifiable : .declared(by: type)
		}
		// SafeDI reads every file of the observer's module, but not every file of the modules it depends on, whose
		// extensions may declare a member of the name.
		guard observer.isInModule, typeDeclaration.isInModule else {
			return .unqualifiable
		}
		return .absent(inheritedTypeName: typeDeclaration.declaration.superclassCandidate)
	}

	/// Whether the type an inheritance clause names `name` is provably a protocol: no declaration SafeDI read that
	/// could be visible where it is written gives the name to anything but a protocol, and either a protocol of the
	/// name is visible or the name is one of `protocolNames`.
	private func isProvablyProtocol(named name: String, as observer: Observer) -> Bool {
		guard Self.provablyProtocolCandidate(name) != nil else { return false }
		var declaresVisibleProtocol = false
		for located in declarationsByName[Substring(name)] ?? [] {
			let visibility = visibility(of: located, as: observer)
			switch (located.declaration.kind, visibility) {
			case (_, .invisible):
				break
			case (.protocolType, .visible):
				declaresVisibleProtocol = declaresVisibleProtocol || !located.declaration.isCompilerDetermined
			case (.protocolType, .unknown):
				break
			case (.classType, _), (.otherType, _), (.genericParameter, _):
				return false
			}
		}
		return declaresVisibleProtocol || Self.protocolNames.contains(name)
	}

	private func visibility(of located: Located, as observer: Observer) -> Visibility {
		switch located.declaration.access {
		case .file:
			// Generated code is in another file, where it cannot spell the declaration.
			return .unknown
		case .module, .package, .exported:
			break
		}
		switch (observer.isInModule, located.isInModule) {
		case (true, true):
			return .visible
		case (true, false):
			// A module sees what the modules it depends on make public.
			switch located.declaration.access {
			case .exported:
				return .visible
			case .module, .file:
				return .invisible
			case .package:
				return .unknown
			}
		case (false, true):
			// A module that this module depends on cannot see this module's declarations.
			return .invisible
		case (false, false):
			// Both are in modules this module depends on, which may or may not be the same one.
			return located.declaration.filePath == observer.filePath ? .visible : .unknown
		}
	}

	/// Protocols of the standard library, Foundation, Combine, Observation, and SafeDI that a class's inheritance clause
	/// commonly names first, which SafeDI takes to be protocols when no declaration it read gives the name to anything
	/// else.
	private static let protocolNames: Set<String> = [
		"CaseIterable",
		"Codable",
		"Comparable",
		"CustomDebugStringConvertible",
		"CustomStringConvertible",
		"Decodable",
		"Encodable",
		"Equatable",
		"Error",
		"Hashable",
		"Identifiable",
		"Instantiable",
		"Observable",
		"ObservableObject",
		"Sendable",
	]
}

extension Instantiable {
	/// The types whose nested type names `generate` qualifies by lexical lookup from this declaration: every
	/// dependency's property type, the type that fulfills an instantiated or aliased dependency, the initializer's
	/// and the hand-written mock's argument types, and the hand-written mock's return type.
	public var typeDescriptionsQualifiedByLexicalLookup: [TypeDescription] {
		var typeDescriptions = [TypeDescription]()
		for dependency in dependencies {
			typeDescriptions.append(dependency.property.typeDescription)
			switch dependency.source {
			case let .instantiated(fulfillingTypeDescription, _):
				if let fulfillingTypeDescription {
					typeDescriptions.append(fulfillingTypeDescription)
				}
			case let .aliased(fulfillingProperty, _, _):
				typeDescriptions.append(fulfillingProperty.typeDescription)
			case .forwarded, .received:
				break
			}
		}
		typeDescriptions.append(contentsOf: (initializer?.arguments ?? []).map(\.typeDescription))
		typeDescriptions.append(contentsOf: (mockInitializer?.arguments ?? []).map(\.typeDescription))
		if let mockReturnType {
			typeDescriptions.append(mockReturnType)
		}
		return typeDescriptions
	}
}

/// The types whose members and generic parameters unqualified lookup searches from inside a declaration.
public struct LexicalScope {
	/// - Parameters:
	///   - declaringType: The type whose declaration the name is written in.
	///   - unsearchedEnclosingTypeCount: How many of the outermost types enclosing `declaringType`, counting
	///     `declaringType` itself, lookup does not search, because the declaration is in an extension.
	public init(declaringType: TypeDescription, unsearchedEnclosingTypeCount: Int) {
		var searchedTypes = [(path: String, type: TypeDescription)]()
		var type: TypeDescription? = declaringType.strippingGenerics
		while let searchedType = type, let namePath = searchedType.namePath, namePath.count > unsearchedEnclosingTypeCount {
			searchedTypes.append((namePath.joined(separator: "."), searchedType))
			type = searchedType.popNested?.strippingGenerics
		}
		self.searchedTypes = searchedTypes
	}

	/// Each searched type, innermost first, with its path from the module scope.
	let searchedTypes: [(path: String, type: TypeDescription)]
}

extension TypeDescription {
	/// The names of this type and of the types enclosing it, outermost first, without generic arguments or
	/// backticks: `["Feature", "Service"]` for `Feature.Service`. `nil` when this type is not spelled as a path of names.
	public var namePath: [String]? {
		switch self {
		case let .simple(name, _):
			[name.withoutBackticks]
		case let .nested(name, parentType, _):
			parentType.namePath.map { $0 + [name.withoutBackticks] }
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .optional, .some, .tuple, .unknown, .void:
			nil
		}
	}

	/// Calls `body` with the first name of every type this type spells, as `mappingNameReferences` visits them.
	fileprivate func forEachNameReference(_ body: (String) -> Void) {
		switch self {
		case .unknown, .void:
			break
		case let .simple(name, generics):
			body(name)
			for generic in generics {
				generic.forEachNameReference(body)
			}
		case let .nested(_, parentType, generics):
			parentType.forEachNameReference(body)
			for generic in generics {
				generic.forEachNameReference(body)
			}
		case let .composition(types):
			for type in types {
				type.forEachNameReference(body)
			}
		case let .optional(type), let .implicitlyUnwrappedOptional(type), let .some(type), let .any(type), let .metatype(type, _), let .attributed(type, _, _), let .array(type):
			type.forEachNameReference(body)
		case let .dictionary(key, value):
			key.forEachNameReference(body)
			value.forEachNameReference(body)
		case let .tuple(elements):
			for element in elements {
				element.typeDescription.forEachNameReference(body)
			}
		case let .closure(arguments, _, _, returnType):
			for argument in arguments {
				argument.forEachNameReference(body)
			}
			returnType.forEachNameReference(body)
		}
	}

	// MARK: Private

	/// This type with the first name of every type it spells replaced by what `transform` returns for that name and
	/// its generic arguments, each already transformed. A nested type's own name and generic arguments are kept, and
	/// its parent type is transformed in turn.
	fileprivate func mappingNameReferences(_ transform: (String, [TypeDescription]) -> TypeDescription) -> TypeDescription {
		switch self {
		case .unknown, .void:
			self
		case let .simple(name, generics):
			transform(name, generics.map { $0.mappingNameReferences(transform) })
		case let .nested(name, parentType, generics):
			.nested(
				name: name,
				parentType: parentType.mappingNameReferences(transform),
				generics: generics.map { $0.mappingNameReferences(transform) },
			)
		case let .composition(types):
			.composition(UnorderedEquatingCollection(types.map { $0.mappingNameReferences(transform) }))
		case let .optional(type):
			.optional(type.mappingNameReferences(transform))
		case let .implicitlyUnwrappedOptional(type):
			.implicitlyUnwrappedOptional(type.mappingNameReferences(transform))
		case let .some(type):
			.some(type.mappingNameReferences(transform))
		case let .any(type):
			.any(type.mappingNameReferences(transform))
		case let .metatype(type, isType):
			.metatype(type.mappingNameReferences(transform), isType: isType)
		case let .attributed(type, specifiers, attributes):
			.attributed(type.mappingNameReferences(transform), specifiers: specifiers, attributes: attributes)
		case let .array(element):
			.array(element: element.mappingNameReferences(transform))
		case let .dictionary(key, value):
			.dictionary(key: key.mappingNameReferences(transform), value: value.mappingNameReferences(transform))
		case let .tuple(elements):
			.tuple(elements.map { TupleElement(label: $0.label, $0.typeDescription.mappingNameReferences(transform)) })
		case let .closure(arguments, isAsync, doesThrow, returnType):
			.closure(
				arguments: arguments.map { $0.mappingNameReferences(transform) },
				isAsync: isAsync,
				doesThrow: doesThrow,
				returnType: returnType.mappingNameReferences(transform),
			)
		}
	}
}

extension String {
	/// This identifier without the backticks that let it be spelled as a keyword: `Type` for `` `Type` ``.
	var withoutBackticks: String {
		hasPrefix("`") && hasSuffix("`") && count > 1 ? String(dropFirst().dropLast()) : self
	}
}
