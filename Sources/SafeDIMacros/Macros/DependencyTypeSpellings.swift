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

/// The types of a declaration's dependencies as its author spelled them, for the code a fix-it adds. SafeDI reads
/// a wrapper spelled with its module's name (`SafeDI.Instantiator<B>`) as the bare wrapper, so a dependency's type
/// is bare; a fix-it that spelled it so would rewrite what the person wrote. The spellings are read from the
/// declaration's stored properties and the parameters of its `instantiate(…)` methods, keyed by the property
/// SafeDI reads, and only where the two differ, so a declaration spelled without SafeDI's module name keeps none.
struct DependencyTypeSpellings {
	init(of declaration: some DeclGroupSyntax) {
		let collector = SpellingCollector(viewMode: .sourceAccurate)
		collector.walk(declaration.memberBlock)
		spelledProperties = collector.spelledProperties
	}

	/// `property` with its type as the declaration spells it.
	func spelled(_ property: Property) -> Property {
		spelledProperties[property] ?? property
	}

	/// `properties`, each with its type as the declaration spells it.
	func spelled(_ properties: [Property]) -> [Property] {
		properties.map(spelled)
	}

	/// `dependencies`, each with its property's type as the declaration spells it, for code a fix-it adds alone.
	func spelled(_ dependencies: [Dependency]) -> [Dependency] {
		dependencies.map {
			Dependency(property: spelled($0.property), source: $0.source)
		}
	}

	private let spelledProperties: [Property: Property]

	/// Walks the members of one declaration and of the types declared inside it. A nested type's member can only
	/// add the spelling of a property of the same label and type, which no fix-it here tells apart.
	private final class SpellingCollector: SyntaxVisitor {
		var spelledProperties = [Property: Property]()

		override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
			for binding in node.bindings {
				if let identifier = IdentifierPatternSyntax(binding.pattern)?.identifier,
				   let type = binding.typeAnnotation?.type
				{
					record(label: identifier.text.spelledAsIdentifier, type: type)
				}
			}
			return .skipChildren
		}

		override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
			if node.name.text == InstantiableVisitor.instantiateMethodName {
				for parameter in node.signature.parameterClause.parameters {
					record(label: Initializer.Argument(parameter).innerLabel, type: parameter.type)
				}
			}
			return .skipChildren
		}

		private func record(label: String, type: TypeSyntax) {
			let property = Property(label: label, typeDescription: type.typeDescription)
			let spelledType = ModuleQualifiedWrapperSpelling().rewrite(type).as(TypeSyntax.self)?.typeDescription ?? property.typeDescription
			guard spelledType.asSource != property.typeDescription.asSource, spelledProperties[property] == nil else { return }
			spelledProperties[property] = Property(label: label, typeDescription: spelledType)
		}
	}

	/// Rewrites each wrapper spelled with SafeDI's module name as one name that holds the qualifier, so the type it
	/// parses to spells it as written, in place of the bare wrapper the parse reads it as.
	private final class ModuleQualifiedWrapperSpelling: SyntaxRewriter {
		override func visit(_ node: MemberTypeSyntax) -> TypeSyntax {
			let rewritten = super.visit(node)
			guard let memberType = MemberTypeSyntax(rewritten),
			      memberType.baseType.namesSafeDIModule,
			      Dependency.isWrapperTypeName(memberType.name.text)
			else { return rewritten }
			return TypeSyntax(IdentifierTypeSyntax(
				name: .identifier("\(Dependency.safeDIModuleName).\(memberType.name.text)"),
				genericArgumentClause: memberType.genericArgumentClause,
			))
		}
	}
}
