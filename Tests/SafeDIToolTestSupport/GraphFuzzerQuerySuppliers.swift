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
	/// `builder` for an instantiated dependency by its lifetime, `absent` for one nothing fulfills (instantiated only if
	/// available, which generated code binds to `nil`), `forwarded`, `alias` for a received dependency that
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
				case "instantiated" where dependency["isOnlyIfAvailable"] as? Bool == true && dependency["fulfilledBy"] == nil:
					// Instantiated only if available where nothing fulfills it: generated code binds `nil`.
					"absent"
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
			case "absent":
				values.insert("nil")
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

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The outcome `query graph`'s export of this graph is judged against: the graph's own, or, for a graph with a seam,
	/// its build with no seam, since the export builds every seam inline.
	var outcomeQueryExportIsJudgedAgainst: GraphFuzzerToolOutcome {
		inlineOutcome ?? firstOutcome
	}

	/// The failure of a graph in one module the tool rejects whose `query graph` export marks dependencies unfulfilled
	/// otherwise than `generate`'s errors say (`GraphFuzzerUnfulfilledDependencies.problems`), or `nil`.
	var queryUnfulfilledFailure: GraphFuzzerFailure? {
		guard let rejectedQueryExport else { return nil }
		let export: GraphFuzzerUnfulfilledDependencies
		do {
			export = try GraphFuzzerUnfulfilledDependencies(exportedJSON: rejectedQueryExport)
		} catch {
			return GraphFuzzerFailure(seed: fixture.seed, kind: .queryMarksOtherDependenciesUnfulfilled, details: "The export is not JSON: \(error)\n\(rejectedQueryExport)")
		}
		let problems = export.problems(
			generateErrorLocations: GraphFuzzerUnfulfilledDependencies.errorLocations(of: outcomeQueryExportIsJudgedAgainst, fixture: fixture),
			errorLocationsWithMissingTypesDeclared: missingTypesDeclaredOutcome?.productionErrorLocations,
			fixture: fixture,
		)
		guard !problems.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .queryMarksOtherDependenciesUnfulfilled,
			details: "\(problems.joined(separator: "\n"))\nThis graph:\n\(outcomeQueryExportIsJudgedAgainst.description)\nWith its missing types declared:\n\(missingTypesDeclaredOutcome?.outcome.description ?? "not run")\nThe export:\n\(rejectedQueryExport)",
		)
	}
}

