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

import Foundation
import SwiftParser
import SwiftSyntax

/// Reads the generated mock code of two outcomes of the tool, each read with SwiftParser, to say which of the two known
/// reasons a difference in one of their files shows. Each reason states what the generator does and accepts only what
/// that can produce; where the two files cannot show it exactly, the difference is reported. The first outcome is in the
/// graph's own naming, and the other's names are restored from the renaming that separates the two.
///
/// - The order of a mock's parameters and fields: `Property.precedesInMockOrder` sorts a mock's received parameters and
///   its overrides of what it receives only if available by label, then by kind, then by type; a mock's forwarded
///   parameters and the wrappers it makes of lazily instantiated instances are sorted too, and a public mock sorts its
///   optional parameters by name. So a renaming that reverses labels reorders those lists, and one that changes the
///   order of type names reorders elements of one label and kind. Only they move, each element whole, among the places
///   they hold: the rest of a list follows declarations, so a value that moved to another scope or to another label still
///   differs, as does a child, a default or the builder that always comes last. A list that moved must be in that order
///   in each outcome's own naming, which rules out a permutation no reversal makes and labels the renaming leaves alone.
///   A mock's own parameters are its forwarded ones, its received ones and the ones it cannot build, in that order, each
///   group sorted on its own but for the last, and their code does not tell the groups apart, so such a list is held to
///   that order within each stretch that holds the same elements in both outcomes.
/// - Which configuration fields exist: `DependencyTreeGenerator.computeCycleEdges` finds the back-edges of the graph's
///   lazy cycles by a search from each concrete type in the order of their names, and a back-edge's field is left out of
///   its owner's configuration struct. A field present in one outcome and absent from the other is such a field when its
///   owner on the other side has neither its label nor its type, when the search's path back from its type to its owner
///   is among the fields of the outcome that lacks it, and when the renaming changes the order of two of the types that
///   decide where the search enters the cycle: its owner, its type, every type a configuration shows to reach them, and
///   every type no generated configuration names, since one of those can reach them unseen. A reversal renames only
///   `<prefix>Root|AnyT|T|Missing|Cycle<digit>`, and a move gives each of a graph's names one of two letters, so two names of
///   one letter keep their order. The reads of a dropped field go with it, each only as the path of the node at its place
///   in the tree. A mock laid out from node records writes one function per node, which is handed its configuration with
///   the places entered, so no node’s place in the tree shows there: the one read of a dropped field is the field of the
///   handed configuration a function hands on as it enters a child’s place (`__safeDI_entered.configuration.<label>`,
///   handed to `__safeDI_entered.entering`), where the outcome that lacks the field hands a new configuration of the
///   field’s type (`NodeRecords.mockArgumentsHanded(to:labeled:by:in:slots:)`), and it reads as that. In a mock that
///   may leave a place out, that call enters the place left out (`__safeDI_entered.leavingOut.entering`), where the
///   outcome with the field hands it only where the places are not left out, or hands the field of the overrides a
///   function without places entered takes, and that call reads as the other's (`leftOutEntryOfDroppedField(_:)`). A dropped field
///   is the field of an edge that closes a cycle, so the child it configures is on that cycle and its place is entered
///   by name: a call that enters the nearest place of a type, or only hands the places on, hands no dropped field, and
///   such a read there is not forgiven.
struct GraphFuzzerMockDifference: Sendable {
	enum Reason: Equatable, Sendable {
		case orderOfParametersAndFields
		case presenceOfConfigurationFields
	}

	/// - Parameters:
	///   - renaming: The renaming that separates the two outcomes, or `nil` when none does.
	///   - instantiableTypeNames: The concrete types the graph declares, which the generated code does not all name.
	init(generatedFiles: [String: String], otherGeneratedFiles: [String: String], renaming: GraphFuzzerRenaming?, instantiableTypeNames: Set<String>) {
		fields = Self.configurationFields(in: generatedFiles)
		otherFields = Self.configurationFields(in: otherGeneratedFiles)
		self.renaming = renaming
		if let renaming, renaming.changesOrderOfTypeNames {
			let typesReachingType = Self.typesReachingEachType(through: [fields, otherFields])
			let configuredTypes = Set([fields, otherFields].flatMap(\.keys).compactMap(Self.concreteTypeName(ofConfigurationNamed:)))
			let typesNoFieldNames = instantiableTypeNames.subtracting(configuredTypes)
			droppedFields = Self.droppedFields(of: fields, absentFrom: otherFields, under: renaming, typesReachingType: typesReachingType, typesNoFieldNames: typesNoFieldNames)
			otherDroppedFields = Self.droppedFields(of: otherFields, absentFrom: fields, under: renaming, typesReachingType: typesReachingType, typesNoFieldNames: typesNoFieldNames)
		} else {
			droppedFields = []
			otherDroppedFields = []
		}
	}

	/// The reasons the difference between `code` and `otherCode`, a file of the first and of the other outcome, shows:
	/// each one it shows when applying exactly those explains every difference, or nothing when anything else differs too
	/// (the two then differ by more than the known reasons), when the two differ in nothing these read, or when either
	/// does not parse. A file's extensions may also have moved among their places, which these reasons do not name.
	func reasons(forDifferenceBetween code: String, and otherCode: String) -> [Reason] {
		let file = Parser.parse(source: code)
		let otherFile = Parser.parse(source: otherCode)
		guard !file.hasError, !otherFile.hasError else { return [] }

		func form(of file: SourceFileSyntax, in fields: Fields, dropping droppedFields: Set<ConfigurationField>, sorted: Bool, recordingTo movableLists: MovableLists = MovableLists()) -> [UInt8] {
			let collector = MockMethodCollector(viewMode: .sourceAccurate)
			collector.walk(file)
			var rendering = Rendering(fields: fields, droppedFields: droppedFields, mockMethods: collector, sortsParametersAndFields: sorted, breaksLabelTiesByText: renaming?.changesOrderOfTypeNames == true, movableLists: movableLists)
			rendering.functionsEnteredOnlyWithNewConfigurations = rendering.functionsEnteredOnlyWithNewConfigurations(in: file)
			return GraphFuzzerExtensionOrder.sortingExtensionsWithinTheirPlaces(in: rendering.text(of: Syntax(file), in: Rendering.Scope()))
		}
		let sortsParametersAndFields = renaming.map { $0.reversesLabels || $0.changesOrderOfTypeNames } ?? false
		let unchanged = form(of: file, in: fields, dropping: [], sorted: false)
		let otherUnchanged = form(of: otherFile, in: otherFields, dropping: [], sorted: false)
		let withoutFields = form(of: file, in: fields, dropping: droppedFields, sorted: false)
		let otherWithoutFields = form(of: otherFile, in: otherFields, dropping: otherDroppedFields, sorted: false)
		let movableLists = MovableLists()
		let otherMovableLists = MovableLists()
		let withoutFieldsSorted = form(of: file, in: fields, dropping: droppedFields, sorted: sortsParametersAndFields, recordingTo: movableLists)
		let otherWithoutFieldsSorted = form(of: otherFile, in: otherFields, dropping: otherDroppedFields, sorted: sortsParametersAndFields, recordingTo: otherMovableLists)

		guard withoutFieldsSorted == otherWithoutFieldsSorted, listsThatMovedAreInLabelOrder(movableLists, otherMovableLists) else { return [] }
		var reasons = [Reason]()
		if withoutFields != otherWithoutFields {
			reasons.append(.orderOfParametersAndFields)
		}
		if unchanged != withoutFields || otherUnchanged != otherWithoutFields {
			reasons.append(.presenceOfConfigurationFields)
		}
		return reasons
	}

	/// A stored field of a configuration struct, which holds the overrides of a child of a mock's tree.
	fileprivate struct ConfigurationField: Hashable, Sendable {
		let owner: String
		let label: String
		let type: String
	}

