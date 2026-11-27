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

// SafeDI infers no isolation: a declaration it generates – a root’s `init()`, a seam’s initializers, a `mock()` – has
// the type’s isolation, or the one its attribute text spells, or, where that text is empty in a module whose
// `#SafeDIConfiguration` declares `defaultIsolation: MainActor.self`, `@MainActor`. So a `@MainActor` callee of a type
// that states no isolation makes generated code that does not compile, with the compiler’s error in a generated file.
// `FileVisitor` records what one declaration shows (`InstantiableVisitor.unstatedGlobalActorIsolation`), and `generate`,
// which knows the module’s setting, reports each finding whose text that setting does not fill
// (`Instantiable.UnstatedGlobalActorIsolation.sourceDiagnostics(reporting:declaredAt:)`). The macro cannot see the setting,
// so the check is the tool’s.

extension InstantiableVisitor {
	/// The declarations SafeDI generates for the visited type declaration that call a declaration spelling `@MainActor`
	/// while nothing could make the generated declaration `@MainActor` too, or `nil` when there is none, the declaration
	/// is an extension, or the walk had no converter.
	///
	/// It reads spellings only, and matches no actor by its name: it knows the main actor by its two literal spellings,
	/// `@MainActor` and `@_Concurrency.MainActor`, and finds a callee that spells one of them. It never finds code that
	/// compiles, so it finds nothing wherever the type, or the attribute argument the generated declaration reads, spells
	/// an attribute without arguments other than `@preconcurrency` (or, on the type, SafeDI’s own `@Instantiable`): such
	/// an attribute may be the main actor under another name, a type alias of it, or a macro that adds it. A `nonisolated`
	/// there or a `@preconcurrency` on the type states an isolation the callee cannot be called from, so it does not keep
	/// it quiet. A callee that spells `nonisolated` or `@preconcurrency` adds no isolation to what calls it (the generator
	/// does not mirror `@preconcurrency` either), so it is not found; nor is a callee bound to any other global actor.
	///
	/// A deliberate gap: a type whose conformance list names a type other than `Instantiable` or `Sendable` (a
	/// superclass, or a protocol bound to a global actor, such as `UIViewController` or SwiftUI’s `View`) can take its
	/// global actor from there, which one declaration does not show, so it is not found. Neither is an `@Instantiable`
	/// extension, whose extended type’s isolation it does not show, nor the mock of a type whose hand-written mock is in a
	/// separate `mockOnly` declaration, nor a type whose attribute list holds an `#if` clause, which may hold an isolation.
	///
	/// Each fix-it replaces only the `@Instantiable` attribute, adds `@MainActor` to every argument a reported finding
	/// reads, each once, and drops a `nonisolated` the argument spells, which would contradict it.
	var unstatedGlobalActorIsolation: Instantiable.UnstatedGlobalActorIsolation? {
		guard let sourceLocationConverter,
		      let (instantiableMacro, attributes, typeName) = instantiableDeclarationSyntax,
		      !conformanceListNamesOtherTypes,
		      !Self.mayStateMainActor(attributes: attributes, besides: instantiableMacro)
		else { return nil }
		let constructionInitializer = zip(initializers, initializerSyntaxes).first { initializer, _ in
			initializer.isValid(forFulfilling: dependencies)
		}
		var findings = [(generatedDeclaration: Instantiable.UnstatedGlobalActorIsolation.GeneratedDeclaration, handWrittenMockName: String?, attributesText: String)]()

		// SafeDI generates initializers only for a tree that builds something: a root or seam that instantiates no
		// dependency gets none, and its callers call its own initializer.
		let instantiatesDependency = dependencies.contains {
			if case .instantiated = $0.source {
				true
			} else {
				false
			}
		}
		let generatedInitializers: Instantiable.UnstatedGlobalActorIsolation.GeneratedDeclaration? = if !instantiatesDependency {
			nil
		} else if generatesDependencyTree {
			.seamInitializers
		} else if isRoot {
			.rootInitializer
		} else {
			nil
		}
		if let generatedInitializers,
		   let (_, initializerSyntax) = constructionInitializer,
		   Self.spellsMainActor(modifiers: initializerSyntax.modifiers, attributes: initializerSyntax.attributes),
		   !Self.mayStateMainActor(generatedInitializerAttributes)
		{
			findings.append((generatedInitializers, nil, generatedInitializerAttributes))
		}

		if generateMock.generatesMock, !mockOnly {
			// A generated `mock()` calls the hand-written mock `customMockName` names, when there is one, and the
			// construction initializer otherwise.
			let mockCallee: (handWrittenMockName: String?, modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax)? = if let mockFunctionSyntax, mockInitializer != nil {
				(mockFunctionSyntax.name.text, mockFunctionSyntax.modifiers, mockFunctionSyntax.attributes)
			} else {
				constructionInitializer.map { _, initializerSyntax in
					(nil, initializerSyntax.modifiers, initializerSyntax.attributes)
				}
			}
			if let mockCallee,
			   Self.spellsMainActor(modifiers: mockCallee.modifiers, attributes: mockCallee.attributes),
			   !Self.mayStateMainActor(mockAttributes)
			{
				findings.append((.mock, mockCallee.handWrittenMockName, mockAttributes))
			}
		}
		guard !findings.isEmpty else { return nil }

		// `generatedAttributes` stands for both arguments, so a generated declaration reads it when it is given.
		func argumentLabel(of generatedDeclaration: Instantiable.UnstatedGlobalActorIsolation.GeneratedDeclaration) -> String {
			instantiableMacro.generatedAttributes == nil ? generatedDeclaration.argumentLabel : "generatedAttributes"
		}
		var fixedLabels = [String]()
		var attributeFixingEveryFinding = instantiableMacro
		for finding in findings where !fixedLabels.contains(argumentLabel(of: finding.generatedDeclaration)) {
			let label = argumentLabel(of: finding.generatedDeclaration)
			fixedLabels.append(label)
			attributeFixingEveryFinding = Self.addingMainActor(toArgumentLabeled: label, whoseTextIs: finding.attributesText, of: attributeFixingEveryFinding)
		}
		return Instantiable.UnstatedGlobalActorIsolation(
			typeName: typeName,
			attributeRange: sourceLocationConverter.sourceRange(of: instantiableMacro),
			findings: findings.map { finding in
				let label = argumentLabel(of: finding.generatedDeclaration)
				return Instantiable.UnstatedGlobalActorIsolation.Finding(
					generatedDeclaration: finding.generatedDeclaration,
					handWrittenMockName: finding.handWrittenMockName,
					argumentLabel: label,
					attributeFixingFinding: Self.addingMainActor(toArgumentLabeled: label, whoseTextIs: finding.attributesText, of: instantiableMacro).trimmedDescription,
				)
			},
			attributeFixingEveryFinding: attributeFixingEveryFinding.trimmedDescription,
		)
	}

