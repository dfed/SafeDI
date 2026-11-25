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
	/// a `mock()` – that calls a declaration spelling `@MainActor` while nothing states an isolation for the generated
	/// declaration, with a fix-it that adds `@MainActor` to the attribute argument the generated declaration reads.
	///
	/// SafeDI infers no isolation: a generated declaration has the type’s isolation, or the one its attributes spell, so
	/// a `@MainActor` callee of a type that states no isolation makes generated code that does not compile, with the
	/// compiler’s error in a generated file. The macro reads spellings only, and matches no actor by its name: it fires
	/// only where the callee spells exactly `@MainActor`, and stays quiet wherever anything else could state an
	/// isolation. The type, or the attribute argument the generated declaration reads, states one when it spells
	/// `nonisolated` or any attribute without arguments, which may be a global actor. A callee that spells
	/// `nonisolated` or `@preconcurrency` adds no isolation to what calls it (the generator does not mirror
	/// `@preconcurrency` either), so it is not reported; nor is a callee bound to another global actor, or to
	/// `@MainActor` spelled any other way.
	///
	/// A deliberate gap: a type whose conformance list names a type other than `Instantiable` or `Sendable` (a
	/// superclass, or a protocol bound to a global actor, such as `UIViewController` or SwiftUI’s `View`) can take its
	/// global actor from there, which the macro cannot see, so it is not reported. Neither is an `@Instantiable`
	/// extension, whose extended type’s isolation the macro cannot see, nor the mock of a type whose hand-written mock
	/// is in a separate `mockOnly` declaration. A type whose attribute list holds an `#if` clause is not reported either,
	/// since the clause may state its isolation.
	///
	/// When the root’s or seam’s initializers and the `mock()` are both reported, the first diagnostic’s fix-it adds
	/// `@MainActor` to every argument either reads, and the second has none, so that no two fix-its edit the attribute.
	/// Each fix-it replaces only the `@Instantiable` attribute.
	static func diagnoseUnstatedGlobalActorIsolation(
		of concreteDeclaration: ConcreteDeclSyntaxProtocol,
		instantiableMacro: AttributeSyntax,
		visitor: InstantiableVisitor,
		context: some MacroExpansionContext,
	) {
		guard !visitor.conformanceListNamesOtherTypes,
		      !statesIsolation(modifiers: concreteDeclaration.modifiers, attributes: concreteDeclaration.attributes, besides: instantiableMacro)
		else { return }
		let typeName = concreteDeclaration.name.text
		let constructionInitializer = zip(visitor.initializers, visitor.initializerSyntaxes).first { initializer, _ in
			initializer.isValid(forFulfilling: visitor.dependencies)
		}
		var findings = [UnstatedIsolation]()

		// SafeDI generates initializers only for a tree that builds something: a root or seam that instantiates no
		// dependency gets none, and its callers call its own initializer.
		let instantiatesDependency = visitor.dependencies.contains {
			if case .instantiated = $0.source {
				true
			} else {
				false
			}
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
		   let (_, initializerSyntax) = constructionInitializer,
		   spellsExactlyMainActor(modifiers: initializerSyntax.modifiers, attributes: initializerSyntax.attributes),
		   !statesIsolation(visitor.generatedInitializerAttributes)
		{
			findings.append(UnstatedIsolation(
				callee: .initializer(typeName: typeName),
				generatedDeclaration: generatedInitializers,
				generatedAttributesText: visitor.generatedInitializerAttributes,
			))
		}

		if instantiableMacro.generateMockValue, !visitor.mockOnly {
			// A generated `mock()` calls the hand-written mock `customMockName` names, when there is one, and the
			// construction initializer otherwise.
			let mockCallee: (callee: FixableInstantiableError.IsolatedCallee, modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax)? = if let mockFunctionSyntax = visitor.mockFunctionSyntax, visitor.mockInitializer != nil {
				(.handWrittenMock(methodName: mockFunctionSyntax.name.text), mockFunctionSyntax.modifiers, mockFunctionSyntax.attributes)
			} else {
				constructionInitializer.map { _, initializerSyntax in
					(.initializer(typeName: typeName), initializerSyntax.modifiers, initializerSyntax.attributes)
				}
			}
			if let mockCallee,
			   spellsExactlyMainActor(modifiers: mockCallee.modifiers, attributes: mockCallee.attributes),
			   !statesIsolation(visitor.mockAttributes)
			{
				findings.append(UnstatedIsolation(
					callee: mockCallee.callee,
					generatedDeclaration: .mock,
					generatedAttributesText: visitor.mockAttributes,
				))
			}
		}

		let globalActor = "@MainActor"
		// `generatedAttributes` stands for both arguments, so a generated declaration reads it when it is given.
		func argumentLabel(of finding: UnstatedIsolation) -> String {
			instantiableMacro.generatedAttributes == nil ? finding.generatedDeclaration.argumentLabel : "generatedAttributes"
		}
		// One fix-it adds the global actor to every argument a reported declaration reads, each once.
		var fixItArgumentLabels = [String]()
		var fixedAttribute = instantiableMacro
		for finding in findings where !fixItArgumentLabels.contains(argumentLabel(of: finding)) {
			let label = argumentLabel(of: finding)
			fixItArgumentLabels.append(label)
			fixedAttribute = addingAttribute(globalActor, toArgumentLabeled: label, whoseTextIs: finding.generatedAttributesText, of: fixedAttribute)
		}
		for (index, finding) in findings.enumerated() {
			let error = FixableInstantiableError.unstatedGlobalActorIsolation(
				globalActor: globalActor,
				callee: finding.callee,
				generatedDeclaration: finding.generatedDeclaration,
				argumentLabel: argumentLabel(of: finding),
				fixItArgumentLabels: fixItArgumentLabels,
			)
			if index == findings.startIndex {
				context.diagnose(Diagnostic(
					node: Syntax(instantiableMacro),
					error: error,
					changes: [.replace(oldNode: Syntax(instantiableMacro), newNode: Syntax(fixedAttribute))],
				))
			} else {
				// The first diagnostic’s fix-it already adds the global actor here, and a second fix-it editing the
				// same attribute would collide with it.
				context.diagnose(Diagnostic(node: Syntax(instantiableMacro), message: error.diagnostic))
			}
		}
	}

	/// A declaration SafeDI generates that calls a `@MainActor` callee while nothing states an isolation for it.
	private struct UnstatedIsolation {
		let callee: FixableInstantiableError.IsolatedCallee
		let generatedDeclaration: FixableInstantiableError.GeneratedIsolatedDeclaration
		/// The text of the attribute argument `generatedDeclaration` reads.
		let generatedAttributesText: String
	}

	/// Whether a callee spells exactly `@MainActor`, and neither `nonisolated` nor `@preconcurrency`, which leave what
	/// calls it unisolated.
	private static func spellsExactlyMainActor(modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax) -> Bool {
		var spellsMainActor = false
		for case let .attribute(attribute) in attributes {
			switch attribute.attributeName.trimmedDescription {
			case "MainActor" where attribute.arguments == nil:
				spellsMainActor = true
			case "preconcurrency":
				return false
			default:
				break
			}
		}
		return spellsMainActor && !modifiers.contains { $0.name.tokenKind == .keyword(.nonisolated) }
	}

	/// Whether a type states an isolation: it spells `nonisolated`, or an attribute without arguments other than
	/// `instantiableMacro`, which may be a global actor whatever its name, or an `#if` clause, which may hold one.
	private static func statesIsolation(
		modifiers: DeclModifierListSyntax,
		attributes: AttributeListSyntax,
		besides instantiableMacro: AttributeSyntax,
	) -> Bool {
		modifiers.contains { $0.name.tokenKind == .keyword(.nonisolated) }
			|| attributes.contains {
				switch $0 {
				case let .attribute(attribute):
					attribute.id != instantiableMacro.id && attribute.arguments == nil
				case .ifConfigDecl:
					true
				}
			}
	}

	/// Whether `attributes`, the text of an attribute argument, states an isolation: it spells `nonisolated`, or an
	/// attribute without arguments, which may be a global actor whatever its name.
	private static func statesIsolation(_ attributes: String) -> Bool {
		attributes.split(separator: " ").contains { $0 == "nonisolated" || ($0.hasPrefix("@") && !$0.contains("(")) }
	}

	/// Returns `instantiableMacro` with `attribute` added before the text of its argument `label`, `text`, or with the
	/// argument added, in the position the macro’s parameters give it, when the attribute has none.
	private static func addingAttribute(
		_ attribute: String,
		toArgumentLabeled label: String,
		whoseTextIs text: String,
		of instantiableMacro: AttributeSyntax,
	) -> AttributeSyntax {
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
		return fixedAttribute
	}
}