	/// Each configuration struct's fields by label, by the struct's name as a field's type spells it.
	fileprivate typealias Fields = [String: [String: ConfigurationField]]

	private let fields: Fields
	private let otherFields: Fields
	private let droppedFields: Set<ConfigurationField>
	private let otherDroppedFields: Set<ConfigurationField>
	private let renaming: GraphFuzzerRenaming?

	/// Whether every list that holds its movable elements in another order in the two outcomes is in label order in each
	/// outcome's own naming. A mock's own parameters are forwarded ones, received ones and the ones it cannot build, in that
	/// order, which their code does not tell apart: such a list is held to that within each stretch that holds the same
	/// elements in both outcomes.
	private func listsThatMovedAreInLabelOrder(_ lists: MovableLists, _ otherLists: MovableLists) -> Bool {
		guard Set(lists.namesByList.keys) == Set(otherLists.namesByList.keys) else { return false }
		return lists.namesByList.allSatisfy { list, listsOfNames in
			let otherListsOfNames = otherLists.namesByList[list, default: []]
			guard listsOfNames.count == otherListsOfNames.count else { return false }
			return zip(listsOfNames, otherListsOfNames).allSatisfy { names, otherNames in
				guard names != otherNames else { return true }
				guard names.count == otherNames.count else { return false }
				let stretches = list.kind == .mockParameters ? Self.stretchesHoldingTheSameElements(names, otherNames) : [names.indices]
				return stretches.allSatisfy { stretch in
					names[stretch] == otherNames[stretch] || (isInLabelOrder(names[stretch], renamed: false) && isInLabelOrder(otherNames[stretch], renamed: true))
				}
			}
		}
	}

	/// The shortest consecutive stretches of `names` and `otherNames` that each hold the same elements in both.
	private static func stretchesHoldingTheSameElements(_ names: [String], _ otherNames: [String]) -> [Range<Int>] {
		var stretches = [Range<Int>]()
		var start = 0
		for end in names.indices where Set(names[start...end]) == Set(otherNames[start...end]) {
			stretches.append(start..<(end + 1))
			start = end + 1
		}
		return stretches
	}

	/// Whether `names`, restored from the renaming when `renamed` is true, are in the order `Property.precedesInMockOrder`
	/// gives them in their own naming: by label, which a name given apart from another's with that label starts with up to
	/// its first underscore, and among those of one label and kind by the type the rest of the name spells.
	private func isInLabelOrder(_ names: ArraySlice<String>, renamed: Bool) -> Bool {
		zip(names, names.dropFirst()).allSatisfy { name, nextName in
			let spelled = renamed ? spellingInItsOwnNaming(name) : name
			let nextSpelled = renamed ? spellingInItsOwnNaming(nextName) : nextName
			let label = labelStarting(spelled)
			let nextLabel = labelStarting(nextSpelled)
			return label == nextLabel ? (kindOfName(name) != kindOfName(nextName) || spelled <= nextSpelled) : label < nextLabel
		}
	}

	private func spellingInItsOwnNaming(_ name: String) -> String {
		guard let renaming else { return name }
		return GraphFuzzerRenaming.typeNamePrefix(in: name).map { renaming.rename(name, typeNamePrefix: String(name[$0])) } ?? renaming.renamingLabel(name)
	}

	/// The fields of `fields` that a lazy cycle's back-edge explains `otherFields` not having. A field whose owner on the
	/// other side has its label or its type is the same field changed, since a back-edge takes every field of an owner
	/// that holds the configuration of a type.
	private static func droppedFields(of fields: Fields, absentFrom otherFields: Fields, under renaming: GraphFuzzerRenaming, typesReachingType: [String: Set<String>], typesNoFieldNames: Set<String>) -> Set<ConfigurationField> {
		Set(fields.values.flatMap(\.values).filter { field in
			let otherFieldsOfOwner = otherFields[field.owner, default: [:]]
			return otherFieldsOfOwner[field.label] == nil
				&& !otherFieldsOfOwner.values.contains { $0.type == field.type }
				&& closesCycle(field, in: otherFields)
				&& renaming.changesOrder(ofTypeNames: typesDecidingTheBackEdge(of: field, typesReachingType: typesReachingType).union(typesNoFieldNames))
		})
	}

	/// Whether `field`'s struct is reached from the struct it holds, through `fields`: the fields of the outcome that lacks
	/// `field`, where the search that found the back-edge reached its owner from its type. A field whose type is no
	/// configuration names no struct, so it closes no cycle.
	private static func closesCycle(_ field: ConfigurationField, in fields: Fields) -> Bool {
		var visitedTypes = Set<String>()
		var typesToVisit = [field.type]
		while let type = typesToVisit.popLast() {
			guard type != field.owner else { return true }
			guard visitedTypes.insert(type).inserted else { continue }
			typesToVisit += fields[type, default: [:]].values.map(\.type)
		}
		return false
	}

	/// The names of the concrete types a configuration shows can decide whether `field` is a back-edge: its owner's, its
	/// type's, and that of every type that reaches them, since a search enters a cycle by those. A search from any other type
	/// never reaches the cycle.
	private static func typesDecidingTheBackEdge(of field: ConfigurationField, typesReachingType: [String: Set<String>]) -> Set<String> {
		guard let owner = concreteTypeName(ofConfigurationNamed: field.owner), let child = concreteTypeName(ofConfigurationNamed: field.type) else { return [] }
		var types: Set = [owner, child]
		var typesToVisit = [owner, child]
		while let type = typesToVisit.popLast() {
			for reachingType in typesReachingType[type, default: []] where types.insert(reachingType).inserted {
				typesToVisit.append(reachingType)
			}
		}
		return types
	}

	/// For each concrete type, the types with a field that holds its configuration, in any of `outcomes`.
	private static func typesReachingEachType(through outcomes: [Fields]) -> [String: Set<String>] {
		var typesReachingType = [String: Set<String>]()
		for field in outcomes.flatMap(\.values).flatMap(\.values) {
			if let owner = concreteTypeName(ofConfigurationNamed: field.owner), let child = concreteTypeName(ofConfigurationNamed: field.type) {
				typesReachingType[child, default: []].insert(owner)
			}
		}
		return typesReachingType
	}

	/// The name of the concrete type a configuration struct named `name` configures, as `computeCycleEdges` reads it, or
	/// `nil` when `name` names no configuration struct.
	private static func concreteTypeName(ofConfigurationNamed name: String) -> String? {
		if let suffix = ["SafeDIMockConfiguration", "SafeDIOverrides"].first(where: { name.hasSuffix(".\($0)") }) {
			return String(name.dropLast(suffix.count + 1))
		} else if name.hasPrefix(moduleLevelConfigurationPrefix), name.hasSuffix(moduleLevelConfigurationSuffix) {
			let moduleAndType = String(name.dropFirst(moduleLevelConfigurationPrefix.count).dropLast(moduleLevelConfigurationSuffix.count))
			return GraphFuzzerRenaming.typeNamePrefix(in: moduleAndType).map { String(moduleAndType[$0.lowerBound...]) }
		} else {
			return nil
		}
	}

	private static let moduleLevelConfigurationPrefix = "__safeDI_"
	private static let moduleLevelConfigurationSuffix = "_MockConfiguration"

	private static func configurationFields(in generatedFiles: [String: String]) -> Fields {
		var fields = Fields()
		for fileName in generatedFiles.keys.sorted() where fileName.hasSuffix("+SafeDIMock.swift") || fileName.hasSuffix("SafeDIMockConfiguration.swift") {
			let file = Parser.parse(source: generatedFiles[fileName, default: ""])
			guard !file.hasError else { continue }
			let collector = ConfigurationFieldCollector(viewMode: .sourceAccurate)
			collector.walk(file)
			fields.merge(collector.fields) { first, second in first.merging(second) { field, _ in field } }
		}
		return fields
	}
}