/// What a `query graph` export says of the dependencies it marks unfulfilled, which `problems` judges against the errors
/// `generate` reports: the rule is that the marks are the dependencies `generate` reports, plus the receives it reports
/// once each missing type is declared, which are then its only errors, and that no dependency instantiated only if
/// available is marked.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct GraphFuzzerUnfulfilledDependencies {
	/// A dependency the export marks unfulfilled.
	struct Mark: Equatable {
		/// The dependency's file and line, as `location(ofFileNamed:line:)` spells it.
		let location: String
		/// Whether the dependency is instantiated, so that its type is one no declaration fulfills.
		let isInstantiated: Bool
		/// The type an instantiated dependency constructs, as a declaration of it names it.
		let instantiatedTypeName: String
		/// Whether the dependency is instantiated or received only if available, so that it is `nil` where nothing
		/// fulfills or provides it.
		let isOnlyIfAvailable: Bool
	}

	init(exportedJSON json: String) throws {
		let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
		isPartial = object["completeness"] as? String == "partialTrees"
		hasWholeTrees = object["completeness"] as? String == "trees"
		var marks = [Mark]()
		for declaration in object["declarations"] as? [[String: Any]] ?? [] {
			for dependency in declaration["dependencies"] as? [[String: Any]] ?? [] where dependency["isUnfulfilled"] as? Bool == true {
				marks.append(Mark(
					location: Self.location(ofFileNamed: URL(fileURLWithPath: dependency["filePath"] as? String ?? "?").lastPathComponent, line: dependency["line"] as? Int ?? 0),
					isInstantiated: dependency["source"] as? String == "instantiated",
					instantiatedTypeName: dependency["fulfilledByType"] as? String ?? dependency["plainType"] as? String ?? "?",
					isOnlyIfAvailable: dependency["isOnlyIfAvailable"] as? Bool == true,
				))
			}
		}
		self.marks = marks
	}

	/// Whether the export's `completeness` is `partialTrees`.
	let isPartial: Bool
	/// Whether the export's `completeness` is `trees`: the production trees are valid.
	let hasWholeTrees: Bool
	/// Each dependency the export marks unfulfilled, in its order.
	let marks: [Mark]

	/// The types no declaration fulfills that the marked instantiated dependencies construct, each once, in name order.
	var missingTypeNames: [String] {
		Set(marks.lazy.filter(\.isInstantiated).map(\.instantiatedTypeName)).sorted()
	}

	/// `generate`'s outcome for a graph with an empty declaration of each missing type, and which of its errors are of the
	/// production trees.
	struct OutcomeWithMissingTypesDeclared {
		/// `generate`'s outcome for the graph, with no seam.
		let outcome: GraphFuzzerToolOutcome
		/// The file and line of each error of it that the production trees report, spelled as the marks' locations are.
		let productionErrorLocations: [String]
	}

	/// The outcome of `fixture` with an empty declaration of each missing type, where the export has partial trees and
	/// marks an instantiated dependency: the graph whose only production errors, if the trees were rightly built around
	/// the missing types, are the receives the export marks. `nil` otherwise.
	///
	/// Once the production trees are valid, `generate` goes on to its mocks and reports their errors, which
	/// `query graph` does not read (base corpus seed 106 reports a cycle in a mock's tree so). So where an error is at no
	/// mark, the graph is exported, and where that export has whole trees none of the errors is of the production trees.
	func outcomeWithMissingTypesDeclared(of fixture: GraphFuzzerFixture) async throws -> OutcomeWithMissingTypesDeclared? {
		guard isPartial, !missingTypeNames.isEmpty else { return nil }
		let fixtureDeclaringMissingTypes = fixtureDeclaringMissingTypes(of: fixture)
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixtureDeclaringMissingTypes.withoutSeams)
		let errorLocations = Self.errorLocations(of: outcome, fixture: fixture)
		let marked = Set(marks.map(\.location))
		guard errorLocations.contains(where: { !marked.contains($0) }),
		      try await Self(exportedJSON: GraphFuzzerQuerySupplies.export(of: fixtureDeclaringMissingTypes)).hasWholeTrees
		else {
			return OutcomeWithMissingTypesDeclared(outcome: outcome, productionErrorLocations: errorLocations)
		}
		return OutcomeWithMissingTypesDeclared(outcome: outcome, productionErrorLocations: [])
	}

	/// `fixture` with an empty declaration of each of `missingTypeNames` in a last file of its own, so that no line of
	/// another file moves: the graph `generate` reports its further errors for once the missing types exist.
	func fixtureDeclaringMissingTypes(of fixture: GraphFuzzerFixture) -> GraphFuzzerFixture {
		var declarations = [Self.missingTypesFileMarker]
		for name in missingTypeNames {
			declarations.append("@Instantiable\nextension \(name): Instantiable {\n\tpublic static func instantiate() -> \(name) {\n\t\t\(name)()\n\t}\n}")
		}
		return GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: fixture.swiftFileContent + [declarations.joined(separator: "\n\n") + "\n"])
	}

	/// The name of the file `fixtureDeclaringMissingTypes(of:)` adds, which names itself.
	static let missingTypesFileName = "QueryMissingTypes.swift"
	private static let missingTypesFileMarker = "\(GraphFuzzerFixture.fileNameMarker)\(missingTypesFileName)"

	/// The file and line of each error `outcome` reports, spelled as the marks' locations are, in the tool's order: no
	/// location where the tool accepts the graph.
	static func errorLocations(of outcome: GraphFuzzerToolOutcome, fixture: GraphFuzzerFixture) -> [String] {
		switch outcome {
		case .accepted:
			return []
		case let .rejected(diagnostics):
			var indexByFileName = [String: Int]()
			for (index, fileName) in fixture.fileNames.enumerated() {
				indexByFileName[fileName] = index
			}
			return diagnostics.split(separator: "\n").compactMap(GraphFuzzerRemedies.ReportedError.init).map { error in
				location(ofFileNamed: indexByFileName[error.fileName].map { "File\($0).swift" } ?? error.fileName, line: error.line)
			}
		}
	}

	/// Each way the marks disagree with `generate`'s errors, empty where they agree. Where the export reports partial
	/// trees, it marks a dependency, every error `generate` reports for the graph (`generateErrorLocations`) is at a mark,
	/// but one at a dependency instantiated only if available, which the export reads as `nil` and so never marks, every
	/// further mark is at an error the production trees report once each missing type is declared
	/// (`errorLocationsWithMissingTypesDeclared`, `nil` where that graph was not run), and every error they then report
	/// is at a mark: an error anywhere else is a receive the export did not mark, or one the trees could not be built
	/// around, so that the export had no partial trees to report. Otherwise it marks nothing.
	func problems(generateErrorLocations: [String], errorLocationsWithMissingTypesDeclared: [String]?, fixture: GraphFuzzerFixture) -> [String] {
		var problems = [String]()
		if isPartial {
			if marks.isEmpty {
				problems.append("The export reports partial trees and marks no dependency unfulfilled.")
			}
			let marked = Set(marks.map(\.location))
			for location in generateErrorLocations where !marked.contains(location) && !Self.isInstantiatedOnlyIfAvailable(at: location, in: fixture) {
				problems.append("`generate` reports an error at \(location), where the export marks no dependency unfulfilled.")
			}
			let reported = Set(generateErrorLocations)
			let reportedWithMissingTypesDeclared = Set(errorLocationsWithMissingTypesDeclared ?? [])
			for mark in marks where !reported.contains(mark.location) && !reportedWithMissingTypesDeclared.contains(mark.location) {
				problems.append("The export marks the dependency at \(mark.location) unfulfilled, where `generate` reports no error, for the graph or for the graph with \(missingTypeNames.joined(separator: ", ")) declared.")
			}
			for mark in marks where mark.isInstantiated && mark.isOnlyIfAvailable {
				problems.append("The export marks the dependency at \(mark.location) unfulfilled, which is instantiated only if available and so is `nil`.")
			}
			for location in errorLocationsWithMissingTypesDeclared ?? [] where !marked.contains(location) {
				problems.append("With \(missingTypeNames.joined(separator: ", ")) declared, `generate` reports an error at \(location), where the export marks no dependency unfulfilled, so its trees are not partial trees of this graph.")
			}
		} else {
			for mark in marks {
				problems.append("The export reports no partial trees and marks the dependency at \(mark.location) unfulfilled.")
			}
		}
		return problems
	}

	/// Whether the line `location` names in `fixture` declares a dependency instantiated only if available.
	private static func isInstantiatedOnlyIfAvailable(at location: String, in fixture: GraphFuzzerFixture) -> Bool {
		for (index, content) in fixture.swiftFileContent.enumerated() {
			let lines = content.components(separatedBy: "\n")
			for (lineIndex, line) in lines.enumerated() where Self.location(ofFileNamed: "File\(index).swift", line: lineIndex + 1) == location {
				return line.contains("@Instantiated(") && line.contains("onlyIfAvailable: true")
			}
		}
		return false
	}

	private static func location(ofFileNamed fileName: String, line: Int) -> String {
		"\(fileName):\(line)"
	}
}

