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

import SwiftSyntax

/// A name that SafeDI’s generated code introduces into a scope where it also binds, or refers to, the names it is
/// given: property labels, `fulfilledByDependencyNamed:` names, `instantiate(…)` parameter names, and the argument
/// labels a generated `mock()` takes. A name SafeDI is given that is reserved would collide with the generated one,
/// so the `@Instantiable` macro rejects it.
///
/// Generated code spells each of these names through this type, so a name cannot be generated without being reserved.
public enum ReservedName: Hashable, Sendable {
	/// A name that begins with `builderFunctionNamePrefix`, the prefix of each builder function a generated `init()`
	/// or `mock()` declares (`__safeDI_<label>`, next to the `let <label>` it builds), of the locals a `@Sendable`
	/// builder function captures, of the local a `mock()` reads each `@Sendable` autoclosure parameter into, of the
	/// `__safeDI_<Seam>_<hash>` enum a seam's module generates beside the seam's initializers, and of the argument
	/// labels of the initializer of a seam that only generated code calls (`seamGeneratedOnlyArgumentLabel(of:)`).
	case builderFunctionName
	/// `mockOverridesParameterName`, the parameter through which a generated `mock()` takes its overrides. A mock
	/// parameter of the same name redeclares it, and a binding of the same name in the mock's body hides it from the
	/// reads of the overrides that follow.
	case mockOverridesParameter
	/// `configurationBuilderPropertyName`, the property and initializer parameter of each generated
	/// `SafeDIMockConfiguration` that overrides how its type is built, beside one property for each dependency the
	/// configured type instantiates and each of its default-valued parameters, which a name of the same spelling
	/// redeclares.
	case configurationBuilderProperty
	/// The name of a type that generated code constructs by name (`Instantiator<T>(…)`). A binding of the same name
	/// hides the type from the code generated in its scope.
	case constructedType(String)

	// MARK: Initialization

	/// The reserved name `name` collides with, or `nil` when it collides with none. Backticks only quote a name, so
	/// `name` is read without them: `` `__safeDI_editor` `` and `__safeDI_editor` name one property.
	public init?(reserving name: String) {
		let name = name.spelledWithoutBackticks
		if name.utf8.starts(with: Self.builderFunctionNamePrefix.utf8) {
			self = .builderFunctionName
		} else if name == Self.mockOverridesParameterName {
			self = .mockOverridesParameter
		} else if name == Self.configurationBuilderPropertyName {
			self = .configurationBuilderProperty
		} else if Self.constructedTypeNames.contains(name) {
			self = .constructedType(name)
		} else {
			return nil
		}
	}

	// MARK: Public

	/// The prefix of the name of each builder function generated code declares. The prefix keeps these names out of
	/// the namespace of the names SafeDI is given.
	public static let builderFunctionNamePrefix = "__safeDI_"
	/// The name of the parameter through which a generated `mock()` takes its overrides. Callers of a generated
	/// `mock()` spell it, so it never changes.
	public static let mockOverridesParameterName = "safeDIOverrides"
	/// The name of the argument through which a function on a cycle of a generated mock's tree takes its configuration
	/// with the places the functions above it entered, and of the value `mock()` binds with none entered.
	public static let mockEnteredPlacesParameterName = "__safeDI_entered"
	/// The name of the property, and initializer parameter, of each generated `SafeDIMockConfiguration` that
	/// overrides how its type is built, and of the binding of that override in a construction expression.
	public static let configurationBuilderPropertyName = "safeDIBuilder"

	/// `name`, which must begin with `builderFunctionNamePrefix`, without the prefix.
	public static func removingBuilderFunctionNamePrefix(from name: String) -> String {
		String(String.UnicodeScalarView(name.unicodeScalars.dropFirst(builderFunctionNamePrefix.unicodeScalars.count)))
	}

