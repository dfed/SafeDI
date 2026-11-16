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

/// Whether the closures a caller's level functions return keep a level's values alive, read from the syntax of the
/// generated files, with no compile: a level's builder struct hands each member the struct of the values the seam bound
/// at that level, and the closure a member returns is kept as long as what it builds, so it must hold only the values
/// its fill reads, never the struct.
///
/// - A **level function** is a function, at any nesting, whose declared return type's last member type is
///   `__safeDI_Builder<…>`, and no parameter of which is a function type whose result names a scope enum. One that has
///   such a parameter is a **conversion function**, which a seam that still takes a closure over its enum calls to
///   build the case its closure takes: it is counted, not judged, since it captures an outer level's values on purpose.
/// - A **member closure** is a closure passed as a labeled argument (`__safeDI_noScope` aside) of an `.init(…)` call
///   whose nearest enclosing function declaration is a level function. It belongs to that function alone: a function
///   declared inside a level function is judged on its own.
/// - A **fill function** is a function of the same file whose return type is not a builder struct, whose first
///   parameter's type's last member ends in `_Values`, and which a member closure hands its parameter, whole, as that
///   first, unlabeled argument of a direct call.
///
/// Findings, each naming the function, the line and the member's label or the parameter:
/// 1. A closure or local function nested in a member closure's body refers to the member closure's parameter, by
///    member access or whole: reported once per member closure, at the first such reference. A reference counts only
///    when it resolves to that parameter, with no nearer declaration of the name between (a nested closure's or
///    function's parameter, a local `let` or `var`, a pattern binding).
/// 2. A member closure uses its parameter in its own body other than as the base of a member access, as the one
///    argument of a direct call of a member of a parameter of its level function whose type is a builder struct
///    (`up.<member>(values)`, the caller's struct for the same level), or as the first argument of a direct call of a fill
///    function.
/// 3. A level function takes a parameter whose type's last member ends in `_Values`.
///
/// A fill function is judged on its `_Values` parameter, which nothing nested in it may refer to (finding 1), and which
/// its own body may use only as the base of a member access (finding 2), each reported on the fill function.
///
/// What it misses: values kept by a conversion function or by the inline conversion a seam's body writes (no function),
/// by a builder that still takes a closure over its enum, by a hand-written builder, or reached through anything but a
/// `_Values` struct; a function that takes a `_Values` struct and that only a `switch` over an enum calls is neither
/// counted nor judged. The retention oracle, which runs the code, stays the gate; this check is its first signal, and the
/// only one in a run without compiles.
struct GraphFuzzerLevelFunctionCaptures: Equatable {
	/// Judges every file of `generatedFiles`, in the order of the files' names.
	init(generatedFiles: [String: String]) {
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where contents.contains(Self.builderStructName) {
			let tree = Parser.parse(source: contents)
			let file = FileJudgment(fileName: fileName, tree: tree)
			findings += file.findings
			levelFunctionCount += file.levelFunctionCount
			namedMemberClosureCount += file.namedMemberClosureCount
			conversionFunctionCount += file.conversionFunctionCount
			fillFunctionCount += file.fillFunctionCount
		}
	}

	init(findings: [Finding] = [], levelFunctionCount: Int = 0, namedMemberClosureCount: Int = 0, conversionFunctionCount: Int = 0, fillFunctionCount: Int = 0) {
		self.findings = findings
		self.levelFunctionCount = levelFunctionCount
		self.namedMemberClosureCount = namedMemberClosureCount
		self.conversionFunctionCount = conversionFunctionCount
		self.fillFunctionCount = fillFunctionCount
	}

	/// A closure that keeps a level's values, or a level function that takes them.
	struct Finding: Equatable, CustomStringConvertible {
		enum Kind: Equatable {
			/// Finding 1: a closure or local function nested in the judged closure or fill function refers to its parameter.
			case nestedReference
			/// Finding 2: the judged closure or fill function uses its parameter in its own body other than the check allows.
			case wholeUse
			/// Finding 3: a level function takes a level's values struct.
			case valuesParameter
		}

