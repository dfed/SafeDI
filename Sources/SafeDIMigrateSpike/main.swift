// SPIKE: a prototype of a 3.0 `SafeDITool migrate`. Never to land. It rewrites a 2.x project's sources for every
// 3.0 call-site break at once: the "fake" rename, D12's `{ }` around created dependencies a mock cannot build, and
// config-down-tree option B (a mocked type's own default-valued arguments move into `safeDIOverrides: .init(…)`).
//
// Usage: SafeDIMigrateSpike --generated DIR [--generated DIR…] --sources DIR [--sources DIR…] [--write] [--diff-out DIR]
//
// `--generated` names directories holding the 2.x generated code, whose `// safedi-migrate-signature:` lines (a spike
// hook in ScopeGenerator) say what role each `mock()` parameter plays. A real `migrate` would run the generator in
// process instead.

import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Signatures

struct ParameterRecord: Decodable {
	let label: String
	let kind: String
	let isSendableAutoclosure: Bool?
	let isOptional: Bool?
	let creatingTypeCount: Int?
}

struct SignatureRecord: Decodable {
	let type: String
	let isPublic: Bool
	let hasOverrides: Bool
	let parameters: [ParameterRecord]
}

// MARK: - Report

enum EditCategory: String, CaseIterable {
	// Fully mechanical, syntax only.
	case attributeLabel = "attribute label (generateMock, mockOnly, mockAttributes, customMockName)"
	case configurationLabel = "#SafeDIConfiguration label"
	case mockGenerationType = "MockGeneration → FakeGeneration"
	case configurationTypeName = "SafeDIMockConfiguration → SafeDIFakeConfiguration"
	case handWrittenMockDeclaration = "hand-written mock declaration renamed"
	// Mechanical given SafeDI's scan of the project (no type checker).
	case generatedMockCallRenamed = "generated mock call: .mock( → .fake("
	case handWrittenMockCallRenamed = "hand-written mock call: .mock( → .fake("
	case createdDependencyWrapped = "D12: created dependency wrapped in { } (a reference: still one shared value)"
	case createdDependencyWrappedExpression = "D12: created dependency wrapped in { } (an expression: now evaluated once per creation)"
	case sendableAutoclosureWrapped = "D12: @Sendable autoclosure argument wrapped in { } (same semantics)"
	case ownDefaultMovedIntoNewOverrides = "B: own default moved into a new safeDIOverrides: .init(…)"
	case ownDefaultMergedIntoOverrides = "B: own default appended to an existing safeDIOverrides: .init(…)"
	case publicNilDefaultDropped = "B: public mock's `nil` (use the default) argument dropped"
	case implicitMemberResolvedFromAnnotation = "implicit member .mock( resolved from a type annotation or return type"
	case selfOrBareCallResolvedLexically = "call through Self./bare name inside the type, resolved lexically"
	// Not mechanical: needs type information or a person.
	case unresolvedImplicitMember = "UNRESOLVED: implicit member .mock( (needs the contextual type)"
	case unresolvedReference = "UNRESOLVED: .mock referenced without a call (function value)"
	case unresolvedOverridesNotLiteral = "UNRESOLVED: own default beside a safeDIOverrides that is not a .init(…) literal"
	case unresolvedUnknownLabel = "UNRESOLVED: argument label not in the 2.x signature (trailing closure or stale call)"
	case leftAloneUnknownBase = "left alone: .mock( on a type SafeDI does not mock (another library's, a typealias, a generic)"
}

final class Report {
	var counts = [EditCategory: Int]()
	var sites = [EditCategory: [String]]()
	func record(_ category: EditCategory, _ site: String) {
		counts[category, default: 0] += 1
		if sites[category, default: []].count < 12 { sites[category, default: []].append(site) }
	}
}

// MARK: - The rewrite

let attributeLabelRenames = ["generateMock": "generateFake", "mockOnly": "fakeOnly", "mockAttributes": "fakeAttributes", "customMockName": "customFakeName"]
let configurationLabelRenames = ["additionalMocksToGenerate": "additionalFakesToGenerate", "mockConditionalCompilation": "fakeConditionalCompilation"]

