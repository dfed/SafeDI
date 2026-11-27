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
import SafeDIToolLibrary
import SwiftParser
import SwiftSyntax

/// What each receive is handed, by `query graph`'s export and by generated code, which the query oracle compares
/// (`GraphFuzzerToolRuns.querySuppliersFailure`). Each receive is named `<type>.<label>`, by the type's name, and each
/// value it is handed `<type>.<label>`, the declaration that supplies it, or `nil`.
struct GraphFuzzerQuerySupplies: Equatable {
	/// The values each receive is handed.
	var valuesByReceive = [String: Set<String>]()
	/// Each read the generated code makes that the oracle cannot follow to a declaration, in file order.
	var unreadable = [String]()

	/// What `query graph`'s export, `json`, says each receive is handed, or `nil` when its trees were not built.
	init?(exportedJSON json: String) throws {
		guard let export = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
		      export["completeness"] as? String == "trees",
		      let declarations = export["declarations"] as? [[String: Any]]
		else { return nil }
		var nameByID = [String: String]()
		for declaration in declarations {
			if let id = declaration["id"] as? String, let name = declaration["typeName"] as? String {
				nameByID[id] = name
			}
		}
		for declaration in declarations {
			guard let name = declaration["typeName"] as? String, let dependencies = declaration["dependencies"] as? [[String: Any]] else { continue }
			for dependency in dependencies {
				guard let label = dependency["label"] as? String, let provenance = dependency["provenance"] as? [[String: Any]] else { continue }
				valuesByReceive["\(name).\(label)"] = Set(provenance.map { entry in
					if entry["source"] as? String == "declaration" {
						"\(nameByID[entry["declaredBy"] as? String ?? ""] ?? "?").\(entry["label"] as? String ?? "?")"
					} else {
						"nil"
					}
				})
			}
		}
	}

	/// What the production code among `generatedFiles` hands each receive of the types `kindsByLabelByType` describes –
	/// each type's dependencies' kinds by label, as `kindsByLabelByType(exportedJSON:)` names them – read from the code's
	/// syntax as Swift resolves each name: the nearest declaration in scope where the receive's type is constructed.
	init(generatedFiles: [String: String], kindsByLabelByType: [String: [String: String]]) {
		for (fileName, contents) in generatedFiles.sorted(by: { $0.key < $1.key }) where !fileName.contains("Mock") {
			let reader = GeneratedCodeSupplyReader(kindsByLabelByType: kindsByLabelByType, fileName: fileName)
			reader.walk(Parser.parse(source: contents))
			for (receive, values) in reader.valuesByReceive {
				valuesByReceive[receive, default: []].formUnion(values)
			}
			unreadable += reader.unreadable
		}
	}

	/// Each type's dependencies' kinds by label, read from `query graph`'s export, `json`: `instantiated`, `lazy` or
	/// `builder` for an instantiated dependency by its lifetime, `forwarded`, `alias` for a received dependency that
	/// renames another, and `received`.
	static func kindsByLabelByType(exportedJSON json: String) throws -> [String: [String: String]] {
		guard let export = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
		      let declarations = export["declarations"] as? [[String: Any]]
		else { return [:] }
		var kindsByLabelByType = [String: [String: String]]()
		for declaration in declarations {
			guard let name = declaration["typeName"] as? String, let dependencies = declaration["dependencies"] as? [[String: Any]] else { continue }
			for dependency in dependencies {
				guard let label = dependency["label"] as? String, let source = dependency["source"] as? String else { continue }
				let kind = switch source {
				case "instantiated":
					dependency["lifetime"] as? String == "eager" ? "instantiated" : dependency["lifetime"] as? String ?? "?"
				case "received":
					dependency["aliasOf"] == nil ? "received" : "alias"
				default:
					source
				}
				kindsByLabelByType[name, default: [:]][label] = kind
			}
		}
		return kindsByLabelByType
	}

	/// The receives whose values differ between `self` and `other`, each with both sets, in name order.
	func differences(from other: Self) -> [String] {
		Set(valuesByReceive.keys).union(other.valuesByReceive.keys).sorted().compactMap { receive in
			let values = valuesByReceive[receive] ?? []
			let otherValues = other.valuesByReceive[receive] ?? []
			return values == otherValues ? nil : "\(receive): \(values.sorted()) against \(otherValues.sorted())"
		}
	}
}