/// Whether `name` names a struct that holds the overrides of a mock's tree: a mock's `SafeDIOverrides`, a type's
/// `SafeDIMockConfiguration`, or a public mock's module-level configuration, spelled `__safeDI_<Module>_<Type>_MockConfiguration`.
private func isConfigurationStruct(named name: String) -> Bool {
	name == mockOverridesStructName || name == "SafeDIMockConfiguration" || name.hasSuffix("_MockConfiguration")
}

/// The name a field's type spells a configuration struct by: the extended type's, then the struct's, or the struct's own at
/// the top level.
private func configurationOwner(named name: String, extendedType: String?) -> String {
	extendedType.map { "\($0).\(name)" } ?? name
}

/// The label and type of `member` when it declares one field, or `nil` otherwise: a property a configuration stores, or
/// one that reads its field from the configuration's storage, as a property of the storage's class that holds it. The
/// property that holds the storage is no field.
private func storedField(of member: MemberBlockItemSyntax) -> (label: String, type: String)? {
	guard let variable = member.decl.as(VariableDeclSyntax.self),
	      variable.bindings.count == 1,
	      let binding = variable.bindings.first,
	      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
	      identifier.identifier.text != configurationStoragePropertyName,
	      let type = binding.typeAnnotation?.type.trimmedDescription
	else { return nil }
	return (identifier.identifier.text, type)
}

/// The name and value of `statement` when it binds one name.
private func binding(of statement: CodeBlockItemSyntax) -> (name: String, value: ExprSyntax)? {
	guard let variable = VariableDeclSyntax(statement.item),
	      variable.bindings.count == 1,
	      let binding = variable.bindings.first,
	      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
	      let value = binding.initializer?.value
	else { return nil }
	return (name, value)
}

/// Whether `statement` copies a mock's parameter out of its overrides: `let <label>: <type> = safeDIOverrides.<label>`.
private func isBindingOfReceiveOverride(_ statement: CodeBlockItemSyntax) -> Bool {
	guard let (name, value) = binding(of: statement), let access = value.as(MemberAccessExprSyntax.self) else { return false }
	return access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == mockOverridesParameterName && access.declName.baseName.text == name
}

/// `name` up to its first underscore: the label a name given apart from another's with the same label starts with.
private func labelStarting(_ name: String) -> String {
	String(name.prefix { $0 != "_" })
}

/// `name` without the type names it spells, which is what names of one label and kind have in common.
private func kindOfName(_ name: String) -> String {
	name.replacingOccurrences(of: "S[0-9]+_[A-Za-z]+[0-9]?", with: "", options: .regularExpression)
}

private let mockOverridesParameterName = "safeDIOverrides"
private let mockOverridesStructName = "SafeDIOverrides"
/// The property through which a configuration holds the class it keeps its fields in, and that class's name.
private let configurationStoragePropertyName = "__safeDI_storage"
private let configurationStorageTypeName = "__safeDI_Storage"

private final class ConfigurationFieldCollector: SyntaxVisitor {
	var fields = GraphFuzzerMockDifference.Fields()

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		guard isConfigurationStruct(named: node.name.text) else { return .visitChildren }
		var extendedType: String?
		var ancestor = node.parent
		while let current = ancestor, extendedType == nil {
			extendedType = current.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription
			ancestor = current.parent
		}
		let owner = configurationOwner(named: node.name.text, extendedType: extendedType)
		for member in node.memberBlock.members {
			guard let field = storedField(of: member) else { continue }
			fields[owner, default: [:]][field.label] = GraphFuzzerMockDifference.ConfigurationField(owner: owner, label: field.label, type: field.type)
		}
		return .skipChildren
	}
}

/// What the `mock` methods of a file show about the lists the generator sorts.
private final class MockMethodCollector: SyntaxVisitor {
	/// The labels of the fields of each `SafeDIOverrides` that override what its mock receives only if available: those
	/// the mock binds to a name of their own, which it does with no child of its tree.
	var overridesOfReceives = [String: Set<String>]()
	/// The types with a public mock, each of whose tiers sorts the parameters it takes as `T? = nil`.
	var typesWithPublicMock = Set<String>()

	/// Whether `declaration` is a tier of a mock: `mock()`, or the function only generated code calls, which a tier that
	/// takes a builder struct declares beside it with the same parameters (`__safeDI_mock` without the construction
	/// function's `safeDIBuilder` parameter).
	static func isMockMethod(_ declaration: FunctionDeclSyntax) -> Bool {
		switch declaration.name.text {
		case "mock":
			true
		case "__safeDI_mock":
			!declaration.signature.parameterClause.parameters.contains { $0.firstName.text == "safeDIBuilder" }
		default:
			false
		}
	}

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		guard Self.isMockMethod(node) else { return .skipChildren }
		var extendedType: String?
		var ancestor = node.parent
		while let current = ancestor, extendedType == nil {
			extendedType = current.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription
			ancestor = current.parent
		}
		if let extendedType, node.modifiers.contains(where: { $0.name.tokenKind == .keyword(.public) }) {
			typesWithPublicMock.insert(extendedType)
		}
		for statement in node.body?.statements ?? [] where isBindingOfReceiveOverride(statement) {
			if let name = binding(of: statement)?.name {
				overridesOfReceives[configurationOwner(named: mockOverridesStructName, extendedType: extendedType), default: []].insert(name)
			}
		}
		return .skipChildren
	}
}

/// The functions of a file that take the places entered, with the configurations they are handed, and every call of a
/// function by name, which a mock laid out from node records calls its functions by.
private final class EnteredFunctionCollector: SyntaxVisitor {
	var configurationsByFunction = [String: Set<String>]()
	var calls = [FunctionCallExprSyntax]()
	/// The names referred to other than as what a call calls, as a function is when handed on to be called later.
	var namesReferredToUncalled = Set<String>()

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		if let parameter = node.signature.parameterClause.parameters.first(where: { ($0.secondName ?? $0.firstName).text == "__safeDI_entered" }) {
			let type = parameter.type.trimmedDescription
			let opening = "__safeDI_Entered<"
			// A configuration no field can spell is no configuration to compare.
			let configuration = type.hasPrefix(opening) && type.hasSuffix(">") ? String(type.dropFirst(opening.count).dropLast()) : type
			configurationsByFunction[node.name.text, default: []].insert(configuration)
		}
		return .visitChildren
	}

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		if node.calledExpression.is(DeclReferenceExprSyntax.self) {
			calls.append(node)
		}
		return .visitChildren
	}

	override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
		if node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id != node.id {
			namesReferredToUncalled.insert(node.baseName.text)
		}
		return .visitChildren
	}
}

/// The names of each list's movable elements, in the order a file holds them, by what the list is.
private final class MovableLists {
	struct List: Hashable {
		enum Kind: Hashable, CaseIterable {
			case mockParameters
			case parameters
			case members
			case statements
			case lazilyInstantiatedWrappers
			case argumentsOfNarrowerTier
		}

		let extendedType: String?
		let configurationOwner: String?
		let kind: Kind
	}

	var namesByList = [List: [[String]]]()
}

/// Renders a file as source text, with its lists of parameters, members and statements normalized so that dropping or
/// moving an element leaves no trace of whitespace or commas, and the elements a known reason reorders or removes
/// sorted or gone. The text stays valid source, which `GraphFuzzerExtensionOrder` reads.
private struct Rendering {
	struct Scope {
		var extendedType: String?
		/// The configuration struct the node is in.
		var configurationOwner: String?
		var isInFunctionBody = false
		/// Whether the node is in a mock method or a configuration struct's initializer, directly and not in a function nested in it.
		var isMockMethod = false
		/// Whether the mock method is a tier of a public mock, and the labels of the parameters it takes as `T? = nil`.
		var isPublicMockMethod = false
		var optionalParametersOfPublicMock = Set<String>()
		var isConfigurationInitializer = false
		/// The names of the builder functions the node is in, outermost first, each with the construction it builds by
		/// (`Self.construction(builtBy:)`).
		var enclosingBuilderFunctions = [(name: String, returnType: String?, construction: String?)]()
	}