struct HandWrittenMockTypes {
	/// Types whose hand-written mock SafeDI finds by the default name `mock`.
	var names = Set<String>()
}

/// Finds the types whose `@Instantiable` declaration holds a hand-written `static func mock` and no `customMockName`.
final class HandWrittenMockCollector: SyntaxVisitor {
	var types = HandWrittenMockTypes()
	var typeStack = [String]()

	func instantiableArguments(_ attributes: AttributeListSyntax) -> LabeledExprListSyntax?? {
		for element in attributes {
			guard let attribute = element.as(AttributeSyntax.self), attribute.attributeName.trimmedDescription == "Instantiable" else { continue }
			return .some(attribute.arguments?.as(LabeledExprListSyntax.self))
		}
		return .none
	}

	func visitType(named name: String, attributes: AttributeListSyntax, members: MemberBlockSyntax) {
		let qualified = (typeStack + [name]).joined(separator: ".")
		if case let .some(arguments) = instantiableArguments(attributes) {
			let hasCustomName = arguments?.contains { $0.label?.text == "customMockName" } ?? false
			let declaresMock = members.members.contains { member in
				guard let function = member.decl.as(FunctionDeclSyntax.self) else { return false }
				return function.name.text == "mock" && function.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
			}
			if !hasCustomName, declaresMock { types.names.insert(qualified) }
		}
	}

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { visitType(named: node.name.text, attributes: node.attributes, members: node.memberBlock); typeStack.append(node.name.text); return .visitChildren }
	override func visitPost(_: ClassDeclSyntax) { typeStack.removeLast() }
	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { visitType(named: node.name.text, attributes: node.attributes, members: node.memberBlock); typeStack.append(node.name.text); return .visitChildren }
	override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }
	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { visitType(named: node.name.text, attributes: node.attributes, members: node.memberBlock); typeStack.append(node.name.text); return .visitChildren }
	override func visitPost(_: ActorDeclSyntax) { typeStack.removeLast() }
	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { visitType(named: node.name.text, attributes: node.attributes, members: node.memberBlock); typeStack.append(node.name.text); return .visitChildren }
	override func visitPost(_: EnumDeclSyntax) { typeStack.removeLast() }
	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { visitType(named: node.extendedType.trimmedDescription, attributes: node.attributes, members: node.memberBlock); typeStack.append(node.extendedType.trimmedDescription); return .visitChildren }
	override func visitPost(_: ExtensionDeclSyntax) { typeStack.removeLast() }
}

final class MigrationRewriter: SyntaxRewriter {
	let signatures: [String: [SignatureRecord]]
	let handWritten: HandWrittenMockTypes
	let report: Report
	let fileName: String
	let converter: SourceLocationConverter
	var typeStack = [String]()
	/// Whether the walk is inside an `@Instantiable` declaration, where a `static func mock` is the hand-written mock.
	var instantiableDepth = [Bool]()

	init(signatures: [String: [SignatureRecord]], handWritten: HandWrittenMockTypes, report: Report, fileName: String, tree: SourceFileSyntax) {
		self.signatures = signatures
		self.handWritten = handWritten
		self.report = report
		self.fileName = fileName
		converter = SourceLocationConverter(fileName: fileName, tree: tree)
		super.init(viewMode: .sourceAccurate)
	}

	func site(_ node: some SyntaxProtocol) -> String {
		"\(fileName):\(node.startLocation(converter: converter).line)"
	}

	// Resolution of a type name as written to a signature key: the full text, else with leading components dropped
	// (a module qualifier), else nested inside the enclosing types.
	func resolve(_ written: String) -> String? {
		var components = written.split(separator: ".").map(String.init)
		while !components.isEmpty {
			let candidate = components.joined(separator: ".")
			if signatures[candidate] != nil || handWritten.names.contains(candidate) { return candidate }
			components.removeFirst()
		}
		for depth in stride(from: typeStack.count, to: 0, by: -1) {
			let candidate = (typeStack.prefix(depth) + [written]).joined(separator: ".")
			if signatures[candidate] != nil || handWritten.names.contains(candidate) { return candidate }
		}
		return nil
	}