/// Reads one generated file: each construction of a type the oracle knows, and, for each argument of a received or
/// aliased dependency, the declaration Swift resolves the argument's name to, followed through renames and the
/// parameters of builder functions a lazy cycle closes on to the declaration that supplies it.
private final class GeneratedCodeSupplyReader: SyntaxVisitor {
	init(kindsByLabelByType: [String: [String: String]], fileName: String) {
		self.kindsByLabelByType = kindsByLabelByType
		self.fileName = fileName
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var valuesByReceive = [String: Set<String>]()
	private(set) var unreadable = [String]()

	override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
		// Mock code is compiled only under its condition.
		node.condition?.trimmedDescription == "DEBUG" ? .skipChildren : .visitChildren
	}

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		guard let typeName = constructedTypeName(of: node).flatMap(knownTypeName(spelled:)), let kindsByLabel = kindsByLabelByType[typeName] else { return .visitChildren }
		for argument in node.arguments {
			guard let label = argument.label?.text, let kind = kindsByLabel[label], kind == "received" || kind == "alias" else { continue }
			var values = Set<String>()
			var visitedFunctions = Set<SyntaxIdentifier>()
			resolve(argument.expression, receive: (typeName, label), into: &values, visitedFunctions: &visitedFunctions)
			valuesByReceive["\(typeName).\(label)", default: []].formUnion(values)
		}
		return .visitChildren
	}

	// MARK: Private

	private let kindsByLabelByType: [String: [String: String]]
	private let fileName: String

	/// The type a call constructs: `T(…)`, `T.instantiate(…)`, or a root's `self.init(…)`.
	private func constructedTypeName(of call: FunctionCallExprSyntax) -> String? {
		if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
			return reference.baseName.text
		} else if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
			if memberAccess.declName.baseName.text == "instantiate", let base = memberAccess.base {
				return base.trimmedDescription
			} else if memberAccess.declName.baseName.tokenKind == .keyword(.`init`), memberAccess.base?.trimmedDescription == "self" {
				return extendedTypeName(enclosing: Syntax(call))
			} else {
				// A nested type, qualified by the types that enclose it.
				return memberAccess.trimmedDescription
			}
		}
		return nil
	}

	/// The name the export gives the type generated code spells `spelling`: the same name, or the one qualified name
	/// that ends in it, as code inside an enclosing type spells a nested type.
	private func knownTypeName(spelled spelling: String) -> String? {
		if kindsByLabelByType[spelling] != nil {
			return spelling
		}
		let qualified = kindsByLabelByType.keys.filter { $0.hasSuffix(".\(spelling)") }
		return qualified.count == 1 ? qualified.first : nil
	}

	private func extendedTypeName(enclosing node: Syntax) -> String? {
		var current = node.parent
		while let node = current {
			if let extensionDeclaration = node.as(ExtensionDeclSyntax.self) {
				return extensionDeclaration.extendedType.trimmedDescription
			}
			current = node.parent
		}
		return nil
	}

	/// The type whose declarations the code block `node` is in makes: the type a builder function returns, or the type
	/// whose `init` it is in.
	private func frameTypeName(enclosing node: Syntax) -> (name: String, function: Syntax)? {
		var current = node.parent
		while let node = current {
			if let function = node.as(FunctionDeclSyntax.self) {
				let returnType = function.signature.returnClause?.type.trimmedDescription ?? ""
				let spelling = returnType.hasPrefix("any ") ? String(returnType.dropFirst(4)) : returnType
				return (knownTypeName(spelled: spelling) ?? spelling, node)
			} else if node.is(InitializerDeclSyntax.self) {
				return extendedTypeName(enclosing: node).map { (knownTypeName(spelled: $0) ?? $0, node) }
			}
			current = node.parent
		}
		return nil
	}

	private enum Declaration {
		case variable(PatternBindingSyntax, VariableDeclSyntax)
		case parameter(label: String, FunctionDeclSyntax)
		case other(Syntax)
	}

	/// The declaration of `name` Swift resolves a use at `node` to: the nearest one in an enclosing scope, declared
	/// before the use in its code block, or a parameter of an enclosing function or closure.
	/// - Parameter anywhereInBlocks: Whether a variable declared after the use in its code block counts too.
	private func declaration(of name: String, at node: Syntax, anywhereInBlocks: Bool = false) -> Declaration? {
		var child = node
		var current = node.parent
		while let node = current {
			if let items = node.as(CodeBlockItemListSyntax.self) {
				var candidates = [CodeBlockItemSyntax]()
				for item in items {
					if item.id == child.id {
						if !anywhereInBlocks {
							break
						} else {
							continue
						}
					}
					candidates.append(item)
				}
				for item in candidates.reversed() {
					if let variable = item.item.as(VariableDeclSyntax.self) {
						for binding in variable.bindings where binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name {
							return .variable(binding, variable)
						}
					}
				}
			} else if let function = node.as(FunctionDeclSyntax.self) {
				for parameter in function.signature.parameterClause.parameters where (parameter.secondName ?? parameter.firstName).text == name {
					return .parameter(label: parameter.firstName.text, function)
				}
			} else if let closure = node.as(ClosureExprSyntax.self), let signature = closure.signature, signature.trimmedDescription.contains(name) {
				return .other(Syntax(closure))
			}
			child = node
			current = node.parent
		}
		return nil
	}

	/// The local function a wrapper, `expression`, hands: `W<T>(f)`, `W<T> { f(…) }`, or an erasing wrapper's
	/// `W<(), AnyT> { AnyT(f()) }`.
	private func wrappedFunction(in expression: ExprSyntax?, at node: Syntax) -> FunctionDeclSyntax? {
		guard let call = expression?.as(FunctionCallExprSyntax.self) else { return nil }
		if let argument = call.arguments.first, call.arguments.count == 1, argument.label == nil {
			return argument.expression.as(DeclReferenceExprSyntax.self).flatMap { function(named: $0.baseName.text, at: node) }
		}
		guard call.arguments.isEmpty, var called = call.trailingClosure?.statements.first?.item.as(ExprSyntax.self)?.as(FunctionCallExprSyntax.self) else { return nil }
		while true {
			if let reference = called.calledExpression.as(DeclReferenceExprSyntax.self), let function = function(named: reference.baseName.text, at: node) {
				return function
			}
			guard let argument = called.arguments.first, called.arguments.count == 1, argument.label == nil, let inner = argument.expression.as(FunctionCallExprSyntax.self) else { return nil }
			called = inner
		}
	}

	/// The places of `function`: each declaration, wherever the type key writes it, that wraps the function and that the type
	/// of its frame declares rather than receives, with its label and that type. A declaration inside the function closes a
	/// cycle on it, which the query graph does not count as a place.
	private func places(of function: FunctionDeclSyntax) -> [(label: String, typeName: String, variable: VariableDeclSyntax)] {
		let declarations = BindingCollector()
		declarations.walk(Syntax(function.root))
		var places = [(label: String, typeName: String, variable: VariableDeclSyntax)]()
		for (label, binding, variable) in declarations.bindings where !Self.isInside(Syntax(variable), function) && wrappedFunction(in: binding.initializer?.value, at: Syntax(variable))?.id == function.id {
			guard let frame = frameTypeName(enclosing: Syntax(variable)) else { continue }
			switch kindsByLabelByType[frame.name]?[label] {
			case "instantiated", "lazy", "builder", "forwarded":
				places.append((label, frame.name, variable))
			default:
				break
			}
		}
		return places
	}

	/// Whether `node` is inside `function`'s body.
	private static func isInside(_ node: Syntax, _ function: FunctionDeclSyntax) -> Bool {
		var current = node.parent
		while let ancestor = current {
			if ancestor.id == function.id {
				return true
			}
			current = ancestor.parent
		}
		return false
	}

	/// The function a call names `name` at `node`: the nearest local function of that name in an enclosing code block.
	private func function(named name: String, at node: Syntax) -> FunctionDeclSyntax? {
		var current = node.parent
		while let node = current {
			if let items = node.as(CodeBlockItemListSyntax.self) {
				for item in items {
					if let function = item.item.as(FunctionDeclSyntax.self), function.name.text == name {
						return function
					}
				}
			}
			current = node.parent
		}
		return nil
	}

	/// Adds what `expression` supplies to `values`.
	/// - Parameter receive: The receive whose own alias `expression` may name, which is followed to what it renames: any
	///   other alias is a declaration that supplies its value.
	private func resolve(_ expression: ExprSyntax, receive: (typeName: String, label: String)? = nil, into values: inout Set<String>, visitedFunctions: inout Set<SyntaxIdentifier>) {
		if expression.is(NilLiteralExprSyntax.self) {
			values.insert("nil")
		} else if let reference = expression.as(DeclReferenceExprSyntax.self) {
			resolve(name: reference.baseName.text, at: Syntax(reference), receive: receive, into: &values, visitedFunctions: &visitedFunctions)
		} else if let optionalChaining = expression.as(OptionalChainingExprSyntax.self) {
			// An optional wrapper's instance, `x?.instance`, is read from `x`: a builder function the type key shares takes
			// the optional wrapper as a parameter.
			resolve(optionalChaining.expression, into: &values, visitedFunctions: &visitedFunctions)
		} else if let memberAccess = expression.as(MemberAccessExprSyntax.self), memberAccess.declName.baseName.text == "instance", let base = memberAccess.base {
			// A lazily instantiated value's instance is read from its wrapper.
			resolve(base, into: &values, visitedFunctions: &visitedFunctions)
		} else if let call = expression.as(FunctionCallExprSyntax.self), call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil {
			// An erasing type wraps the value it erases.
			resolve(argument.expression, into: &values, visitedFunctions: &visitedFunctions)
		} else if let call = expression.as(FunctionCallExprSyntax.self), call.arguments.isEmpty, let closure = call.trailingClosure, closure.signature == nil, closure.statements.count == 1, let wrapped = closure.statements.first?.item.as(ExprSyntax.self), let wrapper = call.calledExpression.as(GenericSpecializationExprSyntax.self)?.expression.as(DeclReferenceExprSyntax.self), ["LazilyInstantiated", "SendableLazilyInstantiated"].contains(wrapper.baseName.text) {
			// A lazy wrapper made of a value, `LazilyInstantiated<T> { x }`, which a twin's call of the function the other
			// twin closes on passes where that function takes the wrapper, holds `x`.
			resolve(wrapped, into: &values, visitedFunctions: &visitedFunctions)
		} else if let call = expression.as(FunctionCallExprSyntax.self), call.arguments.isEmpty, call.trailingClosure != nil, let map = call.calledExpression.as(MemberAccessExprSyntax.self), map.declName.baseName.text == "map", let tuple = map.base?.as(TupleExprSyntax.self), tuple.elements.count == 1, let element = tuple.elements.first, let erased = Self.valueCast(element.expression) {
			// An erased rename of an optional value erases it inside `(x as T?).map { AnyT($0) }`.
			resolve(erased, into: &values, visitedFunctions: &visitedFunctions)
		} else {
			unreadable.append("\(fileName): \(expression.trimmedDescription)")
		}
	}

	/// The value `expression` casts, `x` of `x as T?`, which the parser leaves an unfolded sequence.
	private static func valueCast(_ expression: ExprSyntax) -> ExprSyntax? {
		if let cast = expression.as(AsExprSyntax.self) {
			cast.expression
		} else if let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 3, sequence.elements.dropFirst().first?.is(UnresolvedAsExprSyntax.self) == true {
			sequence.elements.first
		} else {
			nil
		}
	}

	private func resolve(name: String, at node: Syntax, anywhereInBlocks: Bool = false, receive: (typeName: String, label: String)? = nil, into values: inout Set<String>, visitedFunctions: inout Set<SyntaxIdentifier>) {
		switch declaration(of: name, at: node, anywhereInBlocks: anywhereInBlocks) {
		case let .variable(binding, variable):
			guard let frame = frameTypeName(enclosing: Syntax(variable)) else {
				unreadable.append("\(fileName): \(name), declared outside every function")
				return
			}
			let kind = kindsByLabelByType[frame.name]?[name]
			let isOwnAlias = kind == "alias" && receive?.typeName == frame.name && receive?.label == name
			switch kind {
			case "instantiated", "lazy", "builder", "forwarded":
				values.insert("\(frame.name).\(name)")
			case "alias" where !isOwnAlias:
				values.insert("\(frame.name).\(name)")
			default:
				let isAlias = kind == "alias"
				if let initializer = binding.initializer?.value, isAlias || initializer.is(NilLiteralExprSyntax.self) || initializer.is(DeclReferenceExprSyntax.self) || initializer.is(MemberAccessExprSyntax.self) {
					// A rename – an alias – reads the declaration of its fulfilling property where it is bound.
					resolve(initializer, into: &values, visitedFunctions: &visitedFunctions)
				} else if wrappedFunction(in: binding.initializer?.value, at: Syntax(variable)) != nil, let function = frame.function.as(FunctionDeclSyntax.self), case let places = places(of: function), !places.isEmpty {
					// A rebinding at the top of a builder function, which wraps a function again, holds what is in scope at each
					// place of the function it is in: where the type key lays out a loop of builders, the function is declared in
					// the root's body, away from its places. A place that declares the label itself supplies it.
					guard visitedFunctions.insert(variable.id).inserted else { return }
					for place in places {
						if place.label == name {
							values.insert("\(place.typeName).\(name)")
						} else {
							resolve(name: name, at: Syntax(place.variable), anywhereInBlocks: true, into: &values, visitedFunctions: &visitedFunctions)
						}
					}
				} else {
					// A rebinding at the top of a builder function: the declaration of the scope that declares the function.
					resolve(name: name, at: frame.function, anywhereInBlocks: true, into: &values, visitedFunctions: &visitedFunctions)
				}
			}
		case let .parameter(label, function):
			guard let frame = frameTypeName(enclosing: Syntax(function.signature)) else { return }
			if kindsByLabelByType[frame.name]?[label] == "forwarded" {
				values.insert("\(frame.name).\(label)")
			} else if visitedFunctions.insert(function.id).inserted {
				// A parameter of a builder function a lazy cycle closes on holds what each call of the function passes.
				let calls = CallCollector(functionName: function.name.text)
				calls.walk(Syntax(function.root))
				for call in calls.calls where self.function(named: function.name.text, at: Syntax(call))?.id == function.id {
					for argument in call.arguments where argument.label?.text == label {
						resolve(argument.expression, into: &values, visitedFunctions: &visitedFunctions)
					}
				}
			}
		case let .other(node):
			unreadable.append("\(fileName): \(name), a parameter of \(node.trimmedDescription.prefix(80))")
		case nil:
			unreadable.append("\(fileName): \(name), declared nowhere in scope")
		}
	}
}

