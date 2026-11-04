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

/// How visible each type a seam's generated initializer names is, as far as SafeDI can prove it from the declarations
/// it records: a type's own `@Instantiable` declaration, a type's plain declaration (`PlainTypeDeclaration`), the
/// initializers, `instantiate(…)` methods and hand-written mock methods that take it as a dependency, and a short list
/// of standard types. A seam parameter is as visible as the narrowest type it names, and a type nothing proves counts
/// as `internal`.
///
/// Every declaration of the map is an ENTRY, of one of three kinds: a type declaration outside every extension, whose
/// access is its spelled chain, which the compiler enforces, so no mention raises it (EXACT); a type declaration inside
/// an extension, bounded by the extended type's own exact entry of the same module when there is one (then EXACT too),
/// and otherwise by the extension's spelled level, `internal` when it spells none or extends a nested type; and an
/// extension-based declaration, bounded the same way. An entry that is not exact is raised by every mention of its
/// type, at the level of the member that mentions it capped by the proof of the entry that member belongs to – a least
/// fixed point, which depends on no declaration order or name. An entry inside an extension of a type, or an
/// extension-based entry, whose type has no exact entry of the same module but a plain declaration SafeDI records, is
/// exact too, bounded by that declaration.
///
/// A type with no entry is proven by its plain declaration, exactly, when SafeDI records one the seam's module can name
/// (`plainDeclarations(named:mentionedFrom:)`): the compiler enforces that declaration's access, so no mention raises
/// it. Otherwise it is proven by the mentions of declarations in the seam's module or a module whose declaration
/// receives the parameter.
///
/// The proof reads only the map the signature is computed from, so the seam's module and every caller compute the same
/// proofs. A mention is the type of an argument of a construction initializer, `instantiate(…)` method or hand-written
/// mock method whose inner label is the label of a dependency of the entry it is recorded on: what the code SafeDI
/// generates passes that argument, so the compiler has checked the type against the member's access. A result type,
/// another initializer, a default-valued argument bound to no dependency, and a member with generic parameters
/// mention nothing.
public struct TypeAccessProof: Sendable {
	/// - Parameters:
	///   - instantiables: The declaration map the signature is computed from.
	///   - plainTypeDeclarations: The plain type declarations of the modules whose declarations the map holds, each
	///     with the module that declares it, or `nil` when SafeDITool does not know it.
	///   - isOwnFile: Whether a file is one of the run's own files, which lets two declarations of a module SafeDI knows
	///     no name of count as one module's; `nil` where the computation is of another module's seams, whose module is
	///     named.
	public init(instantiables: [TypeDescription: Instantiable], plainTypeDeclarations: [PlainTypeDeclaration], isOwnFile: (@Sendable (String) -> Bool)?) {
		self.instantiables = instantiables
		var entries = [TypeDescription: Instantiable]()
		for (key, instantiable) in instantiables where key == instantiable.concreteInstantiable {
			entries[key] = instantiable
		}
		self.entries = entries
		// A declaration no other file can name names nothing a seam's generated initializer or a mock can mention.
		let plainTypeDeclarations = PlainTypeDeclarations(
			plainTypeDeclarations,
			entryTypes: Set(entries.keys),
			moduleNames: Set(instantiables.values.compactMap(\.moduleName)),
			isOwnFile: isOwnFile,
		)
		self.plainTypeDeclarations = plainTypeDeclarations

		// The exact starts, computed before the fixed point and memoized by type: each step through a bounding entry
		// removes a component of the type, so the recursion ends.
		var kinds = [TypeDescription: EntryKind]()
		func kind(of type: TypeDescription) -> EntryKind? {
			if let kind = kinds[type] {
				return kind
			}
			guard let entry = entries[type] else { return nil }
			let entryKind: EntryKind
			if entry.declarationType.isExtension {
				// The type an extension-based declaration declares is declared elsewhere: its plain declaration, when
				// SafeDI records one the extension's module can name, is its access.
				entryKind = if let resolved = plainTypeDeclarations.declarations(named: entry.concreteInstantiable, mentionedFrom: .declaration(entry)) {
					.plainDeclaration(resolved)
				} else {
					.extensionBased(start: Self.extensionBound(entry.access, extendedType: entry.concreteInstantiable))
				}
			} else if let enclosingExtension = entry.enclosingExtensionAccess {
				var extendedType: TypeDescription? = entry.concreteInstantiable
				for _ in 0...entry.enclosingTypeAccess.count {
					extendedType = extendedType?.popNested
				}
				let ownLevel = Self.normalized(AccessLevel.effective(ofTypeDeclaredBy: entry))
				if let extendedType,
				   let bounding = entries[extendedType],
				   let boundingKind = kind(of: extendedType),
				   let boundingProof = boundingKind.exactProof,
				   Self.isInSameModule(entry, bounding, isOwnFile: isOwnFile)
				{
					entryKind = .exactInExtension(extendedType: extendedType, ownLevel: ownLevel, extendedTypeProof: boundingProof, extendedTypeIsPlain: boundingKind.isPlainDeclaration)
				} else if let extendedType, let resolved = plainTypeDeclarations.declarations(named: extendedType, mentionedFrom: .declaration(entry)) {
					// No `@Instantiable` declaration of the extended type bounds the entry, but its plain declaration,
					// which the compiler caps the entry by, does.
					entryKind = .exactInExtension(extendedType: extendedType, ownLevel: ownLevel, extendedTypeProof: resolved.level, extendedTypeIsPlain: true)
				} else {
					entryKind = .inExtension(
						extendedType: extendedType,
						extension: enclosingExtension,
						start: ownLevel.capped(by: extendedType.map { Self.extensionBound(enclosingExtension, extendedType: $0) } ?? .internal),
						extendedTypeHasEntry: extendedType.flatMap { entries[$0] } != nil,
					)
				}
			} else {
				entryKind = .typeDeclaration(level: Self.normalized(AccessLevel.effective(ofTypeDeclaredBy: entry)))
			}
			kinds[type] = entryKind
			return entryKind
		}
		for type in entries.keys {
			_ = kind(of: type)
		}
		self.kinds = kinds

		// Every mention, from every member of every entry of the map, under each key it is recorded on: a `mockOnly`
		// merge carries its mock under the key it merges into.
		var mentions = [TypeDescription: [Mention]]()
		var seenMembers = Set<MemberKey>()
		for (_, carrier) in instantiables.sorted(by: { $0.key < $1.key }) {
			let dependencyLabels = Set(carrier.dependencies.map(\.property.label))
			for member in Self.provingMembers(of: carrier) {
				guard seenMembers.insert(MemberKey(carrier: carrier.concreteInstantiable, member: member.kind, location: member.location)).inserted else { continue }
				for argument in member.initializer.arguments where dependencyLabels.contains(argument.innerLabel) {
					for mentionedType in Self.mentionedTypes(in: argument.typeDescription) {
						mentions[mentionedType, default: []].append(Mention(
							carrier: carrier.concreteInstantiable,
							member: member.kind,
							argumentLabels: member.initializer.arguments.map(\.label),
							ownLevel: member.ownLevel,
							moduleName: member.moduleName,
							location: member.location,
						))
					}
				}
			}
		}
		self.mentions = mentions

		// The least fixed point: every entry that is not exact starts at its bound and is raised by each mention of its
		// type, at the mentioning member's level capped by its carrier's current proof, never above `public`.
		var proofs = [TypeDescription: AccessLevel]()
		for (type, kind) in kinds {
			proofs[type] = kind.start
		}
		var changed = true
		while changed {
			changed = false
			for type in kinds.keys.sorted() where kinds[type]?.exactProof == nil {
				let raised = (mentions[type] ?? []).reduce(proofs[type] ?? .internal) { level, mention in
					max(level, mention.ownLevel.capped(by: proofs[mention.carrier] ?? .internal))
				}
				if raised != proofs[type] {
					proofs[type] = raised
					changed = true
				}
			}
		}
		self.proofs = proofs
	}