	let fields: GraphFuzzerMockDifference.Fields
	let droppedFields: Set<GraphFuzzerMockDifference.ConfigurationField>
	let mockMethods: MockMethodCollector
	let sortsParametersAndFields: Bool
	/// Whether elements of one label may have moved: a mock orders those by type, which a renaming that changes the
	/// order of type names reorders.
	let breaksLabelTiesByText: Bool
	let movableLists: MovableLists
	/// The functions of a mock laid out from node records that no configuration able to set an override reaches once
	/// each dropped field reads as a new configuration, and that a dropped field reaches
	/// (`functionsEnteredOnlyWithNewConfigurations(in:)`).
	var functionsEnteredOnlyWithNewConfigurations = Set<String>()

	func text(of node: Syntax, in outerScope: Scope) -> String {
		let scope = innerScope(of: node, in: outerScope)
		if let token = node.as(TokenSyntax.self) {
			return token.description
		} else if let clause = node.as(FunctionParameterClauseSyntax.self), scope.isMockMethod || scope.isConfigurationInitializer {
			return "\(clause.leftParen.leadingTrivia)(\(parametersText(of: clause.parameters, in: scope)))\(clause.rightParen.trailingTrivia)"
		} else if let list = node.as(MemberBlockItemListSyntax.self), scope.configurationOwner != nil {
			return membersText(of: list, in: scope)
		} else if let list = node.as(CodeBlockItemListSyntax.self), scope.isInFunctionBody {
			return statementsText(of: list, in: scope)
		} else if let call = node.as(FunctionCallExprSyntax.self), scope.isInFunctionBody, let entry = leftOutEntryOfDroppedField(call) {
			// The other outcome has no field to hand, so its call enters the place left out with a new configuration of the
			// field's type.
			return "\(call.leadingTrivia)\(Self.enteredPlacesParameterName).\(Self.leavingOutMemberName).\(Self.enteringFunctionName)(\(entry.slot), \(entry.field.type)())\(call.trailingTrivia)"
		} else if let list = node.as(LabeledExprListSyntax.self), scope.isInFunctionBody {
			return argumentsText(of: list, in: scope)
		} else if let expression = node.as(IfExprSyntax.self), let elseStatements = elseStatementsOfDroppedOverride(expression, in: scope) ?? elseStatementsOfOverrideNoConfigurationReaches(expression) {
			return expression.leadingTrivia.description + statementsText(of: elseStatements, in: scope) + expression.trailingTrivia.description
		} else {
			return node.children(viewMode: .sourceAccurate).map { text(of: $0, in: scope) }.joined()
		}
	}

	/// `outerScope`, narrowed by `node` when `node` is a declaration that opens a scope.
	private func innerScope(of node: Syntax, in outerScope: Scope) -> Scope {
		var scope = outerScope
		if let declaration = node.as(ExtensionDeclSyntax.self) {
			scope.extendedType = declaration.extendedType.trimmedDescription
		} else if let declaration = node.as(StructDeclSyntax.self) {
			scope.configurationOwner = isConfigurationStruct(named: declaration.name.text) ? configurationOwner(named: declaration.name.text, extendedType: scope.extendedType) : nil
		} else if let declaration = node.as(FunctionDeclSyntax.self) {
			scope.isMockMethod = !scope.isInFunctionBody && MockMethodCollector.isMockMethod(declaration)
			scope.isPublicMockMethod = scope.isMockMethod && scope.extendedType.map(mockMethods.typesWithPublicMock.contains) == true
			scope.optionalParametersOfPublicMock = scope.isPublicMockMethod ? Set(declaration.signature.parameterClause.parameters.filter { $0.defaultValue?.value.is(NilLiteralExprSyntax.self) == true }.map { ($0.secondName ?? $0.firstName).text }) : []
			scope.isConfigurationInitializer = false
			if scope.isInFunctionBody, declaration.name.text.hasPrefix(Self.builderFunctionPrefix) {
				scope.enclosingBuilderFunctions.append((name: declaration.name.text, returnType: declaration.signature.returnClause?.type.trimmedDescription, construction: Self.construction(builtBy: declaration)))
			}
			scope.isInFunctionBody = true
		} else if node.is(InitializerDeclSyntax.self) {
			scope.isConfigurationInitializer = scope.configurationOwner != nil
			scope.isMockMethod = false
			scope.isInFunctionBody = true
		}
		return scope
	}

	/// An element of a list, in the place it holds.
	private struct Place {
		let text: String
		/// The name the generator sorts the element by and the list it sorts it in, or `nil` when the element keeps its
		/// place whatever the labels.
		let sortedAs: (name: String, kind: MovableLists.List.Kind)?
	}

	/// `places`, the ones the generator sorts by label in order of those labels, list by list, when this rendering sorts,
	/// joined.
	private func joined(_ places: [Place], separator: String, in scope: Scope) -> String {
		var texts = places.map(\.text)
		for kind in MovableLists.List.Kind.allCases {
			let indices = places.indices.filter { places[$0].sortedAs?.kind == kind }
			guard !indices.isEmpty else { continue }
			let movable = indices.map { (text: places[$0].text, name: places[$0].sortedAs?.name ?? "") }
			movableLists.namesByList[MovableLists.List(extendedType: scope.extendedType, configurationOwner: scope.configurationOwner, kind: kind), default: []].append(movable.map(\.name))
			if sortsParametersAndFields {
				for (index, text) in zip(indices, textsInLabelOrder(movable)) {
					texts[index] = text
				}
			}
		}
		return texts.joined(separator: separator)
	}

	/// The texts of `movable` by label. Among those of one label, kinds stay in the order they come in, and elements of one
	/// kind are in order of their text when the renaming can have reordered them.
	private func textsInLabelOrder(_ movable: [(text: String, name: String)]) -> [String] {
		var rankOfKind = [String: Int]()
		for element in movable where rankOfKind[kindOfName(element.name)] == nil {
			rankOfKind[kindOfName(element.name)] = rankOfKind.count
		}
		return movable.enumerated().sorted { first, second in
			let firstLabel = labelStarting(first.element.name)
			let secondLabel = labelStarting(second.element.name)
			let firstRank = rankOfKind[kindOfName(first.element.name), default: 0]
			let secondRank = rankOfKind[kindOfName(second.element.name), default: 0]
			if firstLabel != secondLabel {
				return firstLabel < secondLabel
			} else if firstRank != secondRank {
				return firstRank < secondRank
			} else if breaksLabelTiesByText, first.element.text != second.element.text {
				return first.element.text < second.element.text
			} else {
				return first.offset < second.offset
			}
		}.map(\.element.text)
	}

