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

/// What SafeDI would learn from the declarations inside an `#if` block.
enum SafeDIContent: Int, Comparable {
	/// Nothing SafeDI scans for.
	case none
	/// Declarations that feed mock generation only: `mockOnly` types and hand-written mock methods.
	case mockOnly
	/// Declarations that feed the dependency tree.
	case production

	static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/// Where an `#if` block sits, which determines which declarations inside it matter.
enum SafeDIContentContext {
	/// Among type declarations, where `@Instantiable` types and `#SafeDIConfiguration` matter.
	case declarations
	/// Among the members of one `@Instantiable` declaration, where dependencies, initializers,
	/// and mock methods matter. Nested types are scanned separately among the declarations.
	case members(InstantiableMembers)

	struct InstantiableMembers {
		/// Whether the declaration is an extension, whose `instantiate()` method constructs the type.
		let isExtension: Bool
		/// Whether every member only feeds mock generation.
		let isMockOnly: Bool
		let customMockName: String?
	}
}

extension IfConfigDeclSyntax {
	func safeDIContent(in context: SafeDIContentContext) -> SafeDIContent {
		let detector = SafeDIContentDetector(context: context)
		detector.walk(self)
		return detector.content
	}
}

private final class SafeDIContentDetector: SyntaxVisitor {
	init(context: SafeDIContentContext) {
		self.context = context
		super.init(viewMode: .sourceAccurate)
	}

	private(set) var content = SafeDIContent.none

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes)
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes)
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes)
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		visitTypeDeclaration(node.attributes)
	}

	override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		switch context {
		case .declarations:
			// Enums can nest instantiable types.
			.visitChildren
		case .members:
			.skipChildren
		}
	}

	override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
		if case .declarations = context, node.macroName.text == SafeDIConfigurationVisitor.macroName {
			record(.production)
		}
		return .skipChildren
	}

	override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
		if case .members = context,
		   node.modifiers.staticModifier == nil,
		   !node.attributes.dependencySources.isEmpty
		{
			record(.production)
		}
		return .skipChildren
	}

	override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
		if case .members = context {
			record(.production)
		}
		return .skipChildren
	}

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		if case let .members(members) = context {
			let isStaticOrClass = node.modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
			let mockMethodNames = [InstantiableVisitor.mockMethodName, members.customMockName].compactMap { $0 }
			if isStaticOrClass, mockMethodNames.contains(node.name.text) {
				record(.mockOnly)
			} else if members.isExtension, node.name.text == InstantiableVisitor.instantiateMethodName {
				record(.production)
			}
		}
		return .skipChildren
	}

	// MARK: Private

	private let context: SafeDIContentContext

	private func visitTypeDeclaration(_ attributes: AttributeListSyntax) -> SyntaxVisitorContinueKind {
		switch context {
		case .declarations:
			if let instantiableMacro = attributes.instantiableMacro {
				record(instantiableMacro.mockOnlyValue ? .mockOnly : .production)
			}
			// Nested types may be instantiable too.
			return .visitChildren
		case .members:
			return .skipChildren
		}
	}

	private func record(_ found: SafeDIContent) {
		let foundInContext: SafeDIContent = switch context {
		case let .members(members) where members.isMockOnly:
			// Every member of a `mockOnly` declaration only feeds mock generation.
			min(found, .mockOnly)
		case .declarations, .members:
			found
		}
		content = max(content, foundInContext)
	}
}