	/// The prefix among `reservedTypeNamePrefixes` that `typeName`, spelled without backticks, begins with, or `nil` when
	/// it begins with none. No prefix begins another, so a name begins with one at most.
	public static func reservedTypeNamePrefix(of typeName: String) -> String? {
		reservedTypeNamePrefixes.first { typeName.utf8.starts(with: $0.utf8) }
	}

	/// The error at a type named `typeName`, or at a spelling of it, which begins with `prefix`, one of
	/// `reservedTypeNamePrefixes`. The `@Instantiable` macro and SafeDITool both report it, so its wording is spelled once.
	public static func reservedTypeNameMessage(typeName: String, prefix: String) -> String {
		"The type name `\(typeName)` begins with `\(prefix)`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `\(prefix)`."
	}

	// MARK: Internal

	/// The prefix of the name of a seam's plain root enum, `SafeDIScope_<Stem>`, which the seam's module declares in an
	/// extension of the seam, and of the payload structs it declares there.
	static let seamScopeTypeNamePrefix = "SafeDIScope_"

	/// The prefix of the name of a seam's `@Sendable` root enum, `SafeDISendableScope_<Stem>`.
	static let sendableSeamScopeTypeNamePrefix = "SafeDISendableScope_"

	/// The prefix of the name of a seam's plain root enum whose levels are carriers, `SafeDICarrierScope_<Stem>`, which no
	/// generated code spells: the seam declares a carrier for each of its levels (`seamCarrier(ofEnum:)`).
	static let seamCarrierScopeTypeNamePrefix = "SafeDICarrierScope_"

	/// The prefix of the name of a seam's `@Sendable` root enum whose levels are carriers, `SafeDISendableCarrierScope_<Stem>`.
	static let sendableSeamCarrierScopeTypeNamePrefix = "SafeDISendableCarrierScope_"

	/// The prefix of the name of a public mock's plain root enum, `SafeDIMockScope_<Stem>`, which the mocked type's module
	/// declares in an extension of the mocked type.
	static let publicMockScopeTypeNamePrefix = "SafeDIMockScope_"

	/// The prefix of the name of a public mock's `@Sendable` root enum, `SafeDISendableMockScope_<Stem>`.
	static let sendablePublicMockScopeTypeNamePrefix = "SafeDISendableMockScope_"

	/// The prefixes of the names of the types SafeDI's generated code declares beside the types a person declares, each
	/// reserved whole so that no generated name can collide with a person's type: a seam's root enums and a public
	/// mock's, and `builderFunctionNamePrefix`, the prefix of the builder struct `__safeDI_Builder` a seam's enums declare,
	/// of the guard enums a seam's and a public mock's module declares, and of a public mock's module-level configuration.
	/// Not every name with one of these prefixes collides with a name SafeDI generates, and which ones do changes with the
	/// generator, so each prefix is reserved whole.
	static let reservedTypeNamePrefixes = [
		seamScopeTypeNamePrefix,
		sendableSeamScopeTypeNamePrefix,
		publicMockScopeTypeNamePrefix,
		sendablePublicMockScopeTypeNamePrefix,
		builderFunctionNamePrefix,
	]

	/// The argument label under which the initializer of a seam that only generated code calls takes the parameter or
	/// builder labeled `label`, which is in `spelledAsIdentifier` spelling. A person's call uses the readable label on the
	/// plain initializer beside it, which a module generates when its configuration sets
	/// `generatePlainDependencyTreeInitializers`, and no name SafeDI is given begins with this prefix, so the two
	/// initializers never share a label.
	static func seamGeneratedOnlyArgumentLabel(of label: String) -> String {
		"\(builderFunctionNamePrefix)\(label)".spelledAsJoinedIdentifier
	}

	/// The name of the function a scope declares beside the builder function named `functionName` of a member of a loop of
	/// builders whose function takes parameters a lazy cycle needs: the function of no such parameters that every wrapper of
	/// the member hands, which passes them (see `ScopeGenerator.ReceivedBuilderLoops`).
	static func receivedBuilderFunctionName(of functionName: String) -> String {
		"\(functionName)_received".spelledAsJoinedIdentifier
	}