	private func elementText(of node: some SyntaxProtocol, in scope: Scope, omittingTrailingComma trailingComma: TokenSyntax? = nil) -> String {
		node.children(viewMode: .sourceAccurate)
			.filter { $0.id != trailingComma?.id }
			.map { text(of: $0, in: scope) }
			.joined()
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func parametersText(of list: FunctionParameterListSyntax, in scope: Scope) -> String {
		joined(list.filter { !isDroppedField(labeled: $0.firstName.text, in: scope) }.map {
			Place(text: elementText(of: $0, in: scope, omittingTrailingComma: $0.trailingComma), sortedAs: nameSortedBy(parameter: $0, in: scope).map { name in (name, scope.isMockMethod && !scope.isPublicMockMethod ? .mockParameters : .parameters) })
		}, separator: ", ", in: scope)
	}

	/// The name `parameter` is sorted by. A configuration's initializer sorts only the overrides of what its mock receives.
	/// A public mock sorts the parameters it takes as `T? = nil`. Any other mock sorts its required parameters, and neither
	/// mock sorts its overrides, which come last.
	private func nameSortedBy(parameter: FunctionParameterSyntax, in scope: Scope) -> String? {
		let name = (parameter.secondName ?? parameter.firstName).text
		if scope.isConfigurationInitializer {
			return isOverrideOfReceive(labeled: name, in: scope) ? name : nil
		} else if name == mockOverridesParameterName {
			return nil
		} else if scope.isPublicMockMethod {
			return parameter.defaultValue?.value.is(NilLiteralExprSyntax.self) == true ? name : nil
		} else {
			return parameter.defaultValue == nil ? name : nil
		}
	}

	private func membersText(of list: MemberBlockItemListSyntax, in scope: Scope) -> String {
		joined(list.compactMap { member in
			let field = storedField(of: member)
			if let field, isDroppedField(labeled: field.label, in: scope) {
				return nil
			} else {
				return Place(text: elementText(of: member, in: scope), sortedAs: field.flatMap { isOverrideOfReceive(labeled: $0.label, in: scope) ? ($0.label, .members) : nil })
			}
		}, separator: "\n", in: scope)
	}

	private func statementsText(of list: CodeBlockItemListSyntax, in scope: Scope) -> String {
		joined(list.compactMap { statement in
			let assignedField = assignedFieldLabel(of: statement, in: scope)
			if let assignedField, isDroppedField(labeled: assignedField, in: scope) {
				return nil
			} else if isBindingOfDroppedOverride(statement, in: scope) {
				return nil
			} else {
				return Place(text: elementText(of: statement, in: scope), sortedAs: sortedAs(statement: statement, assigningField: assignedField, in: scope))
			}
		}, separator: "\n", in: scope)
	}

	/// How `statement` is sorted, when it assigns or copies the override of what a mock receives, or wraps the instance of a
	/// lazily instantiated dependency the mock is passed: the mock sorts both by label, each list on its own.
	private func sortedAs(statement: CodeBlockItemSyntax, assigningField assignedField: String?, in scope: Scope) -> (name: String, kind: MovableLists.List.Kind)? {
		if let assignedField {
			isOverrideOfReceive(labeled: assignedField, in: scope) ? (assignedField, .statements) : nil
		} else if scope.isMockMethod, let (name, value) = binding(of: statement) {
			if isBindingOfReceiveOverride(statement) {
				(name, .statements)
			} else if name.hasSuffix(Self.lazilyInstantiatedWrapperSuffix) || name.hasSuffix(Self.sendableLazilyInstantiatedWrapperSuffix), value.trimmedDescription.contains("LazilyInstantiated<") {
				(name, .lazilyInstantiatedWrappers)
			} else {
				nil
			}
		} else {
			nil
		}
	}

	private func isOverrideOfReceive(labeled label: String, in scope: Scope) -> Bool {
		scope.configurationOwner.map { mockMethods.overridesOfReceives[$0, default: []].contains(label) } ?? false
	}

	/// The arguments of a call, without those a default-valued parameter's override passes through a dropped field: the
	/// other outcome, which has no field to read, leaves the parameter its default. A public mock's builder passed along
	/// the other outcome passes as `nil`.
	private func argumentsText(of list: LabeledExprListSyntax, in scope: Scope) -> String {
		joined(list.compactMap { argument -> Place? in
			if scope.isConfigurationInitializer, isStorageInitialization(list), let label = argument.label?.text, isDroppedField(labeled: label, in: scope) {
				// The other outcome's configuration has no such field, so its initializer hands the storage none.
				nil
			} else if let label = argument.label?.text,
			          let read = droppedRead(of: overridesRead(by: argument.expression), byNodeAt: Syntax(argument), in: scope),
			          read.endsIn(label == mockOverridesParameterName ? nil : label)
			{
				label == Self.overrideBuilderName ? Place(text: "\(label): nil", sortedAs: nil) : nil
			} else if argument.label == nil, handsConfigurationToEnteredPlaces(list), let field = droppedFieldOfHandedConfiguration(readBy: argument.expression) {
				// The other outcome's configuration has no such field, so its function hands the places a new configuration
				// of the field's type.
				Place(text: "\(field.type)()", sortedAs: nil)
			} else {
				Place(text: elementText(of: argument, in: scope, omittingTrailingComma: argument.trailingComma), sortedAs: nameSortedBy(argument: argument, of: list, in: scope).map { ($0, .argumentsOfNarrowerTier) })
			}
		}, separator: ", ", in: scope)
	}

	/// The label `argument` is sorted by, when a wider tier of a public mock passes it to the narrowest tier, which sorts
	/// the parameters it takes as `T? = nil`: those of the wider tier, and those it passes `nil` for lacking them.
	private func nameSortedBy(argument: LabeledExprSyntax, of list: LabeledExprListSyntax, in scope: Scope) -> String? {
		guard scope.isPublicMockMethod,
		      let label = argument.label?.text,
		      let call = list.parent?.as(FunctionCallExprSyntax.self),
		      let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
		      ["mock", "__safeDI_mock"].contains(callee.declName.baseName.text),
		      callee.base?.trimmedDescription == scope.extendedType
		else { return nil }
		return scope.optionalParametersOfPublicMock.contains(label) || argument.expression.is(NilLiteralExprSyntax.self) ? label : nil
	}

	/// Whether `list` is the arguments of the call that creates a configuration's storage, one for each of its fields.
	private func isStorageInitialization(_ list: LabeledExprListSyntax) -> Bool {
		list.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == configurationStorageTypeName
	}

	/// Whether `list` is the arguments of a call that enters a place by name with the configuration it hands on, in a
	/// mock laid out from node records: `__safeDI_entered.entering(…)`.
	private func handsConfigurationToEnteredPlaces(_ list: LabeledExprListSyntax) -> Bool {
		guard let callee = list.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.as(MemberAccessExprSyntax.self) else { return false }
		return callee.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == Self.enteredPlacesParameterName && callee.declName.baseName.text == Self.enteringFunctionName
	}

	/// The dropped field `expression` reads, when it is `__safeDI_entered.configuration.<label>` in a function that is
	/// handed the places entered with the configuration that holds the field: a function of a mock laid out from node
	/// records is handed its configuration so, and reads a child's as a field of it.
	private func droppedFieldOfHandedConfiguration(readBy expression: ExprSyntax) -> GraphFuzzerMockDifference.ConfigurationField? {
		guard let read = expression.as(MemberAccessExprSyntax.self),
		      let configuration = read.base?.as(MemberAccessExprSyntax.self),
		      configuration.declName.baseName.text == Self.enteredConfigurationMemberName,
		      configuration.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == Self.enteredPlacesParameterName,
		      let owner = configurationHandedToFunction(around: Syntax(expression)),
		      let field = fields[owner]?[read.declName.baseName.text],
		      droppedFields.contains(field)
		else { return nil }
		return field
	}

	/// The slot and the dropped field of `call`, when it enters a place by name with a dropped field where the place is
	/// not left out (`__safeDI_entered.entering(<slot>, <read>)`): in a mock that may leave a place out, the field the
	/// handed configuration holds, read where the places entered are not left out
	/// (`__safeDI_entered.isLeftOut ? C() : __safeDI_entered.configuration.<label>`), or a field of the configuration a
	/// function that takes no places entered is handed as its overrides (`safeDIOverrides.<label>`). The other outcome,
	/// whose configuration has no such field, enters the place left out with a new configuration of the field's type
	/// (`__safeDI_entered.leavingOut.entering(<slot>, C())`), as its edge is one the configurations leave out.
	func leftOutEntryOfDroppedField(_ call: FunctionCallExprSyntax) -> (slot: String, field: GraphFuzzerMockDifference.ConfigurationField)? {
		guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
		      callee.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == Self.enteredPlacesParameterName,
		      callee.declName.baseName.text == Self.enteringFunctionName,
		      call.trailingClosure == nil,
		      call.arguments.count == 2,
		      let slot = call.arguments.first, slot.label == nil,
		      let handed = call.arguments.last, handed.label == nil,
		      let field = droppedFieldHandedWhereNotLeftOut(by: handed.expression)
		else { return nil }
		return (slot.expression.trimmedDescription, field)
	}

	/// The dropped field `expression` hands a place entered by name, as `leftOutEntryOfDroppedField(_:)` describes.
	private func droppedFieldHandedWhereNotLeftOut(by expression: ExprSyntax) -> GraphFuzzerMockDifference.ConfigurationField? {
		// The parser leaves a ternary unfolded: its condition, the `? then :`, and its else expression in sequence.
		if let sequence = expression.as(SequenceExprSyntax.self) {
			let elements = Array(sequence.elements)
			guard elements.count == 3,
			      let condition = elements[0].as(MemberAccessExprSyntax.self),
			      let choice = elements[1].as(UnresolvedTernaryExprSyntax.self),
			      condition.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == Self.enteredPlacesParameterName,
			      condition.declName.baseName.text == Self.isLeftOutMemberName,
			      let new = choice.thenExpression.as(FunctionCallExprSyntax.self), new.arguments.isEmpty, new.trailingClosure == nil,
			      let field = droppedFieldOfHandedConfiguration(readBy: elements[2]),
			      new.calledExpression.trimmedDescription == field.type
			else { return nil }
			return field
		} else if let read = expression.as(MemberAccessExprSyntax.self),
		          read.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == mockOverridesParameterName,
		          let owner = overridesParameterType(ofFunctionAround: Syntax(expression)),
		          let field = fields[owner]?[read.declName.baseName.text],
		          droppedFields.contains(field)
		{
			return field
		} else {
			return nil
		}
	}

	/// The type of the overrides the nearest function around `position` takes, when it takes them as `safeDIOverrides`
	/// and no places entered.
	private func overridesParameterType(ofFunctionAround position: Syntax) -> String? {
		var ancestor = position.parent
		while let current = ancestor {
			if let function = current.as(FunctionDeclSyntax.self) {
				let parameters = function.signature.parameterClause.parameters
				guard !parameters.contains(where: { ($0.secondName ?? $0.firstName).text == Self.enteredPlacesParameterName }),
				      let overrides = parameters.first(where: { ($0.secondName ?? $0.firstName).text == mockOverridesParameterName })
				else { return nil }
				return overrides.type.trimmedDescription
			}
			ancestor = current.parent
		}
		return nil
	}

	/// The configuration the nearest function around `position` that takes the places entered is handed with them, as a
	/// field's type spells it: the generic argument of its `__safeDI_entered` parameter's type.
	private func configurationHandedToFunction(around position: Syntax) -> String? {
		var ancestor = position.parent
		while let current = ancestor {
			if let function = current.as(FunctionDeclSyntax.self),
			   let parameter = function.signature.parameterClause.parameters.first(where: { ($0.secondName ?? $0.firstName).text == Self.enteredPlacesParameterName })
			{
				let type = parameter.type.trimmedDescription
				let opening = "\(Self.enteredTypeName)<"
				guard type.hasPrefix(opening), type.hasSuffix(">") else { return nil }
				return String(type.dropFirst(opening.count).dropLast())
			}
			ancestor = current.parent
		}
		return nil
	}

	private func isDroppedField(labeled label: String, in scope: Scope) -> Bool {
		guard let owner = scope.configurationOwner, let field = fields[owner]?[label] else { return false }
		return droppedFields.contains(field)
	}

	/// The label of the field `statement` assigns, for `self.<label> = <label>` in a configuration struct's initializer.
	private func assignedFieldLabel(of statement: CodeBlockItemSyntax, in scope: Scope) -> String? {
		guard scope.isConfigurationInitializer,
		      let sequence = SequenceExprSyntax(statement.item),
		      sequence.elements.count == 3,
		      let target = sequence.elements.first?.as(MemberAccessExprSyntax.self),
		      target.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.`self`),
		      sequence.elements.dropFirst().first?.is(AssignmentExprSyntax.self) == true,
		      sequence.elements.last?.as(DeclReferenceExprSyntax.self)?.baseName.text == target.declName.baseName.text
		else { return nil }
		return target.declName.baseName.text
	}

