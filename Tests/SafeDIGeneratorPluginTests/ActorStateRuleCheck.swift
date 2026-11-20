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

/// The rule that no `async` function of an actor under `Sources/SafeDICore`, an `async` accessor included, assigns a
/// stored property of that actor. A memo an actor fills by checking and then setting a property is sound only while
/// nothing suspends between the check and the set; once the computation awaits, two callers can both find it empty, both
/// compute, and the later one wins. So a value computed once is a local of the call that computes it, handed down, and
/// never a property of the actor. A synchronous function cannot suspend between a check and a set, so the rule leaves it
/// alone; and it cannot see an `async` function that awaits and then calls a synchronous function that sets a property,
/// so it is a tripwire for the common shape, and the tests that count each layer of a run's work are the guard. Matched by
/// what an assignment assigns, never by a property's name. No waiver is offered.
enum ActorStateRuleCheck {
	/// The actors under `Sources/SafeDICore` the rule does not cover yet, each with the reason.
	static let actorsNotYetCovered = [
		"ScopeGenerator": "its code memo, which `generateCode` fills, goes when production output is rewritten, and its mock parameter tree task, which an `async` getter sets, goes when mock output is",
	]

	/// The actors `files` declare under `Sources/SafeDICore` that the rule covers, by name, each with the names of its
	/// stored properties that are not `static`.
	static func coveredActors(in files: [RepositorySwiftFile]) -> [String: Set<String>] {
		var actors = [String: Set<String>]()
		for file in files where file.path.hasPrefix("Sources/SafeDICore/") {
			let visitor = ActorDeclarationVisitor(viewMode: .sourceAccurate)
			visitor.walk(Parser.parse(source: file.source))
			for (name, storedProperties) in visitor.storedPropertiesByActor where actorsNotYetCovered[name] == nil {
				actors[name, default: []].formUnion(storedProperties)
			}
		}
		return actors
	}

	/// Each site in `files` where an `async` function of an actor the rule covers, declared in the actor or in an extension
	/// of it, assigns a stored property of the actor, as `<path>:<line>: <message>`, in path and line order.
	static func findings(in files: [RepositorySwiftFile]) -> [String] {
		let actors = coveredActors(in: files)
		var findings = [String]()
		for file in files where file.path.hasPrefix("Sources/SafeDICore/") {
			let tree = Parser.parse(source: file.source)
			let visitor = AsyncAssignmentVisitor(actors: actors, converter: SourceLocationConverter(fileName: file.path, tree: tree))
			visitor.walk(tree)
			findings += visitor.sites.map { "\(file.path):\($0.line): an `async` function of actor `\($0.actor)` assigns its stored property `\($0.property)`" }
		}
		return findings
	}
}

/// Finds each actor a file declares, with the names of its stored properties that are not `static`.
private final class ActorDeclarationVisitor: SyntaxVisitor {
	private(set) var storedPropertiesByActor = [String: Set<String>]()

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		var storedProperties = Set<String>()
		for member in node.memberBlock.members {
			guard let variable = member.decl.as(VariableDeclSyntax.self),
			      !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) })
			else { continue }
			for binding in variable.bindings where Self.isStored(binding) {
				if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
					storedProperties.insert(name)
				}
			}
		}
		storedPropertiesByActor[node.name.text, default: []].formUnion(storedProperties)
		return .visitChildren
	}

	/// Whether `binding` declares a stored property: one with no accessors, or only observers.
	private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
		guard let accessorBlock = binding.accessorBlock else { return true }
		switch accessorBlock.accessors {
		case let .accessors(accessors):
			return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
		case .getter:
			return false
		}
	}
}

/// Finds each assignment, in an `async` function of an actor the rule covers, of a stored property of that actor.
private final class AsyncAssignmentVisitor: SyntaxVisitor {
	init(actors: [String: Set<String>], converter: SourceLocationConverter) {
		self.actors = actors
		self.converter = converter
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var sites = [(line: Int, actor: String, property: String)]()

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		if node.signature.effectSpecifiers?.asyncSpecifier != nil, let body = node.body {
			check(body, of: node)
		}
		return .visitChildren
	}