	// MARK: Public

	/// What proves a seam parameter's access: its level, and the narrowest type its type names with how that type is
	/// proven, which a diagnostic explains. `nil` cause when every type it names is `public`.
	public struct ParameterAccess: Sendable {
		public let level: AccessLevel
		public let cause: Cause?
	}

	/// How the narrowest type a parameter names is proven.
	public enum Cause: Sendable {
		/// The type's own `@Instantiable` declaration, outside every extension, proves it.
		case ownDeclaration(type: TypeDescription, level: AccessLevel)
		/// The type's plain declarations (`PlainTypeDeclaration`), each in its module, prove it at `level`, the
		/// narrowest of their levels. `namesModules` when a declaration is in another module than the one whose
		/// declaration mentions the type, so a diagnostic names each declaration's module.
		case plainDeclaration(type: TypeDescription, level: AccessLevel, declarations: [PlainTypeDeclaration], namesModules: Bool)
		/// The type is declared inside an extension of `extendedType`, whose own declaration bounds it – its
		/// `@Instantiable` declaration in the same module, or, when `extendedTypeIsPlain`, its plain declaration: at its
		/// own level `ownLevel`, capped by `extendedTypeLevel`.
		case declarationInExtensionOfRecordedType(type: TypeDescription, ownLevel: AccessLevel, extendedType: TypeDescription, extendedTypeLevel: AccessLevel, spellsOwnLevel: Bool, extendedTypeIsPlain: Bool)
		/// The type is declared inside an extension SafeDI does not read as bounding it, or is an extension-based
		/// declaration – a `mockOnly` one when `isMockOnly` – : it is proven at its extension's bound, raised by
		/// `raisingProvers` when any mentions it more widely.
		case declarationInExtension(type: TypeDescription, level: AccessLevel, extendedType: TypeDescription?, extensionIsSpelled: Bool, isExtensionBased: Bool, extendedTypeHasEntry: Bool, raisingProvers: [Prover], isMockOnly: Bool)
		/// Members SafeDI records that mention the type prove it: `provers`, every one at `level`, the widest, among the
		/// members of declarations in `mentioningModuleName`, the module whose generated code mentions the type (`nil`
		/// when its name is unknown), or in the module of a declaration that receives the parameter.
		case signatures(type: TypeDescription, level: AccessLevel, provers: [Prover], mentioningModuleName: String?)
		/// Nothing proves the type.
		case unproven(type: TypeDescription)
	}