/// The variable bindings in a tree of syntax, with their names, outside code compiled only under `DEBUG`.
private final class BindingCollector: SyntaxVisitor {
	init() {
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var bindings = [(String, PatternBindingSyntax, VariableDeclSyntax)]()

	override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
		node.condition?.trimmedDescription == "DEBUG" ? .skipChildren : .visitChildren
	}

	override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		for binding in node.bindings {
			if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
				bindings.append((name, binding, node))
			}
		}
		return .visitChildren
	}
}

/// The calls of a function of a name in a tree of syntax.
private final class CallCollector: SyntaxVisitor {
	init(functionName: String) {
		self.functionName = functionName
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var calls = [FunctionCallExprSyntax]()

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == functionName {
			calls.append(node)
		}
		return .visitChildren
	}

	private let functionName: String
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerQuerySupplies {
	/// The JSON `query graph` exports for `fixture`, a graph in one module, read from its files in a directory of their own.
	static func export(of fixture: GraphFuzzerFixture) async throws -> String {
		let directory = TestTemporaryDirectory.uniquePath(prefix: "query-graph-").appendingPathComponent("Module")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
		}
		for (index, content) in fixture.swiftFileContent.enumerated() {
			try content.write(to: directory.appendingPathComponent("File\(index).swift"), atomically: true, encoding: .utf8)
		}
		var arguments = ["--include", directory.path]
		if !fixture.activeCompilationConditions.isEmpty {
			arguments += ["--active-compilation-conditions"] + fixture.activeCompilationConditions
		}
		return try await QueryGraph.parse(arguments).graph().json()
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph in one module the tool accepts whose `query graph` export names other suppliers for a receive
	/// than the generated code hands it, or `nil`. The code judged is the graph's own, or, for a graph with a seam, its
	/// build with no seam: the export builds every seam inline, and the seam build constructs the values the inline build
	/// does (`seamBuildsOtherValuesThanInline`).
	var querySuppliersFailure: GraphFuzzerFailure? {
		guard let queryExport else { return nil }
		let outcome = inlineOutcome ?? firstOutcome
		guard case let .accepted(generatedFiles, _) = outcome else { return nil }
		let exported: GraphFuzzerQuerySupplies?
		let kindsByLabelByType: [String: [String: String]]
		do {
			exported = try GraphFuzzerQuerySupplies(exportedJSON: queryExport)
			kindsByLabelByType = try GraphFuzzerQuerySupplies.kindsByLabelByType(exportedJSON: queryExport)
		} catch {
			return GraphFuzzerFailure(seed: fixture.seed, kind: .querySuppliersDifferFromGeneratedCode, details: "The export is not JSON: \(error)\n\(queryExport)")
		}
		guard let exported else {
			return GraphFuzzerFailure(seed: fixture.seed, kind: .querySuppliersDifferFromGeneratedCode, details: "The export built no trees of a graph the tool accepts:\n\(queryExport)")
		}
		let generated = GraphFuzzerQuerySupplies(generatedFiles: generatedFiles, kindsByLabelByType: kindsByLabelByType)
		let differences = exported.differences(from: generated)
		guard !differences.isEmpty || !generated.unreadable.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .querySuppliersDifferFromGeneratedCode,
			details: "Receive: export against generated code\n\((differences + generated.unreadable.map { "Unreadable: \($0)" }).joined(separator: "\n"))\nThis graph:\n\(outcome.description)",
		)
	}
}