	/// The name of the parameter under which a mock's function of a member of a loop of builders takes the overrides of the
	/// loop's level, a node of the type `typeIdentifier` names, or `mock()` itself, whose overrides every member's
	/// configuration is a field of (`NodeRecords.mockLoopLevelArgument(of:in:levels:slots:)`).
	static func loopLevelConfigurationParameterName(ofTypeIdentifier typeIdentifier: String) -> String {
		"\(builderFunctionNamePrefix)\(typeIdentifier)_loopConfiguration".spelledAsJoinedIdentifier
	}

	/// The name of the box a scope binds the levels and payloads of a loop of builders in, beside the builder function
	/// named `functionName` of the loop's first member (see `ScopeGenerator.boxedLoops`).
	static func loopLevelsName(of functionName: String) -> String {
		"\(functionName)_loopLevels".spelledAsJoinedIdentifier
	}

	/// The start of the name of each private final class a seam declares beside its initializers when its tree holds a
	/// loop's levels in one box, which the hash of what the class holds follows (`ScopeGenerator.LoopLevelsType`).
	static let loopLevelsTypeName = "\(builderFunctionNamePrefix)LoopLevels"
	/// The name of the enum a generated `mock()` whose tree holds a cycle declares: the places the functions on a path
	/// have entered, nearest first (`MockEnteredSlot.mockEnteredPlacesDeclaration`).
	static let mockEnteredPlacesTypeName = "\(builderFunctionNamePrefix)Places"
	/// The name of the struct such a `mock()` declares beside it, generic over a configuration: what a function on a
	/// cycle is handed, its configuration with the places entered.
	static let mockEnteredTypeName = "\(builderFunctionNamePrefix)Entered"
	/// The member of that struct that holds the configuration.
	static let mockEnteredConfigurationMemberName = "configuration"
	/// The function of that struct a call of a function a path can close on hands the function its value with: the place
	/// entered before under the call's slot where there is one, and otherwise a new place.
	static let mockEnteringFunctionName = "entering"
	/// The label under which that function is told to enter a new place with the nearest configuration of its type.
	static let mockEnteringNearestOfTypeArgumentLabel = "nearestOfType"
	/// The function a call of a function on no cycle hands the function its value with, where its configuration is the
	/// nearest of its type for a place entered beneath it.
	static let mockEnteringNearestFunctionName = "enteringNearest"
	/// The function a call of a function that only hands the places on hands the function its value with.
	static let mockPassingFunctionName = "passing"

	/// The name of the parameter through which a function building a hole held in an instantiator takes the value the
	/// instantiator forwards.
	static let forwardedValueParameterName = "\(builderFunctionNamePrefix)forwarded"

	/// The name of the static function in a type's extension that a public mock builds the type with when it is built with
	/// its hand-written mock, and of the function of a public mock that only generated code calls, which takes builder
	/// structs where `mock()` takes plain builders. The two overloads differ by the construction function's required
	/// `safeDIBuilder:` label.
	static let publicMockFunctionName = "\(builderFunctionNamePrefix)mock"

	/// The name of the struct a generated mock declares for the overrides of its tree, which its `mock()` takes as
	/// `mockOverridesParameterName`.
	static let mockOverridesTypeName = "SafeDIOverrides"

	/// The name of the struct a seam's scope type declares for each of its levels, generic over what the builder returns:
	/// one stored function per member, each called where the seam binds that level.
	static let builderStructTypeName = "\(builderFunctionNamePrefix)Builder"

	/// The type of a level of a seam's or a public mock's scope enum `enumType`, which hands its members to the generated
	/// code that fills the level's places, over `builtType`: for a seam, the carrier of the level, a final class declared
	/// in the seam's extension beside its initializers; for a public mock, the enum's builder struct.
	static func levelType(ofEnum enumType: TypeDescription, built builtType: TypeDescription) -> TypeDescription {
		guard let carrier = seamCarrier(ofEnum: enumType) else {
			return .nested(name: builderStructTypeName, parentType: enumType, generics: [builtType])
		}
		if let seamType = carrier.seamType {
			return .nested(name: carrier.name, parentType: seamType, generics: [builtType])
		} else {
			return .simple(name: carrier.name, generics: [builtType])
		}
	}