		let kind: Kind
		let fileName: String
		let line: Int
		/// The level function, or the fill function, the finding is on.
		let function: String
		/// The label of the member closure the finding is on, or `nil` for a finding on a fill function or on a level
		/// function's parameter.
		let member: String?
		/// The parameter that holds the level's values.
		let parameter: String

		var description: String {
			let owner = member.map { "member `\($0)` of level function `\(function)`" } ?? (kind == .valuesParameter ? "level function `\(function)`" : "fill function `\(function)`")
			return switch kind {
			case .nestedReference:
				"\(fileName):\(line): a closure or local function inside \(owner) refers to `\(parameter)`, which holds a level's values, so what it builds keeps them alive"
			case .wholeUse:
				"\(fileName):\(line): \(owner) uses `\(parameter)`, which holds a level's values, otherwise than to read a value from it\(member == nil ? "" : ", to hand it to the caller's member for the level, or to hand it to a fill function")"
			case .valuesParameter:
				"\(fileName):\(line): \(owner) takes `\(parameter)`, a level's values struct, so a closure it returns can keep them alive"
			}
		}
	}

	/// The findings, in the order of the files' names, then of the functions' positions in each file.
	private(set) var findings = [Finding]()
	/// The level functions.
	private(set) var levelFunctionCount = 0
	/// The member closures that name their parameter.
	private(set) var namedMemberClosureCount = 0
	/// The conversion functions, which are not judged.
	private(set) var conversionFunctionCount = 0
	/// The fill functions member closures hand their parameter to.
	private(set) var fillFunctionCount = 0

	static let builderStructName = "__safeDI_Builder"
	static let noScopeLabel = "__safeDI_noScope"
	static let valuesStructSuffix = "_Values"
	static let scopeEnumPrefixes = ["SafeDIScope_", "SafeDISendableScope_", "SafeDIMockScope_", "SafeDISendableMockScope_"]
}

/// The judgment of one generated file.
private struct FileJudgment {
	init(fileName: String, tree: SourceFileSyntax) {
		let collector = FunctionCollector(viewMode: .sourceAccurate)
		collector.walk(tree)
		let converter = SourceLocationConverter(fileName: fileName, tree: tree)
		func line(of node: some SyntaxProtocol) -> Int {
			node.startLocation(converter: converter).line
		}
		// Each finding with the position of the function it is on, so that the findings are in the order of the functions'
		// positions in the file, each function's in the order they are found.
		var findings = [(functionPosition: AbsolutePosition, finding: GraphFuzzerLevelFunctionCaptures.Finding)]()
		var fillFunctions = [FunctionDeclSyntax]()
		for function in collector.functions {
			switch Self.kind(of: function) {
			case .other:
				continue
			case .conversion:
				conversionFunctionCount += 1
			case .level:
				levelFunctionCount += 1
				let functionName = function.name.text
				for parameter in function.signature.parameterClause.parameters where Self.isValuesStruct(parameter.type) {
					findings.append((function.position, .init(kind: .valuesParameter, fileName: fileName, line: line(of: parameter), function: functionName, member: nil, parameter: Self.internalName(of: parameter))))
				}
				let builderStructParameters = Set(function.signature.parameterClause.parameters.filter { Self.isBuilderStruct($0.type) }.map(Self.internalName(of:)))
				for (label, closure) in Self.memberClosures(of: function) {
					guard let parameter = Self.namedParameter(of: closure) else { continue }
					namedMemberClosureCount += 1
					var reportedNestedReference = false
					for reference in Self.references(to: parameter, in: closure) {
						if reference.isNested {
							// Reported once per member closure, at the first reference.
							if !reportedNestedReference {
								reportedNestedReference = true
								findings.append((function.position, .init(kind: .nestedReference, fileName: fileName, line: line(of: reference.node), function: functionName, member: label, parameter: parameter)))
							}
						} else if Self.isBaseOfMemberAccess(reference.node) || Self.isSoleArgumentOfBuilderStructMember(reference.node, builderStructParameters: builderStructParameters) {
							continue
						} else if let fillFunction = Self.fillFunction(calledWithFirstArgument: reference.node, among: collector.functions) {
							if !fillFunctions.contains(where: { $0.id == fillFunction.id }) {
								fillFunctions.append(fillFunction)
							}
						} else {
							findings.append((function.position, .init(kind: .wholeUse, fileName: fileName, line: line(of: reference.node), function: functionName, member: label, parameter: parameter)))
						}
					}
				}
			}
		}
		fillFunctionCount = fillFunctions.count
		// Each fill function on its `_Values` parameter.
		for fillFunction in fillFunctions {
			guard let valuesParameter = fillFunction.signature.parameterClause.parameters.first else { continue }
			let parameter = Self.internalName(of: valuesParameter)
			var reportedNestedReference = false
			for reference in Self.references(to: parameter, in: fillFunction) {
				if reference.isNested {
					if !reportedNestedReference {
						reportedNestedReference = true
						findings.append((fillFunction.position, .init(kind: .nestedReference, fileName: fileName, line: line(of: reference.node), function: fillFunction.name.text, member: nil, parameter: parameter)))
					}
				} else if !Self.isBaseOfMemberAccess(reference.node) {
					findings.append((fillFunction.position, .init(kind: .wholeUse, fileName: fileName, line: line(of: reference.node), function: fillFunction.name.text, member: nil, parameter: parameter)))
				}
			}
		}
		// Stable: a function's findings keep the order they were found in.
		self.findings = findings.enumerated()
			.sorted { ($0.element.functionPosition.utf8Offset, $0.offset) < ($1.element.functionPosition.utf8Offset, $1.offset) }
			.map(\.element.finding)
	}