	/// A member that mentions a type, at the level it proves the type: its own level capped by the proof of the entry
	/// it belongs to, which `cap` says is the reason when it is narrower than the member's own.
	public struct Prover: Sendable {
		/// The entry the member is recorded on.
		public let carrier: TypeDescription
		public let member: MemberKind
		public let argumentLabels: [String]
		public let level: AccessLevel
		public let location: Dependency.DeclarationLocation?
		/// Why the member proves less than its own level, or `nil` when it proves its own level.
		public let cap: Cause?

		/// The member as a diagnostic names it: `Badge.init(theme:)`.
		public var name: String {
			let labels = argumentLabels.map { "\($0):" }.joined()
			return switch member {
			case .initializer:
				"`\(carrier.asSource).init(\(labels))`"
			case .instantiateMethod:
				"`\(carrier.asSource).instantiate(\(labels))`"
			case let .mockMethod(name):
				"`\(carrier.asSource).\(name)(\(labels))`"
			}
		}
	}

	/// The module whose code mentions a type, in which SafeDI resolves the type's name to its plain declaration.
	public struct MentioningModule: Sendable {
		/// A mention in the code SafeDI generates for `declaration`, in its module and in a file of its own beside it.
		public static func declaration(_ declaration: Instantiable) -> MentioningModule {
			MentioningModule(moduleName: declaration.moduleName, sourceFilePath: declaration.sourceFilePath, isRunsOwnModule: false)
		}

		/// A mention in the code SafeDI generates for the module named `moduleName`, or `nil` when its name is unknown,
		/// which is the run's own module when `isRunsOwnModule`.
		public static func generatedCode(ofModuleNamed moduleName: String?, isRunsOwnModule: Bool) -> MentioningModule {
			MentioningModule(moduleName: moduleName, sourceFilePath: nil, isRunsOwnModule: isRunsOwnModule)
		}

		let moduleName: String?
		let sourceFilePath: String?
		/// Whether the mention is in the run's own module, whose files hold the declarations of a module SafeDI knows no
		/// name of.
		let isRunsOwnModule: Bool
	}

	/// The kind of a member that proves.
	public enum MemberKind: Hashable, Sendable {
		case initializer
		case instantiateMethod
		case mockMethod(name: String)
	}

	/// The access of a seam parameter of type `type`: the narrowest proof among the types it names, a type with no entry
	/// proven by its plain declaration as `seam`'s module names it, and otherwise only by the members of declarations
	/// whose module is among `admittedModules` – the seam's own and those of the declarations that receive the
	/// parameter – `nil` naming a module SafeDI does not know, which matches only itself.
	/// - Parameter mentioningModule: Where the generated code that takes the parameter is: a seam's, or the public mocks
	///   of a module, in whose module SafeDI resolves the name of a type the parameter mentions.
	public func access(ofParameterTyped type: TypeDescription, mentionedFrom mentioningModule: MentioningModule, admittedModules: Set<String?>) -> ParameterAccess {
		var narrowest: (level: AccessLevel, cause: Cause)?
		for mentionedType in Self.mentionedTypes(in: type) {
			let cause = cause(of: mentionedType, mentionedFrom: mentioningModule, admittedModules: admittedModules)
			guard let cause else { continue }
			let level = cause.level
			if narrowest.map({ level < $0.level }) ?? (level < .public) {
				narrowest = (level, cause)
			}
		}
		return ParameterAccess(level: narrowest?.level ?? .public, cause: narrowest?.cause)
	}