	/// Whether `statement` binds the local a `@Sendable` function reads an override through, when that override lies past a
	/// dropped field. Its read is checked where the local is used.
	private func isBindingOfDroppedOverride(_ statement: CodeBlockItemSyntax, in scope: Scope) -> Bool {
		guard let (name, value) = binding(of: statement), name.hasPrefix(Self.builderFunctionPrefix), let labels = labelsRead(by: value) else { return false }
		return passesDroppedField(labels, in: scope)
	}

	/// The statements of the `else` of `if let safeDIBuilder = <read> { … } else { … }` when `<read>`, directly or through
	/// a local binding, is the override of the node at the `if`'s place through a dropped field, which the mock's code had
	/// no field to read in the other outcome, and the `if` hands the builder what the `else` constructs with: what the `if`
	/// discards is then only the override.
	private func elseStatementsOfDroppedOverride(_ expression: IfExprSyntax, in scope: Scope) -> CodeBlockItemListSyntax? {
		guard expression.conditions.count == 1,
		      case let .optionalBinding(condition) = expression.conditions.first?.condition,
		      condition.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == Self.overrideBuilderName,
		      let value = condition.initializer?.value,
		      case let .codeBlock(elseBody) = expression.elseBody,
		      let read = droppedRead(of: boundValue(of: value) ?? value, byNodeAt: Syntax(expression), in: scope),
		      read.endsIn(nil) || read.endsIn(Self.overrideBuilderName),
		      let call = onlyCall(in: expression.body.statements),
		      let construction = onlyCall(in: elseBody.statements),
		      callsBuilderAs(call, construction: construction, namedByAStructNode: read.endsIn(Self.overrideBuilderName))
		else { return nil }
		return elseBody.statements
	}

	/// The statements of the `else` of `if let safeDIBuilder = __safeDI_entered.configuration.safeDIBuilder { … } else { … }`
	/// when the `if` is what a function of a mock laid out from node records returns, no configuration that could set an
	/// override reaches that function once each dropped field reads as a new configuration, a dropped field does
	/// (`functionsEnteredOnlyWithNewConfigurations(in:)`), and the `if` hands the builder what the `else` constructs with. The other outcome has no field through which any
	/// configuration reaches that function's node, so its function builds the node with no override to read
	/// (`MockEnteredSlots.hasConfigurationByDeclaration`); here every configuration it is handed is a new one, whose
	/// builder is `nil`, so what the `if` discards is only an override that is never set, and both build the same value.
	/// This goes, with the rest of a dropped field's forgiveness, once `computeCycleEdges` no longer follows names.
	private func elseStatementsOfOverrideNoConfigurationReaches(_ expression: IfExprSyntax) -> CodeBlockItemListSyntax? {
		guard expression.conditions.count == 1,
		      case let .optionalBinding(condition) = expression.conditions.first?.condition,
		      condition.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == Self.overrideBuilderName,
		      let read = condition.initializer?.value.as(MemberAccessExprSyntax.self),
		      read.declName.baseName.text == Self.overrideBuilderName,
		      Self.isHandedConfiguration(read.base),
		      case let .codeBlock(elseBody) = expression.elseBody,
		      let function = Self.functionReturning(expression),
		      functionsEnteredOnlyWithNewConfigurations.contains(function.name.text),
		      let call = onlyCall(in: expression.body.statements),
		      let construction = onlyCall(in: elseBody.statements),
		      callsBuilderAs(call, construction: construction, namedByAStructNode: true)
		else { return nil }
		return elseBody.statements
	}