	private(set) var findings = [GraphFuzzerLevelFunctionCaptures.Finding]()
	private(set) var levelFunctionCount = 0
	private(set) var namedMemberClosureCount = 0
	private(set) var conversionFunctionCount = 0
	private(set) var fillFunctionCount = 0

	private enum FunctionKind {
		case level
		case conversion
		case other
	}

	private static func kind(of function: FunctionDeclSyntax) -> FunctionKind {
		guard let returnType = function.signature.returnClause?.type, isBuilderStruct(returnType) else { return .other }
		let takesConversion = function.signature.parameterClause.parameters.contains { parameter in
			guard let functionType = unattributed(parameter.type).as(FunctionTypeSyntax.self) else { return false }
			return functionType.returnClause.type.tokens(viewMode: .sourceAccurate).contains { token in
				GraphFuzzerLevelFunctionCaptures.scopeEnumPrefixes.contains { token.text.hasPrefix($0) }
			}
		}
		return takesConversion ? .conversion : .level
	}

	/// `type` without the attributes and specifiers written before it (`@escaping`, `@Sendable`, `inout`).
	private static func unattributed(_ type: TypeSyntax) -> TypeSyntax {
		type.as(AttributedTypeSyntax.self).map { unattributed($0.baseType) } ?? type
	}

	/// The name of `type`'s last member type: `__safeDI_Builder` of `Home.SafeDIScope_Api.__safeDI_Builder<any Api>`.
	private static func lastMemberName(of type: TypeSyntax) -> String? {
		let type = unattributed(type)
		if let memberType = type.as(MemberTypeSyntax.self) {
			return memberType.name.text
		} else if let identifierType = type.as(IdentifierTypeSyntax.self) {
			return identifierType.name.text
		} else {
			return nil
		}
	}

	private static func isBuilderStruct(_ type: TypeSyntax) -> Bool {
		lastMemberName(of: type) == GraphFuzzerLevelFunctionCaptures.builderStructName
	}

	private static func isValuesStruct(_ type: TypeSyntax) -> Bool {
		lastMemberName(of: type)?.hasSuffix(GraphFuzzerLevelFunctionCaptures.valuesStructSuffix) == true
	}