	/// The entries whose proving members, read from `admittedModules` for a type with no entry and from every module
	/// for an entry, mention a type `type` names, and, for each such member of an entry that is not exact, the entries
	/// that mention that entry's type, transitively: what a type's proof depends on.
	public func declarationsProving(typesNamedBy type: TypeDescription, admittedModules: Set<String?>) -> Set<TypeDescription> {
		var proving = Set<TypeDescription>()
		var typesToVisit = Self.mentionedTypes(in: type)
		var visitedTypes = Set<TypeDescription>()
		while let visitedType = typesToVisit.popLast() {
			guard visitedTypes.insert(visitedType).inserted else { continue }
			let isEntry = kinds[visitedType] != nil
			for mention in mentions[visitedType] ?? [] where isEntry || admittedModules.contains(mention.moduleName) {
				proving.insert(mention.carrier)
				if let carrierKind = kinds[mention.carrier], carrierKind.exactProof == nil {
					typesToVisit.append(mention.carrier)
				}
			}
		}
		return proving
	}

	// MARK: Internal

	/// The types `type` names, in the order the compiler meets them, each a type the compiler checks against a
	/// member's access: a type and its generic arguments, and the types inside every optional, collection, tuple,
	/// closure, metatype, attribute, existential and composition. `Void` names nothing; a description the parser could
	/// not read is named as written.
	public static func mentionedTypes(in type: TypeDescription) -> [TypeDescription] {
		var mentioned = [TypeDescription]()
		var typesToVisit = [type]
		while let visited = typesToVisit.popLast() {
			var children = [TypeDescription]()
			switch visited {
			case .void:
				break
			case let .simple(_, generics), let .nested(_, _, generics):
				mentioned.append(visited)
				children = generics
			case .unknown:
				mentioned.append(visited)
			case let .composition(types):
				children = Array(types)
			case let .optional(wrapped),
			     let .implicitlyUnwrappedOptional(wrapped),
			     let .some(wrapped),
			     let .any(wrapped),
			     let .metatype(wrapped, _),
			     let .attributed(wrapped, _, _),
			     let .array(wrapped):
				children = [wrapped]
			case let .dictionary(key, value):
				children = [key, value]
			case let .tuple(elements):
				children = elements.map(\.typeDescription)
			case let .closure(arguments, _, _, returnType):
				children = arguments + [returnType]
			}
			typesToVisit.append(contentsOf: children.reversed())
		}
		return mentioned
	}

	// MARK: Private

	private let instantiables: [TypeDescription: Instantiable]
	private let entries: [TypeDescription: Instantiable]
	private let plainTypeDeclarations: PlainTypeDeclarations
	private let kinds: [TypeDescription: EntryKind]
	private let mentions: [TypeDescription: [Mention]]
	private let proofs: [TypeDescription: AccessLevel]

	private enum EntryKind: Sendable {
		/// Outside every extension: exact at its spelled chain.
		case typeDeclaration(level: AccessLevel)
		/// An extension-based declaration of a type whose plain declaration bounds it: exact.
		case plainDeclaration(ResolvedPlainTypeDeclarations)
		/// Inside an extension of a type whose own exact entry of the same module, or whose plain declaration, bounds
		/// it: exact.
		case exactInExtension(extendedType: TypeDescription, ownLevel: AccessLevel, extendedTypeProof: AccessLevel, extendedTypeIsPlain: Bool)
		/// Inside an extension that bounds it at `start`.
		case inExtension(extendedType: TypeDescription?, extension: AccessDeclaration, start: AccessLevel, extendedTypeHasEntry: Bool)
		/// An extension-based declaration, bounded at `start`.
		case extensionBased(start: AccessLevel)

		var exactProof: AccessLevel? {
			switch self {
			case let .typeDeclaration(level):
				level
			case let .plainDeclaration(resolved):
				resolved.level
			case let .exactInExtension(_, ownLevel, extendedTypeProof, _):
				ownLevel.capped(by: extendedTypeProof)
			case .inExtension, .extensionBased:
				nil
			}
		}

		var start: AccessLevel {
			switch self {
			case .typeDeclaration, .plainDeclaration, .exactInExtension:
				exactProof ?? .internal
			case let .inExtension(_, _, start, _), let .extensionBased(start):
				start
			}
		}

		/// Whether the entry's access is its type's plain declaration's.
		var isPlainDeclaration: Bool {
			switch self {
			case .plainDeclaration:
				true
			case .typeDeclaration, .exactInExtension, .inExtension, .extensionBased:
				false
			}
		}
	}