	// MARK: Declarations

	func isInstantiable(_ attributes: AttributeListSyntax) -> Bool {
		attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Instantiable" }
	}

	override func visit(_ node: ClassDeclSyntax) -> DeclSyntax { enter(node.name.text, isInstantiable(node.attributes)); defer { exit() }; return super.visit(node) }
	override func visit(_ node: StructDeclSyntax) -> DeclSyntax { enter(node.name.text, isInstantiable(node.attributes)); defer { exit() }; return super.visit(node) }
	override func visit(_ node: ActorDeclSyntax) -> DeclSyntax { enter(node.name.text, isInstantiable(node.attributes)); defer { exit() }; return super.visit(node) }
	override func visit(_ node: EnumDeclSyntax) -> DeclSyntax { enter(node.name.text, isInstantiable(node.attributes)); defer { exit() }; return super.visit(node) }
	override func visit(_ node: ExtensionDeclSyntax) -> DeclSyntax { enter(node.extendedType.trimmedDescription, isInstantiable(node.attributes)); defer { exit() }; return super.visit(node) }
	func enter(_ name: String, _ instantiable: Bool) { typeStack.append(name); instantiableDepth.append(instantiable) }
	func exit() { typeStack.removeLast(); instantiableDepth.removeLast() }

	override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
		let visited = super.visit(node)
		guard var function = visited.as(FunctionDeclSyntax.self) else { return visited }
		if function.name.text == "mock", instantiableDepth.last == true,
		   handWritten.names.contains(typeStack.joined(separator: "."))
		{
			function.name = .identifier("fake", leadingTrivia: function.name.leadingTrivia, trailingTrivia: function.name.trailingTrivia)
			report.record(.handWrittenMockDeclaration, site(node))
			return DeclSyntax(function)
		}
		return visited
	}

	override func visit(_ node: AttributeSyntax) -> AttributeSyntax {
		guard node.attributeName.trimmedDescription == "Instantiable", var arguments = node.arguments?.as(LabeledExprListSyntax.self) else { return super.visit(node) }
		var changed = false
		arguments = LabeledExprListSyntax(arguments.map { argument in
			guard let label = argument.label, let renamed = attributeLabelRenames[label.text] else { return argument }
			changed = true
			report.record(.attributeLabel, site(node))
			return argument.with(\.label, .identifier(renamed, leadingTrivia: label.leadingTrivia, trailingTrivia: label.trailingTrivia))
		})
		let rewritten = changed ? node.with(\.arguments, .argumentList(arguments)) : node
		return super.visit(rewritten)
	}

	override func visit(_ node: MacroExpansionDeclSyntax) -> DeclSyntax {
		guard node.macroName.text == "SafeDIConfiguration" else { return super.visit(node) }
		let arguments = LabeledExprListSyntax(node.arguments.map { argument in
			guard let label = argument.label, let renamed = configurationLabelRenames[label.text] else { return argument }
			report.record(.configurationLabel, site(node))
			return argument.with(\.label, .identifier(renamed, leadingTrivia: label.leadingTrivia, trailingTrivia: label.trailingTrivia))
		})
		return super.visit(node.with(\.arguments, arguments))
	}

	override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
		if node.name.text == "MockGeneration" {
			report.record(.mockGenerationType, site(node))
			return TypeSyntax(node.with(\.name, .identifier("FakeGeneration", leadingTrivia: node.name.leadingTrivia, trailingTrivia: node.name.trailingTrivia)))
		}
		if node.name.text == "SafeDIMockConfiguration" {
			report.record(.configurationTypeName, site(node))
			return TypeSyntax(node.with(\.name, .identifier("SafeDIFakeConfiguration", leadingTrivia: node.name.leadingTrivia, trailingTrivia: node.name.trailingTrivia)))
		}
		return super.visit(node)
	}

	override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
		if node.name.text == "SafeDIMockConfiguration" {
			report.record(.configurationTypeName, site(node))
			return super.visit(node.with(\.name, .identifier("SafeDIFakeConfiguration", leadingTrivia: node.name.leadingTrivia, trailingTrivia: node.name.trailingTrivia)))
		}
		return super.visit(node)
	}

	// MARK: Expressions

	override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
		// `.SafeDIMockConfiguration(…)` / `.SafeDIMockConfiguration.init` in expression position.
		if node.declName.baseName.text == "SafeDIMockConfiguration" {
			report.record(.configurationTypeName, site(node))
			return super.visit(node.with(\.declName, node.declName.with(\.baseName, .identifier("SafeDIFakeConfiguration", leadingTrivia: node.declName.baseName.leadingTrivia, trailingTrivia: node.declName.baseName.trailingTrivia))))
		}
		if node.declName.baseName.text == "MockGeneration" {
			report.record(.mockGenerationType, site(node))
			return super.visit(node.with(\.declName, node.declName.with(\.baseName, .identifier("FakeGeneration"))))
		}
		// `T.mock` not directly called.
		if node.declName.baseName.text == "mock", node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id != node.id {
			if let base = node.base, resolve(base.trimmedDescription) != nil {
				report.record(.unresolvedReference, site(node))
			}
		}
		return super.visit(node)
	}

	override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
		if node.baseName.text == "MockGeneration" {
			report.record(.mockGenerationType, site(node))
			return ExprSyntax(node.with(\.baseName, .identifier("FakeGeneration", leadingTrivia: node.baseName.leadingTrivia, trailingTrivia: node.baseName.trailingTrivia)))
		}
		return super.visit(node)
	}

	override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
		// Rewrite the arguments' own calls first.
		let visited = super.visit(node)
		guard let call = visited.as(FunctionCallExprSyntax.self) else { return visited }

		// Which type the call's `mock` belongs to.
		let typeKey: String?
		var calleeIsMemberAccess = false
		if let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "mock" {
			calleeIsMemberAccess = true
			if let base = member.base {
				let written = base.trimmedDescription
				if written == "Self" || written == "self" {
					typeKey = typeStack.isEmpty ? nil : resolve(typeStack.joined(separator: "."))
					if typeKey != nil { report.record(.selfOrBareCallResolvedLexically, site(node)) }
				} else {
					typeKey = resolve(written)
					if typeKey == nil { report.record(.leftAloneUnknownBase, site(node)); return visited }
				}
			} else if let contextual = contextualTypeName(of: Syntax(node)), let resolved = resolve(contextual) {
				typeKey = resolved
				report.record(.implicitMemberResolvedFromAnnotation, site(node))
			} else {
				report.record(.unresolvedImplicitMember, site(node))
				return visited
			}
		} else if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self), reference.baseName.text == "mock", !typeStack.isEmpty {
			typeKey = resolve(typeStack.joined(separator: "."))
			if typeKey != nil { report.record(.selfOrBareCallResolvedLexically, site(node)) }
		} else {
			return visited
		}
		guard let typeKey else { return visited }

		var rewritten = call
		rewritten.calledExpression = renamedCallee(call.calledExpression, memberAccess: calleeIsMemberAccess)

		guard let overloads = signatures[typeKey] else {
			report.record(.handWrittenMockCallRenamed, site(node))
			return ExprSyntax(rewritten)
		}
		report.record(.generatedMockCallRenamed, site(node))
		if call.trailingClosure != nil || !call.additionalTrailingClosures.isEmpty {
			report.record(.unresolvedUnknownLabel, site(node))
			return ExprSyntax(rewritten)
		}

		// The overload whose labels hold every label the call passes.
		let passedLabels = Set(call.arguments.compactMap { $0.label?.text })
		guard let signature = overloads.first(where: { record in
			passedLabels.isSubset(of: Set(record.parameters.map(\.label) + ["safeDIOverrides"]))
		}) else {
			report.record(.unresolvedUnknownLabel, site(node))
			return ExprSyntax(rewritten)
		}
		let parameterByLabel = Dictionary(signature.parameters.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })

		var keptArguments = [LabeledExprSyntax]()
		var inOrder = [LabeledExprSyntax]()
		var movedDefaults = [(order: Int, argument: LabeledExprSyntax)]()
		var overridesArgument: LabeledExprSyntax?
		let rootDefaultOrder = Dictionary(signature.parameters.filter { $0.kind == "rootDefault" }.enumerated().map { ($1.label, $0) }, uniquingKeysWith: { first, _ in first })
		for argument in call.arguments {
			guard let label = argument.label?.text else { keptArguments.append(argument); inOrder.append(argument); continue }
			if label == "safeDIOverrides" { overridesArgument = argument; inOrder.append(argument); continue }
			guard let parameter = parameterByLabel[label] else { keptArguments.append(argument); inOrder.append(argument); continue }
			switch parameter.kind {
			case "uncovered":
				let wrapped = ClosureExprSyntax(
					leftBrace: .leftBraceToken(trailingTrivia: .space),
					statements: CodeBlockItemListSyntax([CodeBlockItemSyntax(item: .expr(argument.expression.trimmed))]),
					rightBrace: .rightBraceToken(leadingTrivia: .space),
				)
				let wrappedArgument = argument.with(\.expression, ExprSyntax(wrapped).with(\.leadingTrivia, argument.expression.leadingTrivia).with(\.trailingTrivia, argument.expression.trailingTrivia))
				keptArguments.append(wrappedArgument)
				inOrder.append(wrappedArgument)
				let isReference = argument.expression.is(DeclReferenceExprSyntax.self) || argument.expression.as(MemberAccessExprSyntax.self).map { $0.base?.is(DeclReferenceExprSyntax.self) ?? false } ?? false
				report.record(parameter.isSendableAutoclosure == true ? .sendableAutoclosureWrapped : (isReference ? .createdDependencyWrapped : .createdDependencyWrappedExpression), site(argument))
			case "rootDefault":
				if signature.isPublic, parameter.isOptional == false, argument.expression.is(NilLiteralExprSyntax.self) {
					report.record(.publicNilDefaultDropped, site(argument))
					continue
				}
				movedDefaults.append((rootDefaultOrder[label] ?? 0, argument))
				inOrder.append(argument)
			default:
				keptArguments.append(argument)
				inOrder.append(argument)
			}
		}

		if !movedDefaults.isEmpty {
			let moved = movedDefaults.sorted { $0.order < $1.order }.map { $0.argument.trimmed }
			if let overridesArgument {
				// `.init(…)`, `T.SafeDIOverrides(…)` or `T.SafeDIOverrides.init(…)`.
				let isOverridesLiteral: (FunctionCallExprSyntax) -> Bool = { initCall in
					let callee = initCall.calledExpression.trimmedDescription
					return callee == ".init" || callee.hasSuffix("SafeDIOverrides") || callee.hasSuffix("SafeDIOverrides.init")
				}
				guard let initCall = overridesArgument.expression.as(FunctionCallExprSyntax.self), isOverridesLiteral(initCall), initCall.trailingClosure == nil else {
					// Everything else is migrated; the own defaults stay where they were, which 3.0 rejects as extra
					// arguments at this call, and the site is listed for a person.
					report.record(.unresolvedOverridesNotLiteral, site(node))
					return ExprSyntax(finish(rewritten, call: call, keptArguments: inOrder))
				}
				// B's field order: the tree's fields (already in the call), then the type's own defaults in initializer order.
				var initArguments = Array(initCall.arguments)
				let continuation = initArguments.last?.leadingTrivia ?? []
				let isMultiLine = continuation.contains { if case .newlines = $0 { true } else { false } }
				let commaTrivia: Trivia = isMultiLine ? [] : .space
				let originalLastComma = initArguments.last?.trailingComma
				if !initArguments.isEmpty {
					initArguments[initArguments.count - 1] = initArguments[initArguments.count - 1].with(\.trailingComma, .commaToken(trailingTrivia: commaTrivia))
				}
				for (index, argument) in moved.enumerated() {
					let isLast = index == moved.count - 1
					initArguments.append(argument.with(\.leadingTrivia, isMultiLine ? continuation : []).with(\.trailingComma, isLast ? originalLastComma : .commaToken(trailingTrivia: commaTrivia)))
					report.record(.ownDefaultMergedIntoOverrides, site(argument))
				}
				let newInit = initCall.with(\.arguments, LabeledExprListSyntax(initArguments))
				keptArguments.append(overridesArgument.with(\.expression, ExprSyntax(newInit)))
			} else {
				var initArguments = [LabeledExprSyntax]()
				for (index, argument) in moved.enumerated() {
					initArguments.append(argument.with(\.leadingTrivia, []).with(\.trailingComma, index == moved.count - 1 ? nil : .commaToken(trailingTrivia: .space)))
					report.record(.ownDefaultMovedIntoNewOverrides, site(argument))
				}
				let initCall = FunctionCallExprSyntax(
					calledExpression: MemberAccessExprSyntax(period: .periodToken(), declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))),
					leftParen: .leftParenToken(),
					arguments: LabeledExprListSyntax(initArguments),
					rightParen: .rightParenToken(),
				)
				let leading = call.arguments.first?.leadingTrivia ?? []
				keptArguments.append(LabeledExprSyntax(leadingTrivia: leading.isEmpty ? [] : leading, label: .identifier("safeDIOverrides"), colon: .colonToken(trailingTrivia: .space), expression: ExprSyntax(initCall)))
			}
		} else if let overridesArgument {
			keptArguments.append(overridesArgument)
		}

		return ExprSyntax(finish(rewritten, call: call, keptArguments: keptArguments))
	}

	func finish(_ rewritten: FunctionCallExprSyntax, call: FunctionCallExprSyntax, keptArguments: [LabeledExprSyntax]) -> FunctionCallExprSyntax {
		var rewritten = rewritten
		var keptArguments = keptArguments
		// Commas: every argument but the last keeps (or gains) one; the last keeps the original last argument's.
		let originalLastComma = call.arguments.last?.trailingComma
		let originalLastTrailing = call.arguments.last?.trailingTrivia ?? []
		for index in keptArguments.indices {
			if index < keptArguments.count - 1 {
				let nextStartsLine = keptArguments[index + 1].leadingTrivia.contains { if case .newlines = $0 { true } else { false } }
				if keptArguments[index].trailingComma == nil { keptArguments[index].trailingComma = .commaToken(trailingTrivia: nextStartsLine ? [] : .space) }
			} else {
				keptArguments[index].trailingComma = originalLastComma
				if originalLastComma == nil { keptArguments[index] = keptArguments[index].with(\.trailingTrivia, originalLastTrailing) }
			}
		}
		rewritten.arguments = LabeledExprListSyntax(keptArguments)
		if rewritten.leftParen == nil { rewritten.leftParen = .leftParenToken(); rewritten.rightParen = .rightParenToken() }
		return rewritten
	}

	/// The type an implicit member expression is read as, where syntax alone says it: a binding's type annotation, or
	/// the return type of the function or closure-free body that returns it.
	func contextualTypeName(of node: Syntax) -> String? {
		func stripped(_ type: TypeSyntax) -> String {
			if let optional = type.as(OptionalTypeSyntax.self) { return optional.wrappedType.trimmedDescription }
			if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return unwrapped.wrappedType.trimmedDescription }
			return type.trimmedDescription
		}
		guard let parent = node.parent else { return nil }
		if let initializer = parent.as(InitializerClauseSyntax.self), let binding = initializer.parent?.as(PatternBindingSyntax.self) {
			return binding.typeAnnotation.map { stripped($0.type) }
		}
		var returned: Syntax?
		if parent.is(ReturnStmtSyntax.self) {
			returned = parent
		} else if let item = parent.as(CodeBlockItemSyntax.self), let list = item.parent?.as(CodeBlockItemListSyntax.self), list.count == 1 {
			returned = Syntax(list)
		}
		var ancestor = returned?.parent
		while let current = ancestor {
			if current.is(ClosureExprSyntax.self) { return nil }
			if let function = current.as(FunctionDeclSyntax.self) { return function.signature.returnClause.map { stripped($0.type) } }
			ancestor = current.parent
		}
		return nil
	}

	func renamedCallee(_ callee: ExprSyntax, memberAccess: Bool) -> ExprSyntax {
		if memberAccess, let member = callee.as(MemberAccessExprSyntax.self) {
			return ExprSyntax(member.with(\.declName, member.declName.with(\.baseName, .identifier("fake", leadingTrivia: member.declName.baseName.leadingTrivia, trailingTrivia: member.declName.baseName.trailingTrivia))))
		}
		if let reference = callee.as(DeclReferenceExprSyntax.self) {
			return ExprSyntax(reference.with(\.baseName, .identifier("fake", leadingTrivia: reference.baseName.leadingTrivia, trailingTrivia: reference.baseName.trailingTrivia)))
		}
		return callee
	}
}

