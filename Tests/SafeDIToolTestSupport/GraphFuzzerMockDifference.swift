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
/// reasons a difference in one of their files shows.
///
/// - The order of a mock's parameters and fields: a mock's parameters, the fields of its configuration structs, and the
///   statements that copy them are sorted by label, so a renaming that reorders labels reorders them. Those elements are
///   sorted among the places they hold, each list on its own and each element whole, and everything else stays where it
///   is, so a value that moved to another scope or to another label still differs.
/// - Which configuration fields exist: which back-edge of a lazy cycle loses its override follows the order of type
///   names, so a field of a configuration struct can be present in one outcome and absent from the other, along with
///   the reads of it, in this file or in another. A field counts only when no field of its owner and label exists on the
///   other side, and its type is a configuration, so a field whose type changed, or a plain parameter's field, still differs.
struct GraphFuzzerMockDifference: Sendable {
	enum Reason: Equatable, Sendable {
		case orderOfParametersAndFields
		case presenceOfConfigurationFields
	}

	init(generatedFiles: [String: String], otherGeneratedFiles: [String: String]) {
		fields = Self.configurationFields(in: generatedFiles)
		otherFields = Self.configurationFields(in: otherGeneratedFiles)
	}

	/// The reasons the difference between `code` and `otherCode`, a file of the first and of the other outcome, shows:
	/// each one it shows when applying exactly those explains every difference, or nothing when anything else differs too
	/// (the two then differ by more than the known reasons), when the two differ in nothing these read, or when either
	/// does not parse. A file's extensions may also have moved among their places, which these reasons do not name.
	func reasons(forDifferenceBetween code: String, and otherCode: String) -> [Reason] {
		let file = Parser.parse(source: code)
		let otherFile = Parser.parse(source: otherCode)
		guard !file.hasError, !otherFile.hasError else { return [] }
		let dropped = Set(fields.values.flatMap(\.values)).subtracting(Self.sameFields(in: fields, as: otherFields))
		let otherDropped = Set(otherFields.values.flatMap(\.values)).subtracting(Self.sameFields(in: otherFields, as: fields))

		func form(of file: SourceFileSyntax, in fields: Fields, dropping droppedFields: Set<ConfigurationField>, sorted: Bool) -> [UInt8] {
			let text = Rendering(fields: fields, droppedFields: droppedFields, sortsParametersAndFields: sorted).text(of: Syntax(file), in: Rendering.Scope())
			return GraphFuzzerExtensionOrder.sortingExtensionsWithinTheirPlaces(in: text)
		}
		let unchanged = form(of: file, in: fields, dropping: [], sorted: false)
		let otherUnchanged = form(of: otherFile, in: otherFields, dropping: [], sorted: false)
		let withoutFields = form(of: file, in: fields, dropping: dropped, sorted: false)
		let otherWithoutFields = form(of: otherFile, in: otherFields, dropping: otherDropped, sorted: false)
		let withoutFieldsSorted = form(of: file, in: fields, dropping: dropped, sorted: true)
		let otherWithoutFieldsSorted = form(of: otherFile, in: otherFields, dropping: otherDropped, sorted: true)

		guard withoutFieldsSorted == otherWithoutFieldsSorted else { return [] }
		var reasons = [Reason]()
		if withoutFields != otherWithoutFields {
			reasons.append(.orderOfParametersAndFields)
		}
		if unchanged != withoutFields || otherUnchanged != otherWithoutFields {
			reasons.append(.presenceOfConfigurationFields)
		}
		return reasons
	}

	/// A field of a configuration struct, which holds the overrides of a child of a mock's tree.
	fileprivate struct ConfigurationField: Hashable, Sendable {
		let owner: String
		let label: String
		let type: String
	}

	/// Each configuration struct's fields by label, by the struct's name as a field's type spells it.
	fileprivate typealias Fields = [String: [String: ConfigurationField]]

	private let fields: Fields
	private let otherFields: Fields

	/// The fields of `fields` that have the same owner and label in `otherFields`, whatever their type, so that a field
	/// counts as dropped only when its label is gone. A field that changed type is no dropped field.
	private static func sameFields(in fields: Fields, as otherFields: Fields) -> Set<ConfigurationField> {
		Set(fields.values.flatMap(\.values).filter { otherFields[$0.owner]?[$0.label] != nil })
	}

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
	name == "SafeDIOverrides" || name == "SafeDIMockConfiguration" || name.hasSuffix("_MockConfiguration")
}

/// The name a field's type spells a configuration struct by: the extended type's, then the struct's, or the struct's own at
/// the top level.
private func configurationOwner(named name: String, extendedType: String?) -> String {
	extendedType.map { "\($0).\(name)" } ?? name
}