	private struct Mention: Sendable {
		let carrier: TypeDescription
		let member: MemberKind
		let argumentLabels: [String]
		/// The member's own level, before its carrier's proof caps it.
		let ownLevel: AccessLevel
		let moduleName: String?
		let location: Dependency.DeclarationLocation?
	}

	private struct MemberKey: Hashable {
		let carrier: TypeDescription
		let member: MemberKind
		let location: Dependency.DeclarationLocation?
	}

	private struct ProvingMember {
		let kind: MemberKind
		let initializer: Initializer
		let ownLevel: AccessLevel
		let moduleName: String?
		let location: Dependency.DeclarationLocation?
	}

	/// The two members of `instantiable` that prove: its construction initializer or `instantiate(…)` method, and its
	/// hand-written mock method, each without generic parameters, each at its own level.
	private static func provingMembers(of instantiable: Instantiable) -> [ProvingMember] {
		var members = [ProvingMember]()
		if let initializer = instantiable.initializer, !initializer.hasGenericParameter {
			members.append(ProvingMember(
				kind: instantiable.declarationType.isExtension ? .instantiateMethod : .initializer,
				initializer: initializer,
				ownLevel: normalized(AccessLevel.ownLevel(of: initializer.access, declaredIn: instantiable.access)),
				moduleName: instantiable.moduleName,
				location: initializer.access.declarationStartLocation ?? instantiable.declarationLocation,
			))
		}
		if let mockInitializer = instantiable.mockInitializer, !mockInitializer.hasGenericParameter {
			members.append(ProvingMember(
				kind: .mockMethod(name: instantiable.customMockName ?? InstantiableVisitor.mockMethodName),
				initializer: mockInitializer,
				ownLevel: normalized(AccessLevel.ownLevel(of: mockInitializer.access, declaredIn: instantiable.mockDeclarationAccess ?? instantiable.access)),
				moduleName: instantiable.mockDeclarationModuleName,
				location: mockInitializer.access.declarationStartLocation ?? instantiable.mockDeclarationLocation,
			))
		}
		return members
	}

	/// The level an extension bounds a declaration inside it, or an extension-based declaration, at: its spelled level
	/// when it spells one and extends a type declared at the top level, which the compiler then requires the type to
	/// reach, and `internal` otherwise.
	private static func extensionBound(_ extensionAccess: AccessDeclaration, extendedType: TypeDescription) -> AccessLevel {
		extensionAccess.spellsAccessModifier && extendedType.popNested == nil
			? normalized(extensionAccess.level.asDefaultOfExtensionMembers)
			: .internal
	}

	/// Whether two declarations are in one module: both name it, or both are in the run's own files.
	private static func isInSameModule(_ left: Instantiable, _ right: Instantiable, isOwnFile: (@Sendable (String) -> Bool)?) -> Bool {
		if let leftModuleName = left.moduleName, let rightModuleName = right.moduleName {
			leftModuleName == rightModuleName
		} else {
			// Without both names, only the run's own files are known to be one module's; a computation of another
			// module's seam, which passes no `isOwnFile`, has none.
			[left.sourceFilePath, right.sourceFilePath].allSatisfy { filePath in filePath.flatMap { isOwnFile?($0) } == true }
		}
	}

	/// The level a generated declaration can take: `open` counts as `public`, and `fileprivate` and `private` as
	/// `internal`, which generated code in another file can never name anyway.
	static func normalized(_ level: AccessLevel) -> AccessLevel {
		switch level {
		case .open, .public:
			.public
		case .package:
			.package
		case .internal, .fileprivate, .private:
			.internal
		}
	}

	/// The names of the standard types every module can name, which count as `public`: Swift's, Foundation's and
	/// Dispatch's, and SafeDI's wrappers. A name is admitted when it is a type of those modules that adopters pass as a
	/// dependency and nearly never declare themselves: a missing name narrows a tier, with a remedy, while a wrong one –
	/// a type of the module's own that shadows a standard one – is a compiler error on generated code.
	private static let allowlistedNames: Set<String> = [
		"Int", "Bool", "String", "Double", "Void", "Optional", "Array", "Dictionary", "Set",
		"Instantiator", "ErasedInstantiator", "SendableInstantiator", "SendableErasedInstantiator", "LazilyInstantiated", "SendableLazilyInstantiated",
		"Result", "Error", "Never", "Float", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
		"Character", "Substring", "AnyHashable", "Range", "ClosedRange", "Duration", "Clock", "ContinuousClock", "SuspendingClock",
		"Date", "URL", "UUID", "Decimal", "TimeInterval", "Data", "Calendar", "Locale", "TimeZone", "Bundle", "UserDefaults",
		"NotificationCenter", "FileManager", "JSONEncoder", "JSONDecoder", "URLSession", "URLRequest", "URLComponents",
		"OperationQueue", "ProcessInfo", "DateFormatter", "NumberFormatter", "ISO8601DateFormatter", "IndexPath", "IndexSet",
		"CharacterSet", "DispatchQueue",
	]