// MARK: - Driver

func swiftFiles(in directory: String) -> [String] {
	guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
	return enumerator.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted().map { "\(directory)/\($0)" }
}

var generatedDirectories = [String]()
var sourceDirectories = [String]()
var write = false
var diffOut: String?
var reportOut: String?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
	switch argument {
	case "--generated": generatedDirectories.append(arguments.next() ?? "")
	case "--sources": sourceDirectories.append(arguments.next() ?? "")
	case "--write": write = true
	case "--diff-out": diffOut = arguments.next()
	case "--report-json": reportOut = arguments.next()
	default: FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8)); exit(2)
	}
}

let marker = "// safedi-migrate-signature: "
var signatures = [String: [SignatureRecord]]()
for directory in generatedDirectories {
	for path in swiftFiles(in: directory) {
		guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
		for line in text.split(separator: "\n") {
			guard let range = line.range(of: marker) else { continue }
			let json = line[range.upperBound...]
			guard let record = try? JSONDecoder().decode(SignatureRecord.self, from: Data(json.utf8)) else {
				FileHandle.standardError.write(Data("bad record in \(path)\n".utf8)); continue
			}
			if !(signatures[record.type]?.contains { $0.parameters.map(\.label) == record.parameters.map(\.label) } ?? false) {
				signatures[record.type, default: []].append(record)
			}
		}
	}
}