	override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
		if node.effectSpecifiers?.asyncSpecifier != nil, let body = node.body {
			check(body, of: node)
		}
		return .visitChildren
	}

	// MARK: Private

	private let actors: [String: Set<String>]
	private let converter: SourceLocationConverter

	/// Records each assignment in `body`, the body of `function`, of a stored property of the actor that `function` is
	/// declared in or in an extension of.
	private func check(_ body: some SyntaxProtocol, of function: some SyntaxProtocol) {
		guard let actor = Self.enclosingActorName(of: function), let storedProperties = actors[actor] else { return }
		let assignments = AssignmentVisitor(viewMode: .sourceAccurate)
		assignments.walk(body)
		for target in assignments.targets {
			let property: String? = switch target.root {
			case let .member(name):
				name
			case let .name(name):
				LocalNames.isDeclared(name, inScopeAt: target.node) ? nil : name
			}
			if let property, storedProperties.contains(property) {
				sites.append((line: converter.location(for: target.node.positionAfterSkippingLeadingTrivia).line, actor: actor, property: property))
			}
		}
	}

	/// The name of the actor whose declaration or extension directly holds `function`, or `nil` when another type or
	/// none does.
	private static func enclosingActorName(of function: some SyntaxProtocol) -> String? {
		var ancestor = function.parent
		while let node = ancestor {
			if let actor = node.as(ActorDeclSyntax.self) {
				return actor.name.text
			} else if let extensionDeclaration = node.as(ExtensionDeclSyntax.self) {
				return extensionDeclaration.extendedType.trimmedDescription.split(separator: ".").last.map(String.init)
			} else if node.is(StructDeclSyntax.self) || node.is(ClassDeclSyntax.self) || node.is(EnumDeclSyntax.self) || node.is(ProtocolDeclSyntax.self) {
				return nil
			} else {
				ancestor = node.parent
			}
		}
		return nil
	}
}

/// Which names a declaration in scope binds where a name is assigned: a parameter of an enclosing function or closure, a
/// `let` or `var` or a `guard` condition in an enclosing block before the assignment, a condition of an enclosing `if` or
/// `while` whose body holds it, the pattern of an enclosing `for` loop, `case` or `catch`. A name none of them binds is the
/// actor's own.
private enum LocalNames {
	/// Whether a declaration in scope at `node` binds `name`.
	static func isDeclared(_ name: String, inScopeAt node: Syntax) -> Bool {
		var child = node
		var ancestor = node.parent
		while let current = ancestor {
			if let statements = current.as(CodeBlockItemListSyntax.self) {
				for statement in statements where statement.endPosition <= child.position && declares(name, in: statement) {
					return true
				}
			} else if let ifExpression = current.as(IfExprSyntax.self), Syntax(ifExpression.body).id == child.id, binds(name, in: ifExpression.conditions) {
				return true
			} else if let whileStatement = current.as(WhileStmtSyntax.self), Syntax(whileStatement.body).id == child.id, binds(name, in: whileStatement.conditions) {
				return true
			} else if let forStatement = current.as(ForStmtSyntax.self), Syntax(forStatement.body).id == child.id, binds(name, in: forStatement.pattern) {
				return true
			} else if let switchCase = current.as(SwitchCaseSyntax.self), binds(name, in: switchCase.label) {
				return true
			} else if let catchClause = current.as(CatchClauseSyntax.self), binds(name, in: catchClause.catchItems) {
				return true
			} else if let closure = current.as(ClosureExprSyntax.self), let signature = closure.signature, binds(name, in: signature) {
				return true
			} else if let function = current.as(FunctionDeclSyntax.self), function.signature.parameterClause.parameters.contains(where: { ($0.secondName ?? $0.firstName).text == name }) {
				return true
			}
			child = current
			ancestor = current.parent
		}
		return false
	}