	/// Whether `expression` is `__safeDI_entered.configuration`, the configuration a function is handed with the places
	/// entered.
	/// Whether `expression` is the places entered, or the places entered left out: `__safeDI_entered` or
	/// `__safeDI_entered.leavingOut`.
	private static func isEnteredPlaces(_ expression: ExprSyntax?) -> Bool {
		if let leavingOut = expression?.as(MemberAccessExprSyntax.self) {
			leavingOut.declName.baseName.text == leavingOutMemberName && leavingOut.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == enteredPlacesParameterName
		} else {
			expression?.as(DeclReferenceExprSyntax.self)?.baseName.text == enteredPlacesParameterName
		}
	}

	private static func isHandedConfiguration(_ expression: ExprSyntax?) -> Bool {
		guard let configuration = expression?.as(MemberAccessExprSyntax.self) else { return false }
		return configuration.declName.baseName.text == enteredConfigurationMemberName && configuration.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == enteredPlacesParameterName
	}

	/// The function whose last statement returns `expression`, directly.
	private static func functionReturning(_ expression: IfExprSyntax) -> FunctionDeclSyntax? {
		let statement = expression.parent?.as(ReturnStmtSyntax.self).map(Syntax.init) ?? expression.parent?.as(ExpressionStmtSyntax.self).map(Syntax.init) ?? Syntax(expression)
		guard let item = statement.parent?.as(CodeBlockItemSyntax.self),
		      let statements = item.parent?.as(CodeBlockItemListSyntax.self),
		      statements.last?.id == item.id,
		      let function = statements.parent?.as(CodeBlockSyntax.self)?.parent?.as(FunctionDeclSyntax.self)
		else { return nil }
		return function
	}

	/// The functions of `file` that take the places entered with a configuration and are handed no configuration that
	/// could set an override, once each dropped field reads as a new configuration: every call hands
	/// `__safeDI_entered.entering` a new configuration of the function's type, a dropped field of that type, or a field
	/// of the configuration handed to a function that is itself one of these; and a dropped field reaches the function,
	/// directly or through such a function. In the other outcome no field reaches its node, and so no configuration.
	/// A function declared twice with different configurations, called any other way, or referred to uncalled is not one.
	func functionsEnteredOnlyWithNewConfigurations(in file: SourceFileSyntax) -> Set<String> {
		let collector = EnteredFunctionCollector(viewMode: .sourceAccurate)
		collector.walk(file)
		var candidates = Set(collector.configurationsByFunction.keys)
		candidates.subtract(collector.namesReferredToUncalled)
		for (name, configurations) in collector.configurationsByFunction where configurations.count > 1 {
			candidates.remove(name)
		}
		var handsDroppedField = Set<String>()
		// The functions whose handed configuration each candidate is handed a field of.
		var handedFieldsOfFunctions = [String: Set<String>]()
		for call in collector.calls {
			guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
			      let configuration = collector.configurationsByFunction[name]?.first
			else { continue }
			guard let handed = call.arguments.first(where: { $0.label?.text == Self.enteredPlacesParameterName })?.expression.as(FunctionCallExprSyntax.self),
			      let callee = handed.calledExpression.as(MemberAccessExprSyntax.self),
			      Self.isEnteredPlaces(callee.base),
			      callee.declName.baseName.text == Self.enteringFunctionName,
			      handed.arguments.count >= 2,
			      let handedConfiguration = handed.arguments.dropFirst().first, handedConfiguration.label == nil
			else {
				candidates.remove(name)
				continue
			}
			if let field = droppedFieldOfHandedConfiguration(readBy: handedConfiguration.expression) ?? leftOutEntryOfDroppedField(handed)?.field, field.type == configuration {
				handsDroppedField.insert(name)
			} else if let new = handedConfiguration.expression.as(FunctionCallExprSyntax.self), new.arguments.isEmpty, new.trailingClosure == nil, new.calledExpression.trimmedDescription == configuration {
				// A new configuration, as the other outcome hands.
			} else if let read = handedConfiguration.expression.as(MemberAccessExprSyntax.self), Self.isHandedConfiguration(read.base), let caller = Self.functionTakingEnteredPlaces(around: Syntax(call)) {
				handedFieldsOfFunctions[name, default: []].insert(caller)
			} else {
				candidates.remove(name)
			}
		}
		// A candidate handed a field of a function that is not one is not one either.
		var changed = true
		while changed {
			changed = false
			for name in candidates where !(handedFieldsOfFunctions[name] ?? []).isSubset(of: candidates) {
				candidates.remove(name)
				changed = true
			}
		}
		// Of those, the ones a dropped field reaches.
		var reached = handsDroppedField.intersection(candidates)
		changed = true
		while changed {
			changed = false
			for name in candidates.subtracting(reached) where !(handedFieldsOfFunctions[name] ?? []).isDisjoint(with: reached) {
				reached.insert(name)
				changed = true
			}
		}
		return reached
	}

	/// The name of the nearest function around `position` that takes the places entered.
	private static func functionTakingEnteredPlaces(around position: Syntax) -> String? {
		var ancestor = position.parent
		while let current = ancestor {
			if let function = current.as(FunctionDeclSyntax.self), function.signature.parameterClause.parameters.contains(where: { ($0.secondName ?? $0.firstName).text == enteredPlacesParameterName }) {
				return function.name.text
			}
			ancestor = current.parent
		}
		return nil
	}

	/// The one call `statements` hold, or `nil` when they hold anything else.
	private func onlyCall(in statements: CodeBlockItemListSyntax) -> FunctionCallExprSyntax? {
		guard statements.count == 1, let statement = statements.first else { return nil }
		return FunctionCallExprSyntax(statement.item)
	}

	/// Whether `call` is an override's call of its builder that passes what `construction` passes, in order. A node with a
	/// configuration struct builds the concrete type, so when its construction erases, its override erases too; a leaf's
	/// builder returns the erased type, so only its construction erases.
	private func callsBuilderAs(_ call: FunctionCallExprSyntax, construction: FunctionCallExprSyntax, namedByAStructNode isStructNode: Bool) -> Bool {
		let erasedConstruction = wrappedCall(of: construction)
		if isStructNode, let erasedConstruction {
			guard let builderCall = wrappedCall(of: call), isBuilderCall(builderCall) else { return false }
			return call.calledExpression.trimmedDescription == construction.calledExpression.trimmedDescription && arguments(of: builderCall) == arguments(of: erasedConstruction)
		} else {
			return isBuilderCall(call) && arguments(of: call) == arguments(of: erasedConstruction ?? construction)
		}
	}

	private func isBuilderCall(_ call: FunctionCallExprSyntax) -> Bool {
		call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == Self.overrideBuilderName
	}

	/// The call `call` takes as its only, unlabeled argument, as an eraser takes what it erases.
	private func wrappedCall(of call: FunctionCallExprSyntax) -> FunctionCallExprSyntax? {
		guard call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil else { return nil }
		return argument.expression.as(FunctionCallExprSyntax.self)
	}

	/// What `call` passes, without its labels: a builder takes no labels where a construction does.
	private func arguments(of call: FunctionCallExprSyntax) -> [String] {
		call.arguments.map(\.expression.trimmedDescription)
	}