	/// Whether a callee spells `@MainActor` or `@_Concurrency.MainActor`, and neither `nonisolated` nor
	/// `@preconcurrency`, which leave what calls it unisolated.
	private static func spellsMainActor(modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax) -> Bool {
		var spellsMainActor = false
		for case let .attribute(attribute) in attributes {
			// The main actor’s two literal spellings.
			switch attribute.attributeName.trimmedDescription {
			case "MainActor" where attribute.arguments == nil,
			     "_Concurrency.MainActor" where attribute.arguments == nil:
				spellsMainActor = true
			case "preconcurrency":
				return false
			default:
				break
			}
		}
		return spellsMainActor && !modifiers.contains { $0.name.tokenKind == .keyword(.nonisolated) }
	}

	/// Whether a type’s attributes may make it `@MainActor`: an attribute without arguments other than
	/// `instantiableMacro` and `@preconcurrency`, which may be the main actor under any name, or an `#if` clause, which
	/// may hold one.
	private static func mayStateMainActor(attributes: AttributeListSyntax, besides instantiableMacro: AttributeSyntax) -> Bool {
		attributes.contains {
			switch $0 {
			case let .attribute(attribute):
				attribute.id != instantiableMacro.id
					&& attribute.arguments == nil
					&& attribute.attributeName.trimmedDescription != "preconcurrency"
			case .ifConfigDecl:
				true
			}
		}
	}

	/// Whether `attributes`, the text of an attribute argument, may make the generated declaration `@MainActor`: it
	/// spells an attribute without arguments, which may be the main actor under any name.
	private static func mayStateMainActor(_ attributes: String) -> Bool {
		// safedi-source-rule: allow stringScan — reads one attribute argument’s short text, at most twice per `@Instantiable` type whose generated declarations call a `@MainActor` declaration, once when its file is read.
		attributes.split(separator: " ").contains { $0.hasPrefix("@") && !$0.contains("(") }
	}