/// One declaration deleted from a graph the tool accepts, and what `query graph` must then export, which the deletion
/// oracle checks (`GraphFuzzerToolRuns.queryDeletionFailure`): `query graph` reads a graph with a missing type from its
/// declarations as written, so deleting a type's declaration moves no other receive's `provenance`.
///
/// The declaration is one with no dependency of its own that is no root and that a declaration some root reaches
/// instantiates, chosen by the graph's seed. Its `@Instantiable` line is blanked, so that no other line moves and its
/// type is left one no declaration fulfills. The export of that graph must then be the full graph's but for what names
/// the deleted declaration: each required dependency of a reached declaration that instantiated it is marked
/// unfulfilled, each provenance entry that named such a dependency names it as `unfulfilled`, each that named a
/// dependency instantiated only if available is `nil` because that declaration is not instantiated, and every other
/// entry, mark and `isReachedByRoot` is the full graph's.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct GraphFuzzerQueryDeletion: Sendable {
	/// The deletion to make from `fixture`, whose `query graph` export is `json`, or `nil` where the export built no
	/// trees or holds no declaration the oracle deletes.
	init?(exportedJSON json: String, fixture: GraphFuzzerFixture) throws {
		guard let export = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
		      export["completeness"] as? String == "trees",
		      let declarations = export["declarations"] as? [[String: Any]]
		else { return nil }
		var reachedIDs = Set<String>()
		for declaration in declarations where declaration["isReachedByRoot"] as? Bool == true {
			if let id = declaration["id"] as? String {
				reachedIDs.insert(id)
			}
		}
		var candidates = [(declaration: [String: Any], fileIndex: Int, lineIndex: Int)]()
		for declaration in declarations {
			guard (declaration["dependencies"] as? [[String: Any]])?.isEmpty == true,
			      declaration["isRoot"] as? Bool == false,
			      // An extension that conforms to `Instantiable` is read as a declaration without its attribute too.
			      declaration["declarationKind"] as? String != "extension",
			      (declaration["constructedBy"] as? [[String: Any]] ?? []).contains(where: { reachedIDs.contains($0["declaredBy"] as? String ?? "") }),
			      let fileIndex = Self.fileIndex(ofFileAt: declaration["filePath"] as? String ?? ""),
			      let line = declaration["line"] as? Int,
			      fixture.swiftFileContent.indices.contains(fileIndex)
			else { continue }
			let lines = fixture.swiftFileContent[fileIndex].components(separatedBy: "\n")
			guard lines.indices.contains(line - 1), lines[line - 1].hasPrefix("@Instantiable") else { continue }
			candidates.append((declaration, fileIndex, line - 1))
		}
		guard !candidates.isEmpty else { return nil }
		let candidate = candidates[Int(fixture.seed % UInt64(candidates.count))]
		deletedDeclarationID = candidate.declaration["id"] as? String ?? "?"
		var contents = fixture.swiftFileContent
		var lines = contents[candidate.fileIndex].components(separatedBy: "\n")
		lines[candidate.lineIndex] = ""
		contents[candidate.fileIndex] = lines.joined(separator: "\n")
		fixtureWithoutDeclaration = GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: contents)
		for constructor in candidate.declaration["constructedBy"] as? [[String: Any]] ?? [] {
			guard let declaredBy = constructor["declaredBy"] as? String, let label = constructor["label"] as? String else { continue }
			let supplier = Supplier(declaredBy: declaredBy, label: label)
			let dependency = declarations.first { $0["id"] as? String == declaredBy }
				.flatMap { ($0["dependencies"] as? [[String: Any]])?.first { $0["label"] as? String == label } }
			if dependency?["isOnlyIfAvailable"] as? Bool == true {
				suppliersInstantiatedOnlyIfAvailable.insert(supplier)
			} else {
				requiredSuppliers.insert(supplier)
				if reachedIDs.contains(declaredBy) {
					leavesDependencyUnfulfilled = true
				}
			}
			suppliersLeftUnfulfilled.insert(supplier)
		}
		fullExportJSON = json
	}

	/// The `id` of the declaration deleted.
	let deletedDeclarationID: String
	/// The graph without that declaration, every other line where it was.
	let fixtureWithoutDeclaration: GraphFuzzerFixture

	/// A dependency that instantiated the deleted declaration.
	private struct Supplier: Hashable {
		let declaredBy: String
		let label: String
	}

	/// Every dependency that instantiated the deleted declaration, which no declaration fulfills without it.
	private var suppliersLeftUnfulfilled = Set<Supplier>()
	/// Those of them that are required. `generate` reports a type no declaration fulfills where a tree of a root
	/// instantiates it, and then names every required dependency that instantiates it, reached or not.
	private var requiredSuppliers = Set<Supplier>()
	/// Those of them instantiated only if available, which are `nil` without the declaration.
	private var suppliersInstantiatedOnlyIfAvailable = Set<Supplier>()
	/// The graph's own export, which the export without the declaration is compared with.
	private let fullExportJSON: String

	/// Whether deleting the declaration leaves a dependency `generate` reports, one a declaration some root reaches
	/// requires, so that the export has partial trees and marks every required dependency that instantiated it.
	private(set) var leavesDependencyUnfulfilled = false

	/// Each way `json`, the export of `fixtureWithoutDeclaration`, differs from what the deletion must leave, empty where
	/// it is that export.
	func problems(exportedJSONWithoutDeclaration json: String) throws -> [String] {
		let export = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
		let fullExport = try JSONSerialization.jsonObject(with: Data(fullExportJSON.utf8)) as? [String: Any] ?? [:]
		var problems = [String]()
		let expectedCompleteness = leavesDependencyUnfulfilled ? "partialTrees" : "trees"
		if export["completeness"] as? String != expectedCompleteness {
			problems.append("The export's completeness is \(export["completeness"] as? String ?? "?"), not \(expectedCompleteness).")
		}
		var declarationsByID = [String: [String: Any]]()
		for declaration in export["declarations"] as? [[String: Any]] ?? [] {
			declarationsByID[declaration["id"] as? String ?? "?"] = declaration
		}
		if declarationsByID[deletedDeclarationID] != nil {
			problems.append("The export still holds the deleted declaration.")
		}
		for fullDeclaration in fullExport["declarations"] as? [[String: Any]] ?? [] {
			guard let id = fullDeclaration["id"] as? String, id != deletedDeclarationID else { continue }
			guard let declaration = declarationsByID.removeValue(forKey: id) else {
				problems.append("\(id): the export without the declaration lacks it.")
				continue
			}
			if declaration["isReachedByRoot"] as? Bool != fullDeclaration["isReachedByRoot"] as? Bool {
				problems.append("\(id): isReachedByRoot is \(String(describing: declaration["isReachedByRoot"])), not \(String(describing: fullDeclaration["isReachedByRoot"])).")
			}
			let dependencies = declaration["dependencies"] as? [[String: Any]] ?? []
			let fullDependencies = fullDeclaration["dependencies"] as? [[String: Any]] ?? []
			guard dependencies.map({ $0["label"] as? String }) == fullDependencies.map({ $0["label"] as? String }) else {
				problems.append("\(id): the export without the declaration lists other dependencies.")
				continue
			}
			for (dependency, fullDependency) in zip(dependencies, fullDependencies) {
				let name = "\(id).\(fullDependency["label"] as? String ?? "?")"
				let supplier = Supplier(declaredBy: id, label: fullDependency["label"] as? String ?? "?")
				let isMarked = dependency["isUnfulfilled"] as? Bool == true
				if isMarked != (leavesDependencyUnfulfilled && requiredSuppliers.contains(supplier)) {
					problems.append("\(name): \(isMarked ? "marked unfulfilled, which `generate` does not report" : "not marked unfulfilled, which `generate` reports").")
				}
				let expectedFulfilledBy = suppliersLeftUnfulfilled.contains(supplier) ? nil : fullDependency["fulfilledBy"] as? String
				if dependency["fulfilledBy"] as? String != expectedFulfilledBy {
					problems.append("\(name): fulfilledBy is \(dependency["fulfilledBy"] as? String ?? "absent"), not \(expectedFulfilledBy ?? "absent").")
				}
				let provenance = (dependency["provenance"] as? [[String: Any]])?.map(Self.entry(of:)).sorted()
				let expectedProvenance = (fullDependency["provenance"] as? [[String: Any]])?.map(expectedEntry(ofFullExportEntry:)).sorted()
				if provenance != expectedProvenance {
					problems.append("\(name): provenance is \(provenance.map { "\($0)" } ?? "absent"), not \(expectedProvenance.map { "\($0)" } ?? "absent").")
				}
			}
		}
		for id in declarationsByID.keys.sorted() where id != deletedDeclarationID {
			problems.append("\(id): only the export without the declaration holds it.")
		}
		return problems
	}

	/// The provenance entry the export without the declaration must hold where the full export holds `entry`.
	private func expectedEntry(ofFullExportEntry entry: [String: Any]) -> String {
		guard entry["source"] as? String == "declaration", let declaredBy = entry["declaredBy"] as? String, let label = entry["label"] as? String else {
			return Self.entry(of: entry)
		}
		let supplier = Supplier(declaredBy: declaredBy, label: label)
		return if suppliersInstantiatedOnlyIfAvailable.contains(supplier) {
			Self.entry(source: "nil", declaredBy: nil, label: nil, reasonKind: "declarationNotInstantiated", reasonDeclaredBy: declaredBy, reasonLabel: label)
		} else if suppliersLeftUnfulfilled.contains(supplier) {
			Self.entry(source: "unfulfilled", declaredBy: declaredBy, label: label, reasonKind: nil, reasonDeclaredBy: nil, reasonLabel: nil)
		} else {
			Self.entry(of: entry)
		}
	}

	/// A provenance entry as the oracle compares it: everything it holds but its sentences.
	fileprivate static func entry(of entry: [String: Any]) -> String {
		let reason = entry["reason"] as? [String: Any]
		return Self.entry(
			source: entry["source"] as? String ?? "?",
			declaredBy: entry["declaredBy"] as? String,
			label: entry["label"] as? String,
			reasonKind: reason?["kind"] as? String,
			reasonDeclaredBy: reason?["declaredBy"] as? String,
			reasonLabel: reason?["label"] as? String,
		)
	}

	private static func entry(source: String, declaredBy: String?, label: String?, reasonKind: String?, reasonDeclaredBy: String?, reasonLabel: String?) -> String {
		var entry = source
		if let declaredBy, let label {
			entry += " \(declaredBy).\(label)"
		}
		if let reasonKind {
			entry += " (\(reasonKind)"
			if let reasonDeclaredBy, let reasonLabel {
				entry += " \(reasonDeclaredBy).\(reasonLabel)"
			}
			entry += ")"
		}
		return entry
	}

	/// The index of the fixture file the export read at `filePath`, which `GraphFuzzerQuerySupplies.export(of:)` names
	/// `File<index>.swift`.
	private static func fileIndex(ofFileAt filePath: String) -> Int? {
		let name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
		guard name.hasPrefix("File") else { return nil }
		return Int(name.dropFirst("File".count))
	}
}

