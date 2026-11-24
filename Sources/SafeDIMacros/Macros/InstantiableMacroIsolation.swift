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

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

extension InstantiableMacro {
	/// Reports each declaration SafeDI generates for `concreteDeclaration` – a root’s `init()`, a seam’s initializers,
	/// a `mock()` – that calls a declaration bound to a global actor while nothing states the generated declaration’s
	/// isolation, with a fix-it that adds the global actor to the attribute argument the generated declaration reads.
	///
	/// SafeDI infers no isolation: a generated declaration has the type’s isolation, or the one its attributes spell, so
	/// a callee bound to another global actor than the type’s makes generated code that does not compile, with the
	/// compiler’s error in a generated file. A generated declaration whose attributes spell any isolation (a global
	/// actor or `nonisolated`) is stated, and is left to the compiler. A callee that spells `@preconcurrency` adds no
	/// isolation to what calls it (the generator does not mirror it either), so it is not reported.
	///
	/// A deliberate gap: a type whose conformance list names a type other than `Instantiable` or `Sendable` (a
	/// superclass, or a protocol bound to a global actor, such as `UIViewController` or SwiftUI’s `View`) can take its
	/// global actor from there, which the macro cannot see, so it is not reported. Neither is an `@Instantiable`
	/// extension, whose extended type’s isolation the macro cannot see, nor the mock of a type whose hand-written mock
	/// is in a separate `mockOnly` declaration.
	static func diagnoseUnstatedGlobalActorIsolation(
		of concreteDeclaration: ConcreteDeclSyntaxProtocol,
		instantiableMacro: AttributeSyntax,
		visitor: InstantiableVisitor,
		on declaration: some SyntaxProtocol,
		context: some MacroExpansionContext,
	) {
		guard !visitor.conformanceListNamesOtherTypes else { return }
		let typeIsolation = Initializer.spelledIsolation(modifiers: concreteDeclaration.modifiers, attributes: concreteDeclaration.attributes)
		let typeName = concreteDeclaration.name.text
		let constructionInitializer = zip(visitor.initializers, visitor.initializerSyntaxes).first { initializer, _ in
			initializer.isValid(forFulfilling: visitor.dependencies)
		}

		// SafeDI generates initializers only for a tree that builds something: a root or seam that instantiates no
		// dependency gets none, and its callers call its own initializer.
		let instantiatesDependency = visitor.dependencies.contains {
			if case .instantiated = $0.source { true } else { false }
		}
		let generatedInitializers: FixableInstantiableError.GeneratedIsolatedDeclaration? = if !instantiatesDependency {
			nil
		} else if visitor.generatesDependencyTree {
			.seamInitializers
		} else if visitor.isRoot {
			.rootInitializer
		} else {
			nil
		}
		if let generatedInitializers,
		   let (initializer, initializerSyntax) = constructionInitializer,
		   let globalActor = boundGlobalActor(of: initializer, attributes: initializerSyntax.attributes),
		   globalActor != typeIsolation,
		   !statesIsolation(visitor.generatedInitializerAttributes)
		{
			diagnoseUnstatedGlobalActorIsolation(
				globalActor: globalActor,
				callee: .initializer(typeName: typeName),
				generatedDeclaration: generatedInitializers,
				instantiableMacro: instantiableMacro,
				generatedAttributesText: visitor.generatedInitializerAttributes,
				on: declaration,
				context: context,
			)
		}

		guard instantiableMacro.generateMockValue, !visitor.mockOnly else { return }
		// A generated `mock()` calls the hand-written mock `customMockName` names, when there is one, and the
		// construction initializer otherwise.
		let mockCallee: (callee: FixableInstantiableError.IsolatedCallee, initializer: Initializer, attributes: AttributeListSyntax)? = if let mockFunctionSyntax = visitor.mockFunctionSyntax, let mockInitializer = visitor.mockInitializer {
			(.handWrittenMock(methodName: mockFunctionSyntax.name.text), mockInitializer, mockFunctionSyntax.attributes)
		} else {
			constructionInitializer.map { initializer, initializerSyntax in
				(.initializer(typeName: typeName), initializer, initializerSyntax.attributes)
			}
		}
		if let mockCallee,
		   let globalActor = boundGlobalActor(of: mockCallee.initializer, attributes: mockCallee.attributes),
		   globalActor != typeIsolation,
		   !statesIsolation(visitor.mockAttributes)
		{
			diagnoseUnstatedGlobalActorIsolation(
				globalActor: globalActor,
				callee: mockCallee.callee,
				generatedDeclaration: .mock,
				instantiableMacro: instantiableMacro,
				generatedAttributesText: visitor.mockAttributes,
				on: declaration,
				context: context,
			)
		}
	}

