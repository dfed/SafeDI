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

/// The names that types declared inside other types make available to unqualified lookup, each spelled as its
/// path from the module scope: `Feature.Configuration` for `struct Configuration` declared in `enum Feature` or in
/// `extension Feature`.
///
/// Generated code spells a dependency's type outside the declaration that wrote it, such as in an extension of
/// another type, where Swift does not search the declaring type's enclosing types. SafeDI therefore spells each name
/// that resolves to a nested type by its path from the module scope. Top-level types need no path, so only nested
/// declarations are recorded.
public struct NestedTypeDeclarations: Codable, Hashable, Sendable {
	// MARK: Initialization

	public init() {}

	public init(typeNames: Set<String>, genericParameterNames: Set<String>) {
		self.typeNames = typeNames
		self.genericParameterNames = genericParameterNames
	}

	// MARK: Public

	/// The path of every nested struct, class, enum, actor, protocol, and type alias.
	public private(set) var typeNames = Set<String>()
	/// The path of every generic parameter of a nested type, such as `Feature.Box.Value` for `Value` in
	/// `enum Feature { struct Box<Value> {} }`. A generic parameter hides the nested types of the declarations
	/// enclosing its type.
	public private(set) var genericParameterNames = Set<String>()

	public var isEmpty: Bool {
		typeNames.isEmpty && genericParameterNames.isEmpty
	}

	/// Records a type named `name` declared inside `enclosingType`, and its generic parameters. A top-level type,
	/// whose `enclosingType` is `nil`, needs no path, so nothing is recorded for it.
	public mutating func recordType(named name: String, genericParameterNames: [String] = [], within enclosingType: TypeDescription?) {
		guard let enclosingPath = enclosingType?.namePath else { return }
		let path = enclosingPath + [name.withoutBackticks]
		typeNames.insert(path.joined(separator: "."))
		for genericParameterName in genericParameterNames {
			self.genericParameterNames.insert((path + [genericParameterName.withoutBackticks]).joined(separator: "."))
		}
	}

	public mutating func formUnion(_ other: NestedTypeDeclarations) {
		typeNames.formUnion(other.typeNames)
		genericParameterNames.formUnion(other.genericParameterNames)
	}

	public func union(_ other: NestedTypeDeclarations) -> NestedTypeDeclarations {
		var union = self
		union.formUnion(other)
		return union
	}

	/// These declarations without those that no lookup in `lookups` reaches, which change no qualification.
	public func restricted(to lookups: NestedTypeLookups) -> NestedTypeDeclarations {
		NestedTypeDeclarations(
			typeNames: typeNames.filter(lookups.paths.contains),
			genericParameterNames: genericParameterNames.filter(lookups.paths.contains),
		)
	}

	/// The type that the unqualified name `name`, written inside `scope`, names when it names a nested type: the
	/// innermost type `scope` searches that declares a type of that name, as Swift searches outward from the
	/// innermost type. Returns `nil` when the name names a generic parameter, or no nested type, in which case it
	/// names a top-level type or one this module cannot see, and its spelling needs no change.
	func enclosingType(ofNestedTypeNamed name: String, searching scope: LexicalScope) -> TypeDescription? {
		let name = name.withoutBackticks
		for searchedType in scope.searchedTypes {
			let candidate = searchedType.path + "." + name
			if genericParameterNames.contains(candidate) {
				return nil
			} else if typeNames.contains(candidate) {
				return searchedType.type
			}
		}
		return nil
	}
}

/// Every path that `NestedTypeDeclarations` can be asked about while `generate` qualifies the nested type names of
/// some instantiables: for each name their types spell, the name inside each type their lexical scopes search. A
/// declaration whose path is not among them changes no qualification, so SafeDI keeps only those that are, and looks
/// for declarations in a file that mentions no SafeDI declaration only when the file's text can declare one of them.
public struct NestedTypeLookups: Equatable, Sendable {
	public init(instantiables: some Sequence<Instantiable>) {
		for instantiable in instantiables {
			let lexicalScope = LexicalScope(
				declaringType: instantiable.concreteInstantiable,
				unsearchedEnclosingTypeCount: instantiable.unsearchedEnclosingTypeCount,
			)
			// Every searched type is, or is nested in, the same top-level type.
			outermostTypeNames.formUnion(lexicalScope.searchedTypes.prefix(1).map { String($0.path.prefix { $0 != "." }) })
			for typeDescription in instantiable.typeDescriptionsQualifiedByLexicalLookup {
				_ = typeDescription.mappingNameReferences { name, generics in
					let name = name.withoutBackticks
					names.insert(name)
					for searchedType in lexicalScope.searchedTypes {
						paths.insert(searchedType.path + "." + name)
					}
					return .simple(name: name, generics: generics)
				}
			}
		}
	}

	/// The path of every type or generic parameter a lookup can ask about, such as `Feature.Service.Configuration`
	/// and `Feature.Configuration` for `Configuration` spelled inside `Feature.Service`.
	public private(set) var paths = Set<String>()
	/// The last name of every path in `paths`: the names that lookups ask for.
	public private(set) var names = Set<String>()
	/// The first name of every path in `paths`: the top-level types whose declarations and extensions can declare
	/// a type that a lookup asks about.
	public private(set) var outermostTypeNames = Set<String>()

	/// These lookups without those `other` makes. The names and outermost type names are kept whole, so they are
	/// a superset of those of the remaining paths.
	public func subtracting(_ other: NestedTypeLookups) -> NestedTypeLookups {
		var remainder = self
		remainder.paths.subtract(other.paths)
		return remainder
	}
}

/// The names of the types and generic parameters that an `#if` block declares in any of its clauses, and the
/// conditions whose values selected the clauses `FileVisitor` walked.
public struct ConditionallyDeclaredTypes: Hashable, Sendable {
	public init(names: Set<String>, consultedCompilationConditions: Set<String>) {
		self.names = names
		self.consultedCompilationConditions = consultedCompilationConditions
	}

	public let names: Set<String>
	public let consultedCompilationConditions: Set<String>
}

extension [ConditionallyDeclaredTypes] {
	/// The conditions that decided which of the declarations `lookups` asks about were recorded: those of each
	/// block that declares a name a lookup asks for.
	public func consultedCompilationConditions(decidingDeclarationsFor lookups: NestedTypeLookups) -> Set<String> {
		var consultedCompilationConditions = Set<String>()
		for block in self where !block.names.isDisjoint(with: lookups.names) {
			consultedCompilationConditions.formUnion(block.consultedCompilationConditions)
		}
		return consultedCompilationConditions
	}
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
	fileprivate let searchedTypes: [(path: String, type: TypeDescription)]
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

	/// This type with each name that `declarations` show to name a nested type spelled from the module scope,
	/// as Swift resolves the name where the type is written.
	/// - Parameters:
	///   - scope: The types unqualified lookup searches where this type is written.
	///   - declarations: The nested types and generic parameters that unqualified lookup can find.
	/// - Returns: The qualified type, or `nil` when no name in this type names a nested type.
	public func qualifyingNestedTypeNames(
		within scope: LexicalScope,
		among declarations: NestedTypeDeclarations,
	) -> TypeDescription? {
		// Most modules declare no nested type that any lookup reaches.
		guard !declarations.isEmpty else { return nil }
		var isQualified = false
		let qualified = mappingNameReferences { name, generics in
			guard let enclosingType = declarations.enclosingType(ofNestedTypeNamed: name, searching: scope) else {
				return .simple(name: name, generics: generics)
			}
			isQualified = true
			return .nested(name: name, parentType: enclosingType, generics: generics)
		}
		return isQualified ? qualified : nil
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