	/// Whether `name` names the type of a level `levelType(ofEnum:built:)` spells: a builder struct, or a seam's carrier.
	static func namesLevelType(_ name: String) -> Bool {
		name == builderStructTypeName || (name.hasPrefix(builderFunctionNamePrefix) && (name.hasSuffix("Carrier") || name.contains("Carrier_")))
	}

	/// The name of the carrier of a seam's level whose scope enum is `enumType`, and the seam's type where `enumType` is
	/// spelled qualified by it (`seamCarrier(ofEnumNamed:nestedIn:)`); `nil` where `enumType` is no seam's scope enum.
	static func seamCarrier(ofEnum enumType: TypeDescription) -> (name: String, seamType: TypeDescription?, isSendable: Bool, describedTypeName: String?)? {
		enumType.simpleNameAndGenerics.flatMap { seamCarrier(ofEnumNamed: $0.name, nestedIn: $0.parentType) }
	}

	/// The name of the carrier of a seam's level whose scope enum is named `name`, nested in `parentType`, and the seam's
	/// type where the enum is spelled qualified by it: `__safeDI_<Stem>Carrier` for a root enum `SafeDIScope_<Stem>`,
	/// `…SendableCarrier` for `SafeDISendableScope_<Stem>`, followed by `_<enum>` for an enum nested in the root. `nil`
	/// where the enum is no seam's scope enum. A scope enum is nominal, so it is read by its name and the type it is nested
	/// in, never by the shape of a type spelling.
	static func seamCarrier(ofEnumNamed name: String, nestedIn parentType: TypeDescription?) -> (name: String, seamType: TypeDescription?, isSendable: Bool, describedTypeName: String?)? {
		let rootName: String
		var nestedName: String?
		let seamType: TypeDescription?
		if let parent = parentType?.simpleNameAndGenerics, parent.name.hasPrefix(seamCarrierScopeTypeNamePrefix) || parent.name.hasPrefix(sendableSeamCarrierScopeTypeNamePrefix) {
			rootName = parent.name
			nestedName = name
			seamType = parent.parentType
		} else {
			rootName = name
			seamType = parentType
		}
		let stem: String
		let isSendable: Bool
		if rootName.hasPrefix(sendableSeamCarrierScopeTypeNamePrefix) {
			stem = String(rootName.dropFirst(sendableSeamCarrierScopeTypeNamePrefix.count))
			isSendable = true
		} else if rootName.hasPrefix(seamCarrierScopeTypeNamePrefix) {
			stem = String(rootName.dropFirst(seamCarrierScopeTypeNamePrefix.count))
			isSendable = false
		} else {
			return nil
		}
		let describedTypeName = nestedName.map { $0.hasSuffix("_Scope") ? String($0.dropLast("_Scope".count)) : $0 }
		return ("\(builderFunctionNamePrefix)\(stem)\(isSendable ? "Sendable" : "")Carrier\(describedTypeName.map { "_\($0)" } ?? "")", seamType, isSendable, describedTypeName)
	}

	/// The name of a builder struct's generic parameter: the type its builder returns, prefixed so that no type a struct's
	/// member spells can be hidden by it.
	static let builderStructGenericParameterName = "\(builderFunctionNamePrefix)Built"

	/// The argument label of the initializer of a level's builder struct that wraps a builder that takes nothing, which a
	/// seam's readable initializer passes the builder a person wrote to.
	static let noScopeArgumentLabel = "\(builderFunctionNamePrefix)noScope"
	/// The builder generated code passes, and a mock defaults to, for places instantiated only if available that nothing
	/// fulfills: it returns `nil`, the value production binds there.
	static let nilBuilderSource = "{ nil }"