	private static func isAllowlisted(_ type: TypeDescription) -> Bool {
		switch type {
		case let .simple(name, _):
			allowlistedNames.contains(name)
		case let .nested(name, .simple(moduleName, []), _):
			(moduleName == "Swift" || moduleName == "Foundation" || moduleName == "Dispatch") && allowlistedNames.contains(name)
		case .any, .array, .attributed, .closure, .composition, .dictionary, .implicitlyUnwrappedOptional, .metatype, .nested, .optional, .some, .tuple, .unknown, .void:
			false
		}
	}

	/// How `type`, a type a parameter names, is proven, or `nil` for a standard type, which is `public`.
	private func cause(of type: TypeDescription, mentionedFrom mentioningModule: MentioningModule, admittedModules: Set<String?>) -> Cause? {
		if let kind = kinds[type] {
			let level = proofs[type] ?? .internal
			switch kind {
			case .typeDeclaration:
				return .ownDeclaration(type: type, level: level)
			case let .plainDeclaration(resolved):
				return resolved.cause(mentionedFrom: mentioningModule, isOwnFile: plainTypeDeclarations.isOwnFile)
			case let .exactInExtension(extendedType, ownLevel, extendedTypeProof, extendedTypeIsPlain):
				return .declarationInExtensionOfRecordedType(
					type: type,
					ownLevel: ownLevel,
					extendedType: extendedType,
					extendedTypeLevel: extendedTypeProof,
					spellsOwnLevel: entries[type]?.access.spellsAccessModifier ?? false,
					extendedTypeIsPlain: extendedTypeIsPlain,
				)
			case let .inExtension(extendedType, extensionAccess, _, extendedTypeHasEntry):
				return .declarationInExtension(
					type: type,
					level: level,
					extendedType: extendedType,
					extensionIsSpelled: extensionAccess.spellsAccessModifier,
					isExtensionBased: false,
					extendedTypeHasEntry: extendedTypeHasEntry,
					raisingProvers: shallowProvers(of: type, atLevel: level),
					isMockOnly: false,
				)
			case .extensionBased:
				return .declarationInExtension(
					type: type,
					level: level,
					extendedType: type,
					extensionIsSpelled: entries[type]?.access.spellsAccessModifier ?? false,
					isExtensionBased: true,
					extendedTypeHasEntry: true,
					raisingProvers: shallowProvers(of: type, atLevel: level),
					isMockOnly: entries[type]?.mockOnly ?? false,
				)
			}
		} else if Self.isAllowlisted(type) {
			return nil
		} else if let resolved = plainTypeDeclarations.declarations(named: type, mentionedFrom: mentioningModule) {
			// The compiler enforces the declaration's access, so no mention raises it.
			return resolved.cause(mentionedFrom: mentioningModule, isOwnFile: plainTypeDeclarations.isOwnFile)
		} else {
			let admittedMentions = (mentions[type] ?? []).filter { admittedModules.contains($0.moduleName) }
			guard let level = admittedMentions.map({ $0.ownLevel.capped(by: proofs[$0.carrier] ?? .internal) }).max() else {
				return .unproven(type: type)
			}
			return .signatures(type: type, level: level, provers: provers(of: type, atLevel: level, admittedModules: admittedModules), mentioningModuleName: mentioningModule.moduleName)
		}
	}

	/// The members that prove `type` at `level`, in source order, each with why it proves less than its own level;
	/// from every module when `admittedModules` is `nil`.
	private func provers(of type: TypeDescription, atLevel level: AccessLevel, admittedModules: Set<String?>?) -> [Prover] {
		var seen = Set<MemberKey>()
		return (mentions[type] ?? [])
			.filter { mention in admittedModules.map { $0.contains(mention.moduleName) } ?? true }
			.filter { $0.ownLevel.capped(by: proofs[$0.carrier] ?? .internal) == level }
			.filter { seen.insert(MemberKey(carrier: $0.carrier, member: $0.member, location: $0.location)).inserted }
			.sorted { left, right in
				let leftKey = (left.location?.filePath ?? "\u{10FFFF}", left.location?.line ?? 0, left.location?.column ?? 0)
				let rightKey = (right.location?.filePath ?? "\u{10FFFF}", right.location?.line ?? 0, right.location?.column ?? 0)
				return leftKey < rightKey || (leftKey == rightKey && left.carrier < right.carrier)
			}
			.map { mention in
				let carrierProof = proofs[mention.carrier] ?? .internal
				return Prover(
					carrier: mention.carrier,
					member: mention.member,
					argumentLabels: mention.argumentLabels,
					level: level,
					location: mention.location,
					// The carrier's own proof, when it caps the member: guarded against a cycle of carriers by the
					// member being narrower than its own level only where its carrier's proof is.
					cap: mention.ownLevel > carrierProof ? carrierCause(mention.carrier) : nil,
				)
			}
	}