	/// The name a parameter is referred to by in the function's body.
	private static func internalName(of parameter: FunctionParameterSyntax) -> String {
		(parameter.secondName ?? parameter.firstName).text
	}

	/// The member closures of `function`, labeled, in source order: closures passed as labeled arguments of an `.init(…)`
	/// call whose nearest enclosing function declaration is `function`.
	private static func memberClosures(of function: FunctionDeclSyntax) -> [(label: String, closure: ClosureExprSyntax)] {
		guard let body = function.body else { return [] }
		let collector = MemberClosureCollector(viewMode: .sourceAccurate)
		collector.walk(body)
		return collector.memberClosures
	}

	/// The name of `closure`'s one parameter, or `nil` when it names none (`_`, or no signature).
	private static func namedParameter(of closure: ClosureExprSyntax) -> String? {
		let names: [String] = switch closure.signature?.parameterClause {
		case let .simpleInput(parameters)?:
			parameters.map(\.name.text)
		case let .parameterClause(clause)?:
			clause.parameters.map { ($0.secondName ?? $0.firstName).text }
		case nil:
			[]
		}
		return names.first.flatMap { $0 == "_" ? nil : $0 }
	}

	/// A reference to the judged parameter, and whether a closure or a local function lies between it and the judged
	/// closure or function.
	private struct Reference {
		let node: DeclReferenceExprSyntax
		let isNested: Bool
	}

	/// Every reference in `root`'s body, in source order, that resolves to `root`'s own parameter `name`.
	private static func references(to name: String, in root: some SyntaxProtocol) -> [Reference] {
		let collector = ReferenceCollector(name: name, viewMode: .sourceAccurate)
		let body: Syntax? = if let closure = root.as(ClosureExprSyntax.self) {
			Syntax(closure.statements)
		} else if let function = root.as(FunctionDeclSyntax.self) {
			function.body.map { Syntax($0) }
		} else {
			nil
		}
		guard let body else { return [] }
		collector.walk(body)
		return collector.references.compactMap { reference in
			resolution(of: reference, named: name, judgedRoot: Syntax(root)).map { Reference(node: reference, isNested: $0) }
		}
	}

	/// Whether `reference` is nested in a closure or local function inside `judgedRoot`, or `nil` when a nearer declaration
	/// of `name` than `judgedRoot`'s parameter is what it refers to.
	private static func resolution(of reference: DeclReferenceExprSyntax, named name: String, judgedRoot: Syntax) -> Bool? {
		var isNested = false
		var child = Syntax(reference)
		while let parent = child.parent, parent.id != judgedRoot.id {
			if let closure = parent.as(ClosureExprSyntax.self) {
				if closureDeclares(closure, name) {
					return nil
				}
				isNested = true
			} else if let function = parent.as(FunctionDeclSyntax.self) {
				if function.signature.parameterClause.parameters.contains(where: { internalName(of: $0) == name }) {
					return nil
				}
				isNested = true
			} else if let items = parent.as(CodeBlockItemListSyntax.self) {
				// A declaration in the same block before the statement that holds the reference.
				for item in items {
					guard item.position < child.position else { break }
					if itemDeclares(item, name) {
						return nil
					}
				}
			} else if let switchCase = parent.as(SwitchCaseSyntax.self), child.id == switchCase.statements.id {
				if case let .case(label) = switchCase.label, label.caseItems.contains(where: { patternBinds($0.pattern, name) }) {
					return nil
				}
			} else if let ifExpression = parent.as(IfExprSyntax.self), child.id == ifExpression.body.id {
				if conditionsBind(ifExpression.conditions, name) {
					return nil
				}
			} else if let whileStatement = parent.as(WhileStmtSyntax.self), child.id == whileStatement.body.id {
				if conditionsBind(whileStatement.conditions, name) {
					return nil
				}
			} else if let forStatement = parent.as(ForStmtSyntax.self), child.id == forStatement.body.id, patternBinds(forStatement.pattern, name) {
				return nil
			}
			child = parent
		}
		return isNested
	}