	/// The global actor `initializer` is bound to, as its declaration spells it (`"@MainActor"`): `nil` when it spells
	/// none, spells `nonisolated`, or spells `@preconcurrency`, which adds no isolation to what calls it.
	private static func boundGlobalActor(of initializer: Initializer, attributes: AttributeListSyntax) -> String? {
		guard let isolation = initializer.spelledIsolation,
		      isolation != "nonisolated",
		      !attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "preconcurrency" })
		else {
			return nil
		}
		return isolation
	}

	/// Whether `attributes`, the text of an attribute argument, states an isolation: a global actor, or `nonisolated`.
	private static func statesIsolation(_ attributes: String) -> Bool {
		Initializer.globalActorAttribute(in: attributes) != nil || attributes.split(separator: " ").contains("nonisolated")
	}

	private static func diagnoseUnstatedGlobalActorIsolation(
		globalActor: String,
		callee: FixableInstantiableError.IsolatedCallee,
		generatedDeclaration: FixableInstantiableError.GeneratedIsolatedDeclaration,
		instantiableMacro: AttributeSyntax,
		generatedAttributesText: String,
		on declaration: some SyntaxProtocol,
		context: some MacroExpansionContext,
	) {
		// `generatedAttributes` stands for both arguments, so the generated declaration reads it when it is given.
		let argumentLabel = instantiableMacro.generatedAttributes == nil ? generatedDeclaration.argumentLabel : "generatedAttributes"
		let error = FixableInstantiableError.unstatedGlobalActorIsolation(
			globalActor: globalActor,
			callee: callee,
			generatedDeclaration: generatedDeclaration,
			argumentLabel: argumentLabel,
		)
		context.diagnose(Diagnostic(
			node: Syntax(instantiableMacro),
			error: error,
			changes: addingAttribute(
				globalActor,
				toArgumentLabeled: argumentLabel,
				whoseTextIs: generatedAttributesText,
				of: instantiableMacro,
				on: declaration,
			),
		))
	}

	/// Builds fix-it changes that add `attribute` before the text of the argument `label` of an `@Instantiable`
	/// attribute, `text`, or that add the argument, in the position the macro’s parameters give it, when the attribute
	/// has none.
	private static func addingAttribute(
		_ attribute: String,
		toArgumentLabeled label: String,
		whoseTextIs text: String,
		of instantiableMacro: AttributeSyntax,
		on declaration: some SyntaxProtocol,
	) -> [FixIt.Change] {
		// safedi-source-rule: allow forceUnwrap — a declaration SafeDI generates is asked for by an argument (`isRoot`, `generateDependencyTree` or `generateMock`) that `isRootValue`, `InstantiableVisitor.generatesDependencyTree` and `generateMockValue` read from labeled arguments.
		var arguments = Array(LabeledExprListSyntax(instantiableMacro.arguments!)!)
		let attributesText = text.isEmpty ? attribute : "\(attribute) \(text)"
		if let index = arguments.firstIndex(where: { $0.label?.text == label }) {
			arguments[index].expression = ExprSyntax(StringLiteralExprSyntax(content: attributesText))
		} else {
			// Arguments follow the order of the macro’s parameters, and only these follow the attribute arguments.
			let labelsAfterAttributeArguments: Set = label == "mockAttributes"
				? ["generateMock", "customMockName"]
				: ["mockAttributes", "generateMock", "customMockName"]
			let insertionIndex = arguments.firstIndex { $0.label.map { labelsAfterAttributeArguments.contains($0.text) } ?? false } ?? arguments.endIndex
			var argument = LabeledExprSyntax(
				label: .identifier(label),
				colon: .colonToken(trailingTrivia: .space),
				expression: StringLiteralExprSyntax(content: attributesText),
			)
			if insertionIndex == arguments.endIndex {
				arguments[insertionIndex - 1].trailingComma = .commaToken(trailingTrivia: .space)
			} else {
				argument.trailingComma = .commaToken(trailingTrivia: .space)
			}
			arguments.insert(argument, at: insertionIndex)
		}
		var fixedAttribute = instantiableMacro
		fixedAttribute.arguments = .argumentList(LabeledExprListSyntax(arguments))
		let rewriter = AttributeRewriter(oldID: instantiableMacro.id, replacement: fixedAttribute)
		return [.replace(oldNode: Syntax(declaration), newNode: rewriter.rewrite(Syntax(declaration)))]
	}
}