	/// Returns `instantiableMacro` with `@MainActor` added before the text of its argument `label`, `text`, less any
	/// `nonisolated`, or with the argument added, in the position the macro’s parameters give it, when the attribute has
	/// none.
	private static func addingMainActor(
		toArgumentLabeled label: String,
		whoseTextIs text: String,
		of instantiableMacro: AttributeSyntax,
	) -> AttributeSyntax {
		// safedi-source-rule: allow forceUnwrap — a declaration SafeDI generates is asked for by an argument (`isRoot`, `generateDependencyTree` or `generateMock`) that `isRootValue`, `InstantiableVisitor.generatesDependencyTree` and `mockGenerationValue` read from labeled arguments.
		var arguments = Array(LabeledExprListSyntax(instantiableMacro.arguments!)!)
		// A `nonisolated` the argument spells would contradict the attribute added.
		// safedi-source-rule: allow stringScan — splits one attribute argument’s short text, once per finding, only while a fix-it is built.
		let words = text.split(separator: " ")
		// safedi-source-rule: allow stringScan — membership among the few words of one attribute argument, once per finding.
		let keptText = words.contains("nonisolated") ? words.filter { $0 != "nonisolated" }.joined(separator: " ") : text
		let attributesText = keptText.isEmpty ? mainActorAttribute : "\(mainActorAttribute) \(keptText)"
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

/// The attribute the check reports a missing isolation with, and its fix-it adds.
private let mainActorAttribute = "@MainActor"

extension Instantiable.UnstatedGlobalActorIsolation {
	/// The errors that report `reported`, findings of this declaration, at its `@Instantiable` attribute in the file of
	/// `declarationLocation`. The first carries the fix-it, which adds `@MainActor` to every argument a reported finding
	/// reads, so that no two fix-its edit the attribute.
	public func sourceDiagnostics(reporting reported: [Finding], declaredAt declarationLocation: Dependency.DeclarationLocation) -> [SourceDiagnostic] {
		let fixedAttribute = reported.count == findings.count ? attributeFixingEveryFinding : reported.first?.attributeFixingFinding
		let location = { () -> Dependency.DeclarationLocation in
			// A range read without its positions is reported at the declaration, as `mockGenerationArgumentLocation` is.
			guard case let .here(startLine, startColumn, _, _) = attributeRange.placement else { return declarationLocation }
			return Dependency.DeclarationLocation(filePath: declarationLocation.filePath, line: startLine, column: startColumn)
		}()
		return reported.enumerated().map { index, finding in
			SourceDiagnostic(
				severity: .error,
				location: location,
				message: message(reporting: finding),
				fixIts: index == reported.startIndex ? fixedAttribute.map { [SourceDiagnostic.FixIt(range: attributeRange, replacement: $0)] } ?? [] : [],
			)
		}
	}

	private func message(reporting finding: Finding) -> String {
		let callee = finding.handWrittenMockName.map { "The hand-written mock `\($0)(…)`" } ?? "`\(typeName)`’s initializer"
		return "\(callee) is `\(mainActorAttribute)`, and \(finding.generatedDeclaration.callsClause), so \(finding.generatedDeclaration.mustBeClause) `\(mainActorAttribute)` too. SafeDI does not infer the isolation of the code it generates: add `\(mainActorAttribute)` to `\(finding.argumentLabel)`."
	}
}

extension Instantiable.UnstatedGlobalActorIsolation.GeneratedDeclaration {
	/// The attribute argument whose text the declaration carries, other than `generatedAttributes`.
	fileprivate var argumentLabel: String {
		switch self {
		case .rootInitializer, .seamInitializers:
			"generatedInitializerAttributes"
		case .mock:
			"mockAttributes"
		}
	}

	/// The clause that says the generated declaration calls the callee.
	fileprivate var callsClause: String {
		switch self {
		case .rootInitializer:
			"the `init()` SafeDI generates for this root calls it"
		case .seamInitializers:
			"the initializers SafeDI generates for this type with `generateDependencyTree: true` call it"
		case .mock:
			"the `mock()` SafeDI generates calls it"
		}
	}

	/// The clause that names the generated declaration as what must be bound to the global actor, before the actor.
	fileprivate var mustBeClause: String {
		switch self {
		case .rootInitializer:
			"that `init()` must be"
		case .seamInitializers:
			"they must be"
		case .mock:
			"that `mock()` must be"
		}
	}

	/// Whether the module’s declared `defaultIsolation` fills the text this declaration reads in `instantiable`, so that
	/// the declaration is `@MainActor` with no text written.
	public func isFilledByModuleDefaultIsolation(in instantiable: Instantiable) -> Bool {
		switch self {
		case .rootInitializer, .seamInitializers:
			instantiable.initializerUsesModuleDefaultIsolation
		case .mock:
			instantiable.usesModuleDefaultIsolation
		}
	}
}