	/// Why the entry of `carrier` is proven at its level, for a member it caps.
	private func carrierCause(_ carrier: TypeDescription) -> Cause? {
		guard let kind = kinds[carrier] else { return nil }
		let level = proofs[carrier] ?? .internal
		switch kind {
		case .typeDeclaration:
			return .ownDeclaration(type: carrier, level: level)
		case let .plainDeclaration(resolved):
			// A carrier's cap names the modules: no seam's module is at hand to tell them apart from.
			return .plainDeclaration(type: resolved.type, level: resolved.level, declarations: resolved.declarations, namesModules: true)
		case let .exactInExtension(extendedType, ownLevel, extendedTypeProof, extendedTypeIsPlain):
			return .declarationInExtensionOfRecordedType(type: carrier, ownLevel: ownLevel, extendedType: extendedType, extendedTypeLevel: extendedTypeProof, spellsOwnLevel: entries[carrier]?.access.spellsAccessModifier ?? false, extendedTypeIsPlain: extendedTypeIsPlain)
		case let .inExtension(extendedType, extensionAccess, _, extendedTypeHasEntry):
			return .declarationInExtension(type: carrier, level: level, extendedType: extendedType, extensionIsSpelled: extensionAccess.spellsAccessModifier, isExtensionBased: false, extendedTypeHasEntry: extendedTypeHasEntry, raisingProvers: shallowProvers(of: carrier, atLevel: level), isMockOnly: false)
		case .extensionBased:
			return .declarationInExtension(type: carrier, level: level, extendedType: carrier, extensionIsSpelled: entries[carrier]?.access.spellsAccessModifier ?? false, isExtensionBased: true, extendedTypeHasEntry: true, raisingProvers: shallowProvers(of: carrier, atLevel: level), isMockOnly: entries[carrier]?.mockOnly ?? false)
		}
	}

	/// The members that raise `type` to `level`, without their own caps: a diagnostic names them, not why they are
	/// capped in turn.
	private func shallowProvers(of type: TypeDescription, atLevel level: AccessLevel) -> [Prover] {
		guard level > (kinds[type]?.start ?? .internal) else { return [] }
		var seen = Set<MemberKey>()
		return (mentions[type] ?? [])
			.filter { $0.ownLevel.capped(by: proofs[$0.carrier] ?? .internal) == level }
			.filter { seen.insert(MemberKey(carrier: $0.carrier, member: $0.member, location: $0.location)).inserted }
			.sorted { left, right in
				let leftKey = (left.location?.filePath ?? "\u{10FFFF}", left.location?.line ?? 0, left.location?.column ?? 0)
				let rightKey = (right.location?.filePath ?? "\u{10FFFF}", right.location?.line ?? 0, right.location?.column ?? 0)
				return leftKey < rightKey || (leftKey == rightKey && left.carrier < right.carrier)
			}
			.map { Prover(carrier: $0.carrier, member: $0.member, argumentLabels: $0.argumentLabels, level: level, location: $0.location, cap: nil) }
	}
}

extension TypeAccessProof.Cause {
	/// The level the cause proves.
	public var level: AccessLevel {
		switch self {
		case let .ownDeclaration(_, level),
		     let .plainDeclaration(_, level, _, _),
		     let .declarationInExtension(_, level, _, _, _, _, _, _),
		     let .signatures(_, level, _, _):
			level
		case let .declarationInExtensionOfRecordedType(_, ownLevel, _, extendedTypeLevel, _, _):
			ownLevel.capped(by: extendedTypeLevel)
		case .unproven:
			.internal
		}
	}
}

// MARK: - TypeAccessProof.PlainTypeDeclarations