	/// Whether `statement`, before an assignment in its block, declares `name` for what follows it: a `let` or `var`, or a
	/// `guard` condition. An `if` condition's names are in scope in its body alone.
	private static func declares(_ name: String, in statement: CodeBlockItemSyntax) -> Bool {
		if let variable = statement.item.as(VariableDeclSyntax.self) {
			variable.bindings.contains { binds(name, in: $0.pattern) }
		} else if let guardStatement = statement.item.as(GuardStmtSyntax.self) {
			binds(name, in: guardStatement.conditions)
		} else {
			false
		}
	}

	/// Whether `node` binds `name`: a pattern, or a closure's parameter.
	private static func binds(_ name: String, in node: some SyntaxProtocol) -> Bool {
		let visitor = BindingVisitor(name: name)
		visitor.walk(node)
		return visitor.binds
	}

	private final class BindingVisitor: SyntaxVisitor {
		init(name: String) {
			self.name = name
			super.init(viewMode: .sourceAccurate)
		}

		private(set) var binds = false

		override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
			binds = binds || node.identifier.text == name
			return .skipChildren
		}

		override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
			binds = binds || node.name.text == name
			return .skipChildren
		}

		override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
			binds = binds || (node.secondName ?? node.firstName).text == name
			return .skipChildren
		}

		// What a nested closure or function declares, and what a statement's own body declares, is not in scope after it.
		override func visit(_: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
			.skipChildren
		}

		override func visit(_: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
			.skipChildren
		}

		override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			.skipChildren
		}

		private let name: String
	}
}

/// What each assignment in a body assigns: `=` and each compound assignment such as `+=`, with the name at the root of
/// what it assigns to.
private final class AssignmentVisitor: SyntaxVisitor {
	/// The root of an assignment's target: a member of `self`, such as `x` in `self.x[key] = value`, or a bare name, such
	/// as `x` in `x.y = value`.
	enum Root {
		case member(String)
		case name(String)
	}

	private(set) var targets = [(root: Root, node: Syntax)]()

	override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
		let elements = Array(node.elements)
		for (index, element) in elements.enumerated() where index > 0 && Self.isAssignment(element) {
			for root in Self.roots(of: elements[index - 1]) {
				targets.append((root: root, node: Syntax(elements[index - 1])))
			}
		}
		return .visitChildren
	}

	// MARK: Private

	private static func isAssignment(_ element: ExprSyntax) -> Bool {
		if element.is(AssignmentExprSyntax.self) {
			return true
		} else if let binaryOperator = element.as(BinaryOperatorExprSyntax.self) {
			let text = binaryOperator.operator.text
			return text.hasSuffix("=") && !["==", "!=", "<=", ">=", "===", "!=="].contains(text)
		} else {
			return false
		}
	}

	/// The roots of what `target` assigns to: one, or one for each element of a tuple.
	private static func roots(of target: ExprSyntax) -> [Root] {
		if let tuple = target.as(TupleExprSyntax.self) {
			tuple.elements.flatMap { roots(of: $0.expression) }
		} else if let memberAccess = target.as(MemberAccessExprSyntax.self) {
			if let base = memberAccess.base, base.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
				[.member(memberAccess.declName.baseName.text)]
			} else {
				memberAccess.base.map(roots(of:)) ?? []
			}
		} else if let subscriptCall = target.as(SubscriptCallExprSyntax.self) {
			roots(of: subscriptCall.calledExpression)
		} else if let forceUnwrap = target.as(ForceUnwrapExprSyntax.self) {
			roots(of: forceUnwrap.expression)
		} else if let optionalChaining = target.as(OptionalChainingExprSyntax.self) {
			roots(of: optionalChaining.expression)
		} else if let reference = target.as(DeclReferenceExprSyntax.self) {
			[.name(reference.baseName.text)]
		} else {
			[]
		}
	}
}