	/// The parameter name under which that initializer takes the builder: apart from every property label, since a
	/// member can be named `builder`.
	static let noScopeParameterName = "\(builderFunctionNamePrefix)builder"

	/// The name under which a generated initializer reads the parameter that sets a member labeled `self`
	/// (`String.spelledAsAssigningParameterName`): a parameter named `self` would hide the instance the initializer assigns
	/// to.
	static let selfParameterName = "\(builderFunctionNamePrefix)self"

	/// The name of the final class each generated configuration (`SafeDIOverrides`, `SafeDIMockConfiguration`, a public
	/// mock's module-level configuration) keeps its fields in, so that a copy of the configuration is one reference.
	static let configurationStorageTypeName = "\(builderFunctionNamePrefix)Storage"

	/// The name of the property through which a generated configuration holds its `configurationStorageTypeName`.
	static let configurationStoragePropertyName = "\(builderFunctionNamePrefix)storage"

	/// The names of the types generated code constructs by name: the wrapper of each kind of property that is not
	/// a constant, which generated code builds with its builder function.
	static let constructedTypeNames = Set(Property.PropertyType.allCases.compactMap(\.wrapperTypeName))
}

// MARK: - ReservedTypeNameDeclaration

/// A declaration of a type whose name begins with one of `ReservedName.reservedTypeNamePrefixes` that the `@Instantiable`
/// macro does not see: one that is neither `@Instantiable` itself nor declared inside an `@Instantiable` type or
/// extension, at any depth. SafeDITool reports each one in the module's own files, as the macro reports those it sees.
public struct ReservedTypeNameDeclaration: Codable, Hashable, Sendable {
	public init(typeName: String, prefix: String, location: Dependency.DeclarationLocation?) {
		self.typeName = typeName
		self.prefix = prefix
		self.location = location
	}

	/// The declared type's own name, spelled without backticks.
	public let typeName: String
	/// The reserved prefix `typeName` begins with.
	public let prefix: String
	/// Where the declaration's name is written.
	public let location: Dependency.DeclarationLocation?

	/// The record of the type `name` declares, when its name begins with a reserved prefix.
	/// - Parameter sourceLocationConverter: A converter for the tree `name` is in, with which the record names where the
	///   name is written.
	static func declaredBy(_ name: TokenSyntax, sourceLocationConverter: SourceLocationConverter?) -> ReservedTypeNameDeclaration? {
		let typeName = name.text.spelledWithoutBackticks
		return ReservedName.reservedTypeNamePrefix(of: typeName).map { prefix in
			ReservedTypeNameDeclaration(
				typeName: typeName,
				prefix: prefix,
				location: sourceLocationConverter?.declarationLocation(for: name.positionAfterSkippingLeadingTrivia),
			)
		}
	}

	/// The records of the type aliases and associated types among the members of `protocolDeclaration`, in every clause of
	/// each `#if` block among them, in source order: a protocol's body declares no other type.
	static func declaredAmongMembers(of protocolDeclaration: ProtocolDeclSyntax, sourceLocationConverter: SourceLocationConverter?) -> [ReservedTypeNameDeclaration] {
		func typeNames(in members: MemberBlockItemListSyntax) -> [TokenSyntax] {
			members.flatMap { member -> [TokenSyntax] in
				if let typeAlias = TypeAliasDeclSyntax(member.decl) {
					[typeAlias.name]
				} else if let associatedType = AssociatedTypeDeclSyntax(member.decl) {
					[associatedType.name]
				} else if let ifConfigDeclaration = IfConfigDeclSyntax(member.decl) {
					ifConfigDeclaration.clauses.flatMap { clause in
						MemberBlockItemListSyntax(clause.elements).map(typeNames(in:)) ?? []
					}
				} else {
					[]
				}
			}
		}
		return typeNames(in: protocolDeclaration.memberBlock.members).compactMap {
			declaredBy($0, sourceLocationConverter: sourceLocationConverter)
		}
	}
}