extension TypeAccessProof {
	/// The plain type declarations the proof reads, by the type each declares, and how a mention of a type's name
	/// resolves to them.
	fileprivate struct PlainTypeDeclarations: Sendable {
		/// - Parameters:
		///   - plainTypeDeclarations: The declarations, each with its module.
		///   - entryTypes: The types the proof's entries declare.
		///   - moduleNames: The names of the modules the proof's entries are declared in, which, with those of the
		///     declarations, a mention can spell before a type's name.
		///   - isOwnFile: Whether a file is one of the run's own files.
		init(_ plainTypeDeclarations: [PlainTypeDeclaration], entryTypes: Set<TypeDescription>, moduleNames: Set<String>, isOwnFile: (@Sendable (String) -> Bool)?) {
			var declarationsByType = [TypeDescription: [PlainTypeDeclaration]]()
			// A declaration no other file can name is never what a mention in another file names.
			for declaration in plainTypeDeclarations.sortedByDeclaration() where declaration.isVisibleOutsideItsFile {
				declarationsByType[declaration.typeDescription, default: []].append(declaration)
			}
			self.declarationsByType = declarationsByType
			self.entryTypes = entryTypes
			self.moduleNames = moduleNames.union(plainTypeDeclarations.compactMap(\.moduleName))
			self.isOwnFile = isOwnFile
		}

		let isOwnFile: (@Sendable (String) -> Bool)?

		/// The plain declarations a mention of `type` in a declaration of the module of `mentioning` names, or `nil`
		/// when SafeDI records none that module can name. A mention spelled with a module's name before the type's
		/// (`Core.Theme`), where the view holds a module of that name and no type of it, names that module's
		/// declarations of the rest. Otherwise the mentioning module's own declaration is what Swift resolves the name to,
		/// and without one, a declaration another module declares `package` or wider: the only kind another module can
		/// name. Generic arguments name nothing a declaration records.
		func declarations(named type: TypeDescription, mentionedFrom mentioningModule: MentioningModule) -> ResolvedPlainTypeDeclarations? {
			guard let type = type.withoutGenericArguments else { return nil }
			let candidates: [PlainTypeDeclaration]
			if let moduleName = type.outermostTypeName,
			   moduleNames.contains(moduleName),
			   !entryTypes.contains(.simple(name: moduleName)),
			   declarationsByType[.simple(name: moduleName)] == nil,
			   let typeInModule = type.droppingOutermostType
			{
				candidates = (declarationsByType[typeInModule] ?? []).filter { $0.moduleName == moduleName }
			} else {
				let declarations = declarationsByType[type] ?? []
				let mentioningModuleDeclarations = declarations.filter { mentioningModule.declares($0, isOwnFile: isOwnFile) }
				candidates = mentioningModuleDeclarations.isEmpty
					? declarations.filter { $0.moduleName != nil && TypeAccessProof.normalized($0.effectiveAccessLevel) >= .package }
					: mentioningModuleDeclarations
			}
			guard let level = candidates.map({ TypeAccessProof.normalized($0.effectiveAccessLevel) }).min() else { return nil }
			return ResolvedPlainTypeDeclarations(type: candidates.first?.typeDescription ?? type, level: level, declarations: candidates)
		}

		private let declarationsByType: [TypeDescription: [PlainTypeDeclaration]]
		private let entryTypes: Set<TypeDescription>
		private let moduleNames: Set<String>
	}

	/// The plain declarations a mention of a type names: `level`, the narrowest of their levels, proves the type.
	fileprivate struct ResolvedPlainTypeDeclarations: Sendable {
		let type: TypeDescription
		let level: AccessLevel
		/// In the order of their files, and within a file in source order.
		let declarations: [PlainTypeDeclaration]

		/// The cause, as a diagnostic about a mention in `mentioning`'s module explains it.
		func cause(mentionedFrom mentioningModule: MentioningModule, isOwnFile: (@Sendable (String) -> Bool)?) -> Cause {
			.plainDeclaration(
				type: type,
				level: level,
				declarations: declarations,
				namesModules: !declarations.allSatisfy { mentioningModule.declares($0, isOwnFile: isOwnFile) },
			)
		}
	}
}

extension TypeAccessProof.MentioningModule {
	/// Whether `declaration` is in this module: both name it, or, without both names, the declaration is in one of the
	/// run's own files and so is the mention.
	fileprivate func declares(_ declaration: PlainTypeDeclaration, isOwnFile: (@Sendable (String) -> Bool)?) -> Bool {
		if let moduleName, let declarationModuleName = declaration.moduleName {
			moduleName == declarationModuleName
		} else {
			declaration.sourceFilePath.flatMap { isOwnFile?($0) } == true
				&& (isRunsOwnModule || sourceFilePath.flatMap { isOwnFile?($0) } == true)
		}
	}
}
