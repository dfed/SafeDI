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
	/// Reports `name`, the name of the type the macro decorates or extends, and the name of each type declared among
	/// `members` – in every clause of an `#if` block, and inside another type declared there – that begins with one of
	/// `ReservedName.reservedTypeNamePrefixes`. A type declared there that is itself `@Instantiable` is left to its own expansion,
	/// which reports its name and the types declared inside it, so that no name is reported twice.
	///
	/// The macro sees only these declarations; SafeDITool reports a type of such a name declared anywhere else in the
	/// module's own files – in a plain extension of the decorated type, or a type that is not `@Instantiable` – and
	/// `diagnoseReservedTypeNamesSpelled(by:among:context:)` reports a spelling of one in the declaration.
	static func diagnoseReservedTypeNames(
		declaredBy name: TokenSyntax?,
		among members: MemberBlockItemListSyntax,
		context: some MacroExpansionContext,
	) {
		if let name {
			diagnoseReservedTypeName(name, context: context)
		}
		for declaration in declarations(in: members) where declaration.asProtocol(WithAttributesSyntax.self)?.attributes.instantiableMacro == nil {
			if let nestedTypeName = declaration.nestedTypeNameToken {
				diagnoseReservedTypeName(nestedTypeName, context: context)
			}
			if let nestedTypeDeclaration = declaration.asProtocol(DeclGroupSyntax.self) {
				diagnoseReservedTypeNames(declaredBy: nil, among: nestedTypeDeclaration.memberBlock.members, context: context)
			}
		}
	}

	/// Reports each name spelled by the declarations the macro reads that begins with one of
	/// `ReservedName.reservedTypeNamePrefixes` and that Swift resolves lexically: the first name of each type spelling,
	/// wherever the spelling nests (a generic argument, a tuple, a closure, an optional, `any`, an attribute). Generated
	/// code spells these types in scopes where a type SafeDI generates can hide one of such a name, wherever the type is
	/// declared – in another module, or in one SafeDI never reads. A name qualified by another (`Outer.SafeDIScope_X`)
	/// resolves as a member of the type before it, which a generated type cannot hide, so it is not reported.
	/// - Parameters:
	///   - memberDeclarations: The members of the decorated declaration, with those in every clause of its `#if` blocks,
	///     whose dependencies' property types, alias `ofType:` arguments and `fulfilledByType:` arguments are read.
	///   - functionSignatures: The initializers, `instantiate(…)` methods and hand-written mock methods whose parameters'
	///     types are read.
	///   - returningSignatures: The `instantiate(…)` methods and hand-written mock methods, whose return types are read.
	static func diagnoseReservedTypeNamesSpelled(
		byDependenciesAmong memberDeclarations: [DeclSyntax],
		parametersOf functionSignatures: [FunctionSignatureSyntax],
		returnTypesOf returningSignatures: [FunctionSignatureSyntax],
		context: some MacroExpansionContext,
	) {
		var spellings = [Syntax]()
		// Each name, with the node it is reported at.
		var names = [(name: TokenSyntax, node: Syntax)]()
		let variables = memberDeclarations
			.compactMap(VariableDeclSyntax.init)
			.map { (declaration: $0, dependencyAttributes: $0.attributes.dependencySources.map(\.attribute)) }
		for variable in variables where !variable.dependencyAttributes.isEmpty {
			spellings += variable.declaration.bindings.compactMap { $0.typeAnnotation.map { Syntax($0.type) } }
			for attribute in variable.dependencyAttributes {
				if let ofType = attribute.ofType {
					spellings.append(Syntax(ofType))
				}
				// `fulfilledByType:` spells its type in a string, which is read as the type it names and reported at the string.
				if let fulfilledByType = attribute.fulfilledByType.flatMap(StringLiteralExprSyntax.init),
				   case let .stringSegment(segment) = fulfilledByType.segments.first
				{
					names += firstNames(spelledBy: Syntax(TypeSyntax(stringLiteral: segment.content.text))).map { ($0, Syntax(fulfilledByType)) }
				}
			}
		}
		spellings += functionSignatures.flatMap { $0.parameterClause.parameters.map { Syntax($0.type) } }
		spellings += returningSignatures.compactMap { $0.returnClause.map { Syntax($0.type) } }
		names += spellings.flatMap(firstNames(spelledBy:)).map { ($0, Syntax($0)) }
		// In source order, whichever list found each name.
		for (name, node) in names.sorted(by: { $0.node.positionAfterSkippingLeadingTrivia < $1.node.positionAfterSkippingLeadingTrivia }) {
			diagnoseReservedTypeName(name, at: node, context: context)
		}
	}

	/// The token that names the type `type` spells, when it names one by itself or as a member of another type – `Api`
	/// in `Api` and in `Feature.Api` – or `nil` when it spells another kind of type.
	static func typeNameToken(of type: TypeSyntax) -> TokenSyntax? {
		IdentifierTypeSyntax(type)?.name ?? MemberTypeSyntax(type)?.name
	}

	/// Reports `name` when it begins with one of `ReservedName.reservedTypeNamePrefixes`, at `node`, or at `name` itself.
	private static func diagnoseReservedTypeName(_ name: TokenSyntax, at node: Syntax? = nil, context: some MacroExpansionContext) {
		let typeName = name.text.spelledWithoutBackticks
		if let prefix = ReservedName.reservedTypeNamePrefix(of: typeName) {
			context.diagnose(Diagnostic(
				node: node ?? Syntax(name),
				message: ReservedTypeNameDiagnostic(typeName: typeName, prefix: prefix),
			))
		}
	}

	/// The names `spelling`, a type or an expression that spells one (`ofType: Feature.Api.self`), resolves lexically: the
	/// first name of each type it spells, at any depth, in source order.
	private static func firstNames(spelledBy spelling: Syntax) -> [TokenSyntax] {
		let finder = FirstTypeNameFinder(viewMode: .sourceAccurate)
		finder.walk(spelling)
		return finder.names
	}
}

// MARK: - FirstTypeNameFinder

/// Finds the first name of each type a type or an expression spells: a type's name that no other name qualifies, and an
/// expression's name that is not a member of what precedes it.
private final class FirstTypeNameFinder: SyntaxVisitor {
	private(set) var names = [TokenSyntax]()

	override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
		names.append(node.name)
		return .visitChildren
	}

	override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
		if node.keyPathInParent != \MemberAccessExprSyntax.declName {
			names.append(node.baseName)
		}
		return .visitChildren
	}
}

// MARK: - ReservedTypeNameDiagnostic

/// The error at a type whose name begins with a prefix SafeDI reserves for the types in the code it generates.
private struct ReservedTypeNameDiagnostic: DiagnosticMessage {
	/// The error at the type named `typeName`, which begins with `prefix`.
	init(typeName: String, prefix: String) {
		message = ReservedName.reservedTypeNameMessage(typeName: typeName, prefix: prefix)
		diagnosticID = MessageID(domain: "\(Self.self)", id: "reservedTypeName")
		severity = .error
	}

	let message: String
	let diagnosticID: MessageID
	let severity: DiagnosticSeverity
}