/// The label and type of `member` when it declares one stored field, or `nil` otherwise.
private func storedField(of member: MemberBlockItemSyntax) -> (label: String, type: String)? {
	guard let variable = member.decl.as(VariableDeclSyntax.self),
	      variable.bindings.count == 1,
	      let binding = variable.bindings.first,
	      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
	      let type = binding.typeAnnotation?.type.trimmedDescription
	else { return nil }
	return (identifier.identifier.text, type)
}

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
			guard let field = storedField(of: member), field.type.hasSuffix("SafeDIMockConfiguration") || field.type.hasSuffix("_MockConfiguration") else { continue }
			fields[owner, default: [:]][field.label] = GraphFuzzerMockDifference.ConfigurationField(owner: owner, label: field.label, type: field.type)
		}
		return .skipChildren
	}
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
		var isConfigurationInitializer = false
	}

	let fields: GraphFuzzerMockDifference.Fields
	let droppedFields: Set<GraphFuzzerMockDifference.ConfigurationField>
	let sortsParametersAndFields: Bool

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
		} else if let list = node.as(LabeledExprListSyntax.self), scope.isInFunctionBody {
			return argumentsText(of: list, in: scope)
		} else if let expression = node.as(IfExprSyntax.self), let elseStatements = elseStatementsOfDroppedOverride(expression, in: scope) {
			return expression.leadingTrivia.description + statementsText(of: elseStatements, in: scope) + expression.trailingTrivia.description
		} else if let access = node.as(MemberAccessExprSyntax.self), readsDroppedField(ExprSyntax(access), in: scope) {
			// Passed along, as a hole's builder is, where the other outcome, which has no field to read, passes `nil`.
			return "\(access.leadingTrivia)nil\(access.trailingTrivia)"
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
			scope.isMockMethod = !scope.isInFunctionBody && declaration.name.text == "mock"
			scope.isConfigurationInitializer = false
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
		let isMovable: Bool
	}

	/// `places`, the ones that may move sorted among the places they hold when this rendering sorts, joined.
	private func joined(_ places: [Place], separator: String) -> String {
		var movableTexts = places.filter(\.isMovable).map(\.text)
		if sortsParametersAndFields {
			movableTexts.sort()
		}
		var nextMovable = movableTexts.makeIterator()
		return places.map { place in
			place.isMovable ? (nextMovable.next() ?? place.text) : place.text
		}.joined(separator: separator)
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
			Place(text: elementText(of: $0, in: scope, omittingTrailingComma: $0.trailingComma), isMovable: true)
		}, separator: ", ")
	}

	private func membersText(of list: MemberBlockItemListSyntax, in scope: Scope) -> String {
		joined(list.compactMap { member in
			let field = storedField(of: member)
			if let field, isDroppedField(labeled: field.label, in: scope) {
				return nil
			} else {
				return Place(text: elementText(of: member, in: scope), isMovable: field != nil)
			}
		}, separator: "\n")
	}

	private func statementsText(of list: CodeBlockItemListSyntax, in scope: Scope) -> String {
		joined(list.compactMap { statement in
			let assignedField = assignedFieldLabel(of: statement, in: scope)
			if let assignedField, isDroppedField(labeled: assignedField, in: scope) {
				return nil
			} else if isBindingOfDroppedOverride(statement, in: scope) {
				return nil
			} else {
				return Place(text: elementText(of: statement, in: scope), isMovable: assignedField != nil || isParameterBinding(statement, in: scope))
			}
		}, separator: "\n")
	}

	/// The arguments of a call, without those a default-valued parameter's override passes through a dropped field: the
	/// other outcome, which has no field to read, leaves the parameter its default. A builder passed along, which the
	/// other outcome passes as `nil`, stays.
	private func argumentsText(of list: LabeledExprListSyntax, in scope: Scope) -> String {
		list.filter { argument in
			guard let label = argument.label?.text, label != Self.overrideBuilderName else { return true }
			return !readsDroppedField(argument.expression, in: scope)
		}.map { elementText(of: $0, in: scope, omittingTrailingComma: $0.trailingComma) }.joined(separator: ", ")
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

	/// Whether `statement` copies a mock's parameter out of its overrides: `let <label>: <type> = safeDIOverrides.<label>`.
	private func isParameterBinding(_ statement: CodeBlockItemSyntax, in scope: Scope) -> Bool {
		guard scope.isMockMethod, let (name, value) = binding(of: statement), let access = value.as(MemberAccessExprSyntax.self) else { return false }
		return access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == Self.overridesParameterName && access.declName.baseName.text == name
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

	private func isBindingOfDroppedOverride(_ statement: CodeBlockItemSyntax, in scope: Scope) -> Bool {
		guard let (_, value) = binding(of: statement) else { return false }
		return readsDroppedField(value, in: scope)
	}

	/// The statements of the `else` of `if let safeDIBuilder = <read> { … } else { … }` when `<read>`, directly or through
	/// a local binding, reads an override through a dropped field: the mock's code had no field to read in the other outcome.
	private func elseStatementsOfDroppedOverride(_ expression: IfExprSyntax, in scope: Scope) -> CodeBlockItemListSyntax? {
		guard expression.conditions.count == 1,
		      case let .optionalBinding(condition) = expression.conditions.first?.condition,
		      condition.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == Self.overrideBuilderName,
		      let value = condition.initializer?.value,
		      case let .codeBlock(elseBody) = expression.elseBody,
		      readsDroppedField(boundValue(of: value) ?? value, in: scope)
		else { return nil }
		return elseBody.statements
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

	/// Whether `expression` is `safeDIOverrides.<label>.<label>…`, a walk of configuration fields that passes through a dropped one.
	private func readsDroppedField(_ expression: ExprSyntax, in scope: Scope) -> Bool {
		guard let extendedType = scope.extendedType else { return false }
		var labels = [String]()
		var current = expression
		while let access = current.as(MemberAccessExprSyntax.self), let base = access.base {
			labels.append(access.declName.baseName.text)
			current = base
		}
		guard current.as(DeclReferenceExprSyntax.self)?.baseName.text == Self.overridesParameterName else { return false }
		var owner = configurationOwner(named: "SafeDIOverrides", extendedType: extendedType)
		for label in labels.reversed() {
			guard let field = fields[owner]?[label] else { return false }
			guard !droppedFields.contains(field) else { return true }
			owner = field.type
		}
		return false
	}

	private static let overridesParameterName = "safeDIOverrides"
	private static let overrideBuilderName = "safeDIBuilder"
}