	private static func closureDeclares(_ closure: ClosureExprSyntax, _ name: String) -> Bool {
		switch closure.signature?.parameterClause {
		case let .simpleInput(parameters)?:
			parameters.contains { $0.name.text == name }
		case let .parameterClause(clause)?:
			clause.parameters.contains { ($0.secondName ?? $0.firstName).text == name }
		case nil:
			false
		}
	}

	/// Whether the statement `item` declares `name` for the statements after it: a `let` or `var`, a `guard` binding, or a
	/// local function of that name.
	private static func itemDeclares(_ item: CodeBlockItemSyntax, _ name: String) -> Bool {
		if let variable = item.item.as(VariableDeclSyntax.self) {
			variable.bindings.contains { patternBinds($0.pattern, name) }
		} else if let guardStatement = item.item.as(GuardStmtSyntax.self) {
			conditionsBind(guardStatement.conditions, name)
		} else if let function = item.item.as(FunctionDeclSyntax.self) {
			function.name.text == name
		} else {
			false
		}
	}

	private static func conditionsBind(_ conditions: ConditionElementListSyntax, _ name: String) -> Bool {
		conditions.contains { condition in
			if let binding = condition.condition.as(OptionalBindingConditionSyntax.self) {
				patternBinds(binding.pattern, name)
			} else if let matching = condition.condition.as(MatchingPatternConditionSyntax.self) {
				patternBinds(matching.pattern, name)
			} else {
				false
			}
		}
	}

	/// Whether `pattern` binds `name`, at any depth: `x`, `let x`, `(x, y)`, `.case(let x)`.
	private static func patternBinds(_ pattern: some SyntaxProtocol, _ name: String) -> Bool {
		if let identifier = pattern.as(IdentifierPatternSyntax.self) {
			return identifier.identifier.text == name
		}
		// A binding in an enum case pattern is an expression pattern holding a pattern expression.
		if let patternExpression = pattern.as(PatternExprSyntax.self) {
			return patternBinds(patternExpression.pattern, name)
		}
		return pattern.children(viewMode: .sourceAccurate).contains { patternBinds($0, name) }
	}

	private static func isBaseOfMemberAccess(_ reference: DeclReferenceExprSyntax) -> Bool {
		guard let memberAccess = reference.parent?.as(MemberAccessExprSyntax.self) else { return false }
		return memberAccess.base?.id == Syntax(reference).id
	}

	/// Whether `reference` is the one argument of a direct call of a member of one of `builderStructParameters`
	/// (`up.<member>(values)`): the caller's struct for the same level.
	private static func isSoleArgumentOfBuilderStructMember(_ reference: DeclReferenceExprSyntax, builderStructParameters: Set<String>) -> Bool {
		guard let argument = reference.parent?.as(LabeledExprSyntax.self), argument.label == nil,
		      let arguments = argument.parent?.as(LabeledExprListSyntax.self), arguments.count == 1,
		      let call = arguments.parent?.as(FunctionCallExprSyntax.self), call.trailingClosure == nil,
		      let member = call.calledExpression.as(MemberAccessExprSyntax.self),
		      let base = member.base?.as(DeclReferenceExprSyntax.self)
		else { return false }
		return builderStructParameters.contains(base.baseName.text)
	}

	/// The fill function `reference` is the first, unlabeled argument of a direct call of, or `nil`.
	private static func fillFunction(calledWithFirstArgument reference: DeclReferenceExprSyntax, among functions: [FunctionDeclSyntax]) -> FunctionDeclSyntax? {
		guard let argument = reference.parent?.as(LabeledExprSyntax.self), argument.label == nil,
		      let arguments = argument.parent?.as(LabeledExprListSyntax.self), arguments.first?.id == argument.id,
		      let call = arguments.parent?.as(FunctionCallExprSyntax.self),
		      let callee = call.calledExpression.as(DeclReferenceExprSyntax.self)
		else { return nil }
		return functions.first { function in
			guard function.name.text == callee.baseName.text,
			      let firstParameter = function.signature.parameterClause.parameters.first,
			      firstParameter.firstName.tokenKind == .wildcard,
			      isValuesStruct(firstParameter.type)
			else { return false }
			return function.signature.returnClause.map { !isBuilderStruct($0.type) } ?? true
		}
	}
}