/// One property that provides a value deleted from a graph the tool accepts, and what `query graph` must then export,
/// which the deletion oracle checks beside `GraphFuzzerQueryDeletion`: `query graph` reads a receive nothing provides
/// from the declarations as written, so deleting a property moves only what read that property.
///
/// The property is an instantiated dependency of a declaration some root reaches whose type's declaration has no
/// dependency of its own, so that no tree goes with it and no sibling waits on it: the one whose value the most
/// receives beneath another receive of it are handed, then the one the most receives are handed, and among equals one
/// chosen by the graph's seed. The export of the graph without it, where it has trees, must be the full graph's but for
/// the dependencies that receive or rename its label. Of those, none is handed the property, each keeps every other
/// declaration it was handed, one that never read the property keeps its `provenance` whole, a dependency is marked
/// exactly where a value of it is `unfulfilled` and names nothing, and each `unfulfilled` value that names a dependency
/// names a marked receive of the label. What takes the property's place is judged too: each `declaration` a reader is
/// handed is a dependency of the export that provides a value (instantiated, forwarded or an alias), a reader that was
/// handed the property is handed something in its place, and a required receive that is not optional is never `nil`.
/// Every other dependency's `provenance`, and every `isReachedByRoot` but the property's type's, is the full graph's.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct GraphFuzzerQueryProviderDeletion: Sendable {
	/// The deletion to make from `fixture`, whose `query graph` export is `json`, or `nil` where the export built no
	/// trees or holds no property the oracle deletes.
	init?(exportedJSON json: String, fixture: GraphFuzzerFixture) throws {
		guard let export = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
		      export["completeness"] as? String == "trees",
		      let declarations = export["declarations"] as? [[String: Any]],
		      let files = GraphFuzzerRemedies.Files(fixture)
		else { return nil }
		var leafIDs = Set<String>()
		for declaration in declarations where (declaration["dependencies"] as? [[String: Any]])?.isEmpty == true {
			if let id = declaration["id"] as? String {
				leafIDs.insert(id)
			}
		}
		var candidates = [(declarationID: String, typeName: String, label: String, fulfilledBy: String)]()
		for declaration in declarations where declaration["isReachedByRoot"] as? Bool == true {
			guard let id = declaration["id"] as? String, let typeName = declaration["typeName"] as? String else { continue }
			for dependency in declaration["dependencies"] as? [[String: Any]] ?? [] where dependency["source"] as? String == "instantiated" {
				guard let label = dependency["label"] as? String,
				      let fulfilledBy = dependency["fulfilledBy"] as? String, leafIDs.contains(fulfilledBy)
				else { continue }
				candidates.append((id, typeName, label, fulfilledBy))
			}
		}
		// A property whose value a receive beneath another receive of it is handed is deleted first, and then one with
		// more receives: what a receive beneath a marked receive reads is what the comparison is for.
		func receives(of candidate: (declarationID: String, typeName: String, label: String, fulfilledBy: String)) -> (nested: Int, count: Int) {
			var receivingIDs = Set<String>()
			var count = 0
			for declaration in declarations {
				for dependency in declaration["dependencies"] as? [[String: Any]] ?? [] {
					for entry in dependency["provenance"] as? [[String: Any]] ?? [] where entry["source"] as? String == "declaration"
						&& entry["declaredBy"] as? String == candidate.declarationID && entry["label"] as? String == candidate.label
					{
						count += 1
						if let id = declaration["id"] as? String {
							receivingIDs.insert(id)
						}
					}
				}
			}
			var nested = 0
			for declaration in declarations where (declaration["id"] as? String).map(receivingIDs.contains) == true {
				for constructor in declaration["constructedBy"] as? [[String: Any]] ?? [] where (constructor["declaredBy"] as? String).map(receivingIDs.contains) == true {
					nested += 1
				}
			}
			return (nested, count)
		}
		var preferred = [(declarationID: String, typeName: String, label: String, fulfilledBy: String)]()
		var preferredReceives = (nested: -1, count: -1)
		for candidate in candidates {
			let receives = receives(of: candidate)
			if receives == preferredReceives {
				preferred.append(candidate)
			} else if receives > preferredReceives {
				preferred = [candidate]
				preferredReceives = receives
			}
		}
		guard !preferred.isEmpty else { return nil }
		let candidate = preferred[Int(fixture.seed % UInt64(preferred.count))]
		var editedFiles = files
		guard editedFiles.edit(typeNamed: candidate.typeName, { properties in
			let kept = properties.filter { $0.label != candidate.label }
			return kept.count == properties.count - 1 ? kept : nil
		}) else { return nil }
		declarationID = candidate.declarationID
		label = candidate.label
		fulfillingDeclarationID = candidate.fulfilledBy
		fixtureWithoutProperty = GraphFuzzerFixture(seed: fixture.seed, swiftFileContent: editedFiles.contents)
		fullExportJSON = json
	}

	/// The `id` of the declaration whose property is deleted, and the property's label.
	let declarationID: String
	let label: String
	/// The `id` of the declaration that fulfilled the property's type, which the deletion may leave unreached.
	private let fulfillingDeclarationID: String
	/// The graph without that property.
	let fixtureWithoutProperty: GraphFuzzerFixture
	/// The graph's own export, which the export without the property is compared with.
	private let fullExportJSON: String

	/// Whether `json`, the export of `fixtureWithoutProperty`, has trees to judge: it has none where the graph without
	/// the property has an error that is not of a dependency that cannot be fulfilled.
	static func hasTrees(exportedJSON json: String) throws -> Bool {
		let completeness = (try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["completeness"] as? String
		return completeness == "trees" || completeness == "partialTrees"
	}

	/// Whether a value of a receive in `json`, an export, is `unfulfilled` naming a receive above it.
	static func namesMarkedReceive(exportedJSON json: String) throws -> Bool {
		let export = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
		return (export["declarations"] as? [[String: Any]] ?? []).contains { declaration in
			(declaration["dependencies"] as? [[String: Any]] ?? []).contains { dependency in
				(dependency["provenance"] as? [[String: Any]] ?? []).contains { $0["source"] as? String == "unfulfilled" && $0["declaredBy"] != nil }
			}
		}
	}

	/// Each way `json`, the export of `fixtureWithoutProperty`, differs from what the deletion must leave, empty where it
	/// is that export or has no trees.
	func problems(exportedJSONWithoutProperty json: String) throws -> [String] {
		guard try Self.hasTrees(exportedJSON: json) else { return [] }
		let export = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
		let fullExport = try JSONSerialization.jsonObject(with: Data(fullExportJSON.utf8)) as? [String: Any] ?? [:]
		var problems = [String]()
		var declarationsByID = [String: [String: Any]]()
		var markedReceivesOfLabel = Set<String>()
		var providingDependencies = Set<String>()
		var marksDependency = false
		for declaration in export["declarations"] as? [[String: Any]] ?? [] {
			let id = declaration["id"] as? String ?? "?"
			declarationsByID[id] = declaration
			for dependency in declaration["dependencies"] as? [[String: Any]] ?? [] where dependency["source"] as? String != "received" || dependency["aliasOf"] != nil {
				providingDependencies.insert("declaration \(id).\(dependency["label"] as? String ?? "?")")
			}
			for dependency in declaration["dependencies"] as? [[String: Any]] ?? [] where dependency["isUnfulfilled"] as? Bool == true {
				marksDependency = true
				if dependency["label"] as? String == label, dependency["aliasOf"] == nil {
					markedReceivesOfLabel.insert("unfulfilled \(id).\(label)")
				}
			}
		}
		let expectedCompleteness = marksDependency ? "partialTrees" : "trees"
		if export["completeness"] as? String != expectedCompleteness {
			problems.append("The export's completeness is \(export["completeness"] as? String ?? "?"), not \(expectedCompleteness).")
		}
		for fullDeclaration in fullExport["declarations"] as? [[String: Any]] ?? [] {
			guard let id = fullDeclaration["id"] as? String else { continue }
			guard let declaration = declarationsByID.removeValue(forKey: id) else {
				problems.append("\(id): the export without the property lacks it.")
				continue
			}
			if id != fulfillingDeclarationID, declaration["isReachedByRoot"] as? Bool != fullDeclaration["isReachedByRoot"] as? Bool {
				problems.append("\(id): isReachedByRoot is \(String(describing: declaration["isReachedByRoot"])), not \(String(describing: fullDeclaration["isReachedByRoot"])).")
			}
			let dependencies = declaration["dependencies"] as? [[String: Any]] ?? []
			let fullDependencies = (fullDeclaration["dependencies"] as? [[String: Any]] ?? []).filter { id != declarationID || $0["label"] as? String != label }
			guard dependencies.map({ $0["label"] as? String }) == fullDependencies.map({ $0["label"] as? String }) else {
				problems.append("\(id): the export without the property lists other dependencies.")
				continue
			}
			for (dependency, fullDependency) in zip(dependencies, fullDependencies) {
				let name = "\(id).\(fullDependency["label"] as? String ?? "?")"
				let isMarked = dependency["isUnfulfilled"] as? Bool == true
				let provenance = (dependency["provenance"] as? [[String: Any]])?.map(GraphFuzzerQueryDeletion.entry(of:)).sorted()
				let fullProvenance = (fullDependency["provenance"] as? [[String: Any]])?.map(GraphFuzzerQueryDeletion.entry(of:)).sorted()
				let readsLabel = dependency["source"] as? String == "received"
					&& ((dependency["aliasOf"] as? [String: Any])?["label"] as? String ?? dependency["label"] as? String) == label
				guard readsLabel else {
					if isMarked {
						problems.append("\(name): marked unfulfilled, though it reads no `\(label)`.")
					}
					if provenance != fullProvenance {
						problems.append("\(name): provenance is \(provenance.map { "\($0)" } ?? "absent"), not \(fullProvenance.map { "\($0)" } ?? "absent"), though it reads no `\(label)`.")
					}
					continue
				}
				guard let provenance else {
					if fullProvenance != nil {
						problems.append("\(name): has no provenance without the property.")
					}
					if isMarked {
						problems.append("\(name): marked unfulfilled in a declaration no root reaches, which `generate` does not report.")
					}
					continue
				}
				let deleted = "declaration \(declarationID).\(label)"
				let fullEntries = fullProvenance ?? []
				if !fullEntries.contains(deleted), !fullEntries.contains(where: { $0.hasPrefix("nil (providerNotYetBuilt") }), provenance != fullEntries {
					problems.append("\(name): provenance is \(provenance), not \(fullEntries), though it never read the property.")
				}
				for entry in fullEntries where entry.hasPrefix("declaration ") && entry != deleted && !provenance.contains(entry) {
					problems.append("\(name): is no longer handed `\(entry)`.")
				}
				if provenance.isEmpty, fullEntries.contains(deleted) {
					problems.append("\(name): was handed the deleted property and is handed nothing in its place.")
				}
				let type = dependency["type"] as? String ?? ""
				let isRequiredAndNotOptional = dependency["isOnlyIfAvailable"] as? Bool != true && !type.hasSuffix("?") && !type.hasPrefix("Optional<")
				for entry in provenance {
					if entry == deleted {
						problems.append("\(name): is handed the deleted property.")
					} else if entry.hasPrefix("declaration "), !providingDependencies.contains(entry) {
						problems.append("\(name): is handed `\(entry)`, which is no instantiated, forwarded or aliased dependency of the export.")
					} else if entry.hasPrefix("nil"), isRequiredAndNotOptional {
						problems.append("\(name): required and not optional, and a value of it is `\(entry)`.")
					} else if entry == "unfulfilled" {
						if dependency["isOnlyIfAvailable"] as? Bool == true {
							problems.append("\(name): received only if available, and a value of it is `unfulfilled` naming nothing.")
						}
					} else if entry.hasPrefix("unfulfilled "), !markedReceivesOfLabel.contains(entry) {
						problems.append("\(name): a value of it is `\(entry)`, which is no marked receive of `\(label)`.")
					} else if entry == "nil (noProvidingDeclaration)", dependency["isOnlyIfAvailable"] as? Bool != true {
						problems.append("\(name): required, and a value of it is `nil` where nothing provides it, which `generate` reports or a receive above stands for.")
					}
				}
				if isMarked != provenance.contains("unfulfilled") {
					problems.append("\(name): \(isMarked ? "marked unfulfilled though each value of it names a receive above" : "not marked unfulfilled though a value of it names nothing").")
				}
			}
		}
		for id in declarationsByID.keys.sorted() {
			problems.append("\(id): only the export without the property holds it.")
		}
		return problems
	}
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension GraphFuzzerToolRuns {
	/// The failure of a graph in one module the tool accepts whose `query graph` export, once a type's declaration or a
	/// property that provides a value is deleted from the graph, moves what a receive that did not read it is handed
	/// (`GraphFuzzerQueryDeletion`, `GraphFuzzerQueryProviderDeletion`), or `nil`.
	var queryDeletionFailure: GraphFuzzerFailure? {
		var details = [String]()
		do {
			if let queryDeletion {
				let problems = try queryDeletion.deletion.problems(exportedJSONWithoutDeclaration: queryDeletion.export)
				if !problems.isEmpty {
					details.append("Without the declaration \(queryDeletion.deletion.deletedDeclarationID):\n\(problems.joined(separator: "\n"))\nThe export without it:\n\(queryDeletion.export)")
				}
			}
			if let queryProviderDeletion {
				let problems = try queryProviderDeletion.deletion.problems(exportedJSONWithoutProperty: queryProviderDeletion.export)
				if !problems.isEmpty {
					details.append("Without the property \(queryProviderDeletion.deletion.declarationID).\(queryProviderDeletion.deletion.label):\n\(problems.joined(separator: "\n"))\nThe export without it:\n\(queryProviderDeletion.export)")
				}
			}
		} catch {
			return GraphFuzzerFailure(seed: fixture.seed, kind: .queryProvenanceMovesWhenDeclarationIsDeleted, details: "An export is not JSON: \(error)")
		}
		guard !details.isEmpty else { return nil }
		return GraphFuzzerFailure(
			seed: fixture.seed,
			kind: .queryProvenanceMovesWhenDeclarationIsDeleted,
			details: "\(details.joined(separator: "\n"))\nThe graph's export:\n\(queryExport ?? "")",
		)
	}
}

/// The query oracles' judgments of one graph, made as `GraphFuzzerOracle.toolRuns(of:)` makes them and without the
/// rest of its runs, for the tests that hold the oracles' floors.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
enum GraphFuzzerQueryJudgment {
	/// What `queryUnfulfilledFailure` finds in a graph in one module the tool rejects.
	struct Marks {
		/// Whether the export has partial trees.
		let isPartial: Bool
		/// Whether the export marks an instantiated dependency, so that the graph was run again with its missing types
		/// declared.
		let ranWithMissingTypesDeclared: Bool
		let problems: [String]
	}

	/// The marks oracle's judgment of `fixture`, or `nil` where the tool accepts it.
	static func marks(of fixture: GraphFuzzerFixture) async throws -> Marks? {
		let outcome = try await GraphFuzzerOracle.toolOutcome(of: fixture.withoutSeams)
		guard case .rejected = outcome else { return nil }
		let marks = try await GraphFuzzerUnfulfilledDependencies(exportedJSON: GraphFuzzerQuerySupplies.export(of: fixture))
		let outcomeWithMissingTypesDeclared = try await marks.outcomeWithMissingTypesDeclared(of: fixture)
		return Marks(
			isPartial: marks.isPartial,
			ranWithMissingTypesDeclared: outcomeWithMissingTypesDeclared != nil,
			problems: marks.problems(
				generateErrorLocations: GraphFuzzerUnfulfilledDependencies.errorLocations(of: outcome, fixture: fixture),
				errorLocationsWithMissingTypesDeclared: outcomeWithMissingTypesDeclared?.productionErrorLocations,
				fixture: fixture,
			),
		)
	}

	/// What `queryDeletionFailure` finds in a graph in one module whose export has trees.
	struct Deletions {
		/// Whether a type's declaration was deleted and that left a dependency `generate` reports.
		let declarationLeavesDependencyUnfulfilled: Bool
		/// Whether the export without a property that provides a value has partial trees, and whether a receive in it is
		/// `unfulfilled` naming a marked receive above it.
		let propertyLeavesPartialTrees: Bool
		let propertyLeavesReceiveBeneathMarkedReceive: Bool
		let problems: [String]
	}

	/// The deletion oracle's judgment of `fixture`.
	static func deletions(of fixture: GraphFuzzerFixture) async throws -> Deletions {
		let export = try await GraphFuzzerQuerySupplies.export(of: fixture)
		var problems = [String]()
		let declarationDeletion = try GraphFuzzerQueryDeletion(exportedJSON: export, fixture: fixture)
		if let declarationDeletion {
			problems += try await declarationDeletion.problems(exportedJSONWithoutDeclaration: GraphFuzzerQuerySupplies.export(of: declarationDeletion.fixtureWithoutDeclaration))
		}
		var propertyLeavesPartialTrees = false
		var propertyLeavesReceiveBeneathMarkedReceive = false
		let propertyDeletion = try GraphFuzzerQueryProviderDeletion(exportedJSON: export, fixture: fixture)
		if let propertyDeletion {
			let exportWithoutProperty = try await GraphFuzzerQuerySupplies.export(of: propertyDeletion.fixtureWithoutProperty)
			propertyLeavesPartialTrees = try GraphFuzzerUnfulfilledDependencies(exportedJSON: exportWithoutProperty).isPartial
			propertyLeavesReceiveBeneathMarkedReceive = try GraphFuzzerQueryProviderDeletion.namesMarkedReceive(exportedJSON: exportWithoutProperty)
			problems += try propertyDeletion.problems(exportedJSONWithoutProperty: exportWithoutProperty)
		}
		return Deletions(
			declarationLeavesDependencyUnfulfilled: declarationDeletion?.leavesDependencyUnfulfilled == true,
			propertyLeavesPartialTrees: propertyLeavesPartialTrees,
			propertyLeavesReceiveBeneathMarkedReceive: propertyLeavesReceiveBeneathMarkedReceive,
			problems: problems,
		)
	}
}