let sourcePaths = sourceDirectories.flatMap(swiftFiles(in:))
let trees = sourcePaths.map { path in (path, Parser.parse(source: (try? String(contentsOfFile: path, encoding: .utf8)) ?? "")) }
let collector = HandWrittenMockCollector(viewMode: .sourceAccurate)
for (_, tree) in trees { collector.walk(tree) }

let report = Report()
var changedFiles = 0
for (path, tree) in trees {
	let rewriter = MigrationRewriter(signatures: signatures, handWritten: collector.types, report: report, fileName: path, tree: tree)
	let rewritten = rewriter.rewrite(tree)
	let before = tree.description
	let after = rewritten.description
	guard before != after else { continue }
	changedFiles += 1
	if write { try after.write(toFile: path, atomically: true, encoding: .utf8) }
	if let diffOut {
		let name = path.replacingOccurrences(of: "/", with: "__")
		try? FileManager.default.createDirectory(atPath: diffOut, withIntermediateDirectories: true)
		try before.write(toFile: "\(diffOut)/\(name).before", atomically: true, encoding: .utf8)
		try after.write(toFile: "\(diffOut)/\(name).after", atomically: true, encoding: .utf8)
	}
	// The rewrite must still parse.
	let reparsed = Parser.parse(source: after)
	if reparsed.hasError { print("PARSE ERROR after rewrite: \(path)") }
}

print("signatures: \(signatures.count) mocked types, files: \(sourcePaths.count), changed: \(changedFiles)")
for category in EditCategory.allCases {
	guard let count = report.counts[category] else { continue }
	print(String(format: "%6d  %@", count, category.rawValue))
	for site in report.sites[category] ?? [] where category.rawValue.hasPrefix("UNRESOLVED") || category.rawValue.hasPrefix("left alone") {
		print("          \(site)")
	}
}
if let reportOut {
	var json = [String: Int]()
	for (category, count) in report.counts { json[category.rawValue] = count }
	try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: reportOut))
}