/// Every function declaration of a file, at any nesting, in source order.
private final class FunctionCollector: SyntaxVisitor {
	private(set) var functions = [FunctionDeclSyntax]()

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		functions.append(node)
		return .visitChildren
	}
}

/// The member closures in a level function's body: closures passed as labeled arguments of `.init(…)` calls, outside
/// every function declared in the body.
private final class MemberClosureCollector: SyntaxVisitor {
	private(set) var memberClosures = [(label: String, closure: ClosureExprSyntax)]()

	override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		// A function declared inside a level function is judged on its own.
		.skipChildren
	}

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self), memberAccess.base == nil, memberAccess.declName.baseName.text == "init" {
			for argument in node.arguments {
				guard let label = argument.label?.text, label != GraphFuzzerLevelFunctionCaptures.noScopeLabel,
				      let closure = argument.expression.as(ClosureExprSyntax.self)
				else { continue }
				memberClosures.append((label, closure))
			}
		}
		return .visitChildren
	}
}

/// Every reference to a value named `name`: a name read in an expression, not a member's name after a dot.
private final class ReferenceCollector: SyntaxVisitor {
	init(name: String, viewMode: SyntaxTreeViewMode) {
		self.name = name
		super.init(viewMode: viewMode)
	}

	private let name: String
	private(set) var references = [DeclReferenceExprSyntax]()

	override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
		let isMemberName = node.parent?.as(MemberAccessExprSyntax.self)?.declName.id == node.id
		if node.baseName.text == name, !isMemberName {
			references.append(node)
		}
		return .visitChildren
	}
}

/// What the level function capture check judged (`GraphFuzzerLevelFunctionCaptures`), of one graph or added up over a
/// corpus, which each corpus pins (`level-captures` in the long run's report): a change that judges fewer graphs, or
/// stops reaching fill functions, fails the pin.
struct GraphFuzzerLevelFunctionCaptureCounts: Equatable {
	/// The graphs with a level function.
	var judged = 0
	/// The judged graphs with a member closure that names its parameter.
	var judgedWithNamed = 0
	/// The member closures that name their parameter, over every graph.
	var named = 0
	/// The conversion functions, over every graph: counted, not judged.
	var conversions = 0
	/// The fill functions member closures hand their parameter to, over every graph.
	var fills = 0

	init(judged: Int = 0, judgedWithNamed: Int = 0, named: Int = 0, conversions: Int = 0, fills: Int = 0) {
		self.judged = judged
		self.judgedWithNamed = judgedWithNamed
		self.named = named
		self.conversions = conversions
		self.fills = fills
	}

	/// The counts of one graph the check judged.
	init(_ captures: GraphFuzzerLevelFunctionCaptures) {
		self.init(
			judged: captures.levelFunctionCount > 0 ? 1 : 0,
			judgedWithNamed: captures.levelFunctionCount > 0 && captures.namedMemberClosureCount > 0 ? 1 : 0,
			named: captures.namedMemberClosureCount,
			conversions: captures.conversionFunctionCount,
			fills: captures.fillFunctionCount,
		)
	}

	/// The counts as the long run's report and `combine-graph-fuzzer-reports.py` write them.
	var reportField: String {
		"judged=\(judged),judgedWithNamed=\(judgedWithNamed),named=\(named),conversions=\(conversions),fills=\(fills)"
	}

	mutating func add(_ other: GraphFuzzerLevelFunctionCaptureCounts) {
		judged += other.judged
		judgedWithNamed += other.judgedWithNamed
		named += other.named
		conversions += other.conversions
		fills += other.fills
	}
}