	/// The value a local `let` in an enclosing block gives the name `expression` refers to, or `nil` when it is no such name.
	private func boundValue(of expression: ExprSyntax) -> ExprSyntax? {
		guard let name = expression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return nil }
		var ancestor = expression.parent
		while let current = ancestor {
			if let statements = current.as(CodeBlockItemListSyntax.self),
			   let value = statements.lazy.compactMap({ binding(of: $0) }).first(where: { $0.name == name })?.value
			{
				return value
			}
			ancestor = current.parent
		}
		return nil
	}

	/// What `expression` reads of the overrides, past the call of a value a struct stores as a closure and the local a
	/// `@Sendable` function reads it through.
	private func overridesRead(by expression: ExprSyntax) -> ExprSyntax {
		var read = expression
		if let call = read.as(FunctionCallExprSyntax.self), call.arguments.isEmpty, call.trailingClosure == nil {
			read = call.calledExpression
		}
		return boundValue(of: read) ?? read
	}

	/// The labels `expression` names in turn, when it is `safeDIOverrides.<label>.<label>…`, or such a read's members
	/// read through the local a `@Sendable` function binds a whole configuration to.
	private func labelsRead(by expression: ExprSyntax) -> [String]? {
		var labels = [String]()
		var current = expression
		while true {
			while let access = current.as(MemberAccessExprSyntax.self), let base = access.base {
				labels.append(access.declName.baseName.text)
				current = base
			}
			guard let reference = current.as(DeclReferenceExprSyntax.self) else { return nil }
			if reference.baseName.text == mockOverridesParameterName {
				return labels.reversed()
			} else if let value = boundValue(of: current) {
				current = value
			} else {
				return nil
			}
		}
	}

	/// Whether every one of `labels` names a field of the struct the one before it holds, and one of those fields is dropped.
	private func passesDroppedField(_ labels: [String], in scope: Scope) -> Bool {
		guard let extendedType = scope.extendedType else { return false }
		var owner = configurationOwner(named: mockOverridesStructName, extendedType: extendedType)
		var passesDroppedField = false
		for label in labels {
			guard let field = fields[owner]?[label] else { return false }
			passesDroppedField = passesDroppedField || droppedFields.contains(field)
			owner = field.type
		}
		return passesDroppedField
	}

	/// What a read of the overrides adds to the path of the node it belongs to.
	private struct DroppedRead {
		let labelsPastNode: [String]

		/// Whether the read is the node's own entry when `label` is `nil`, and that entry's field `label` otherwise.
		func endsIn(_ label: String?) -> Bool {
			labelsPastNode == (label.map { [$0] } ?? [])
		}
	}

	/// The read `read` makes, when it passes a dropped field and begins with the path of the node built at `position`.
	private func droppedRead(of read: ExprSyntax, byNodeAt position: Syntax, in scope: Scope) -> DroppedRead? {
		guard let labels = labelsRead(by: read), passesDroppedField(labels, in: scope), let path = pathOfNode(at: position, in: scope), labels.starts(with: path) else { return nil }
		return DroppedRead(labelsPastNode: Array(labels.dropFirst(path.count)))
	}

	/// The labels of the path of the node built at `position`, which its place in the tree implies: one for each builder
	/// function around it, and the name it is bound to when it builds in a binding rather than in a function's return.
	private func pathOfNode(at position: Syntax, in scope: Scope) -> [String]? {
		guard let extendedType = scope.extendedType else { return nil }
		// The path and owner the builder functions around the node imply, or `nil` beneath an edge whose function reads no
		// overrides: a cycle edge, which leaves its field out of its owner's configuration.
		var current: (path: [String], owner: String)? = ([], configurationOwner(named: mockOverridesStructName, extendedType: extendedType))
		// Each builder function whose path resolved, with the path and owner it leaves.
		var resolved = [(construction: String?, path: [String], owner: String)]()
		for (index, function) in scope.enclosingBuilderFunctions.enumerated() {
			// A function that builds again what an enclosing function builds, as the same type built the same way, is a
			// lap of a cycle, which reads no field of its own even where its owner has one (`MockLowering.cycleNodeKey`).
			let isLap = function.construction != nil && scope.enclosingBuilderFunctions[..<index].contains { $0.returnType == function.returnType && $0.construction == function.construction }
			if !isLap, let (path, owner) = current, let label = labelBuilt(byFunctionNamed: function.name, amongFieldsOf: owner), let field = fields[owner]?[label] {
				current = (path + [label], field.type)
			} else if let construction = function.construction, let ancestor = resolved.last(where: { $0.construction == construction }) {
				// A function beneath a cycle edge that builds again a type an enclosing function built the same way reads
				// the overrides of that nearest ancestor, so its path is the ancestor's. An erased place builds its type
				// as a plain one does, so the construction, not the type the function returns, decides.
				current = (ancestor.path, ancestor.owner)
			} else {
				current = nil
			}
			if let (path, owner) = current {
				resolved.append((construction: function.construction, path: path, owner: owner))
			}
		}
		guard var path = current?.path else { return nil }
		if let bindingName = nameBound(aroundNodeAt: position) {
			path.append(bindingName)
		}
		return path
	}

	/// The label of the field of `owner` that the builder function named `function` builds: the function is named
	/// `__safeDI_<label>`, or that followed by the type it builds when a cycle-closing scope would otherwise refer to it.
	private func labelBuilt(byFunctionNamed function: String, amongFieldsOf owner: String) -> String? {
		let name = String(function.dropFirst(Self.builderFunctionPrefix.count))
		guard let labels = fields[owner]?.keys else { return nil }
		return labels.contains(name) ? name : labels.filter { name.hasPrefix("\($0)_") }.max { $0.count < $1.count }
	}

	/// The name the statement holding `position` binds, when the statement is directly in the function around `position`.
	private func nameBound(aroundNodeAt position: Syntax) -> String? {
		var statement: CodeBlockItemSyntax?
		var ancestor: Syntax? = position
		while let current = ancestor, !current.is(FunctionDeclSyntax.self) {
			statement = current.as(CodeBlockItemSyntax.self) ?? statement
			ancestor = current.parent
		}
		return statement.flatMap { binding(of: $0)?.name }
	}

	/// The construction a builder function builds its node by, the call its default branch returns once any erasure
	/// around it is unwrapped: `T` for `T(…)`, `T.<method>` for a static method such as a hand-written mock or
	/// `instantiate(…)`; else the type the function returns.
	static func construction(builtBy declaration: FunctionDeclSyntax) -> String? {
		var expression: ExprSyntax? = declaration.body?.statements.last.flatMap(Self.valueExpression(of:))
		while let ifExpression = expression?.as(IfExprSyntax.self) {
			expression = ifExpression.elseBody.flatMap { $0.as(CodeBlockSyntax.self) }?.statements.last.flatMap(Self.valueExpression(of:))
		}
		while let call = expression?.as(FunctionCallExprSyntax.self) {
			if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self), reference.baseName.text.first?.isUppercase == true {
				// An erasure wraps the construction as its one unlabeled argument.
				guard call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil, argument.expression.is(FunctionCallExprSyntax.self) else {
					return reference.baseName.text
				}
				expression = argument.expression
			} else if let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base?.as(DeclReferenceExprSyntax.self), base.baseName.text.first?.isUppercase == true {
				return "\(base.baseName.text).\(member.declName.baseName.text)"
			} else {
				break
			}
		}
		return declaration.signature.returnClause?.type.trimmedDescription
	}

	private static func valueExpression(of item: CodeBlockItemSyntax) -> ExprSyntax? {
		if let statement = item.item.as(ReturnStmtSyntax.self) {
			statement.expression
		} else if let statement = item.item.as(ExpressionStmtSyntax.self) {
			statement.expression
		} else {
			item.item.as(ExprSyntax.self)
		}
	}

	private static let builderFunctionPrefix = "__safeDI_"
	private static let lazilyInstantiatedWrapperSuffix = "_lazilyInstantiated"
	private static let sendableLazilyInstantiatedWrapperSuffix = "_sendableLazilyInstantiated"
	private static let overrideBuilderName = "safeDIBuilder"
	private static let enteredPlacesParameterName = "__safeDI_entered"
	private static let enteredTypeName = "__safeDI_Entered"
	private static let enteredConfigurationMemberName = "configuration"
	private static let enteringFunctionName = "entering"
	private static let leavingOutMemberName = "leavingOut"
	private static let isLeftOutMemberName = "isLeftOut"
}
