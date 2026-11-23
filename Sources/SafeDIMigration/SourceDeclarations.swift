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

/// What the rewriter needs to know of the project's own declarations, gathered from every file before any is rewritten.
struct SourceDeclarations: Sendable {
	init(trees: [SourceFileSyntax]) {
		let collector = DeclarationCollector(viewMode: .sourceAccurate)
		for tree in trees {
			collector.walk(tree)
		}
		handWrittenMockTypes = collector.handWrittenMockTypes
		typealiasTargets = collector.typealiasTargets
		genericParameterNames = collector.genericParameterNames
	}

	/// Each `@Instantiable` type, by its dotted name, that declares a hand-written `static func mock` and no
	/// `customMockName`: SafeDI finds that mock by its name, so 3.0 finds it as `fake`.
	let handWrittenMockTypes: Set<String>
	/// Each typealias's name, with the type it stands for as written.
	let typealiasTargets: [String: String]
	/// Each generic parameter's name declared anywhere in the sources.
	let genericParameterNames: Set<String>
}

/// SafeDI's instantiable attribute and the declarations it decorates.
enum InstantiableAttribute {
	/// The `@Instantiable` attribute in `attributes`, if any.
	static func attribute(in attributes: AttributeListSyntax) -> AttributeSyntax? {
		attributes.lazy
			.compactMap { $0.as(AttributeSyntax.self) }
			.first { $0.attributeName.trimmedDescription == "Instantiable" }
	}

	/// Whether the declaration is `@Instantiable` with no `customMockName`, so a `static func mock` in it is its
	/// hand-written mock.
	static func findsMockByName(_ attributes: AttributeListSyntax) -> Bool {
		guard let attribute = attribute(in: attributes) else { return false }
		let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) ?? []
		return !arguments.contains { $0.label?.text == "customMockName" }
	}

	/// Whether `function` is a static `mock` method.
	static func isStaticMock(_ function: FunctionDeclSyntax) -> Bool {
		function.name.text == "mock" && function.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
	}
}

/// A type declaration's name and members, whichever kind of declaration it is.
struct TypeDeclarationParts {
	init?(_ node: some SyntaxProtocol) {
		if let declaration = node.as(ClassDeclSyntax.self) {
			name = declaration.name.text
			attributes = declaration.attributes
		} else if let declaration = node.as(StructDeclSyntax.self) {
			name = declaration.name.text
			attributes = declaration.attributes
		} else if let declaration = node.as(ActorDeclSyntax.self) {
			name = declaration.name.text
			attributes = declaration.attributes
		} else if let declaration = node.as(EnumDeclSyntax.self) {
			name = declaration.name.text
			attributes = declaration.attributes
		} else if let declaration = node.as(ExtensionDeclSyntax.self) {
			name = declaration.extendedType.trimmedDescription
			attributes = declaration.attributes
		} else {
			return nil
		}
	}

	let name: String
	let attributes: AttributeListSyntax
}

private final class DeclarationCollector: SyntaxVisitor {
	var handWrittenMockTypes = Set<String>()
	var typealiasTargets = [String: String]()
	var genericParameterNames = Set<String>()
	private var typeStack = [String]()

	override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(node.name.text, node.attributes, node.memberBlock)
	}

	override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(node.name.text, node.attributes, node.memberBlock)
	}

	override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(node.name.text, node.attributes, node.memberBlock)
	}

	override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(node.name.text, node.attributes, node.memberBlock)
	}

	override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
		enter(node.extendedType.trimmedDescription, node.attributes, node.memberBlock)
	}

	override func visitPost(_: ClassDeclSyntax) {
		typeStack.removeLast()
	}

	override func visitPost(_: StructDeclSyntax) {
		typeStack.removeLast()
	}

	override func visitPost(_: ActorDeclSyntax) {
		typeStack.removeLast()
	}

	override func visitPost(_: EnumDeclSyntax) {
		typeStack.removeLast()
	}

	override func visitPost(_: ExtensionDeclSyntax) {
		typeStack.removeLast()
	}

	private func enter(_ typeName: String, _ attributes: AttributeListSyntax, _ memberBlock: MemberBlockSyntax) -> SyntaxVisitorContinueKind {
		let name = (typeStack + [typeName]).joined(separator: ".")
		let declaresMock = memberBlock.members.contains { member in
			member.decl.as(FunctionDeclSyntax.self).map(InstantiableAttribute.isStaticMock) ?? false
		}
		if declaresMock, InstantiableAttribute.findsMockByName(attributes) {
			handWrittenMockTypes.insert(name)
		}
		typeStack.append(typeName)
		return .visitChildren
	}

	override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
		typealiasTargets[node.name.text] = node.initializer.value.trimmedDescription
		return .visitChildren
	}

	override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind {
		genericParameterNames.insert(node.name.text)
		return .visitChildren
	}
}

/// The mocked types of the role file and the hand-written mocks of the sources, by the name a call spells.
struct MockedTypeIndex: Sendable {
	init(roles: MigrationRoles, handWrittenMockTypes: Set<String>) {
		var entriesByName = [String: [MigrationRoles.MockedType]]()
		for mockedType in roles.mockedTypes {
			entriesByName[mockedType.type, default: []].append(mockedType)
		}
		self.entriesByName = entriesByName
		self.handWrittenMockTypes = handWrittenMockTypes
		moduleNames = Set(roles.mockedTypes.compactMap(\.module))
	}

	enum Resolution: Equatable {
		/// A type whose `mock()` 2.x generates.
		case generated(MigrationRoles.MockedType)
		/// A type whose hand-written `mock` 2.x finds by name.
		case handWritten
		/// A name two modules generate a mock for.
		case ambiguous
	}

	/// What the dotted type name `name` is, where `module` is the module a call spells before it.
	func resolution(of name: String, inModule module: String?) -> Resolution? {
		if let entries = entriesByName[name] {
			let inModule = entries.filter { $0.module == module }
			let candidates = inModule.isEmpty ? entries : inModule
			if candidates.count == 1 {
				return .generated(candidates[0])
			} else {
				return .ambiguous
			}
		} else if handWrittenMockTypes.contains(name) {
			return .handWritten
		} else {
			return nil
		}
	}

	/// Resolves a type name as a call writes it, from inside the types `enclosingTypes` names, outermost first: a
	/// leading module name is read as one, and a name is looked up nested in each enclosing type, innermost first,
	/// before it is looked up as written, as Swift resolves it.
	func resolve(_ written: String, enclosingTypes: [String]) -> Resolution? {
		var components = written.split(separator: ".").map(String.init)
		var module: String?
		if components.count > 1, moduleNames.contains(components[0]) {
			module = components.removeFirst()
		}
		let name = components.joined(separator: ".")
		for depth in stride(from: module == nil ? enclosingTypes.count : 0, through: 0, by: -1) {
			let candidate = (enclosingTypes.prefix(depth) + [name]).joined(separator: ".")
			if let resolution = resolution(of: candidate, inModule: module) {
				return resolution
			}
		}
		return nil
	}

	private let entriesByName: [String: [MigrationRoles.MockedType]]
	private let handWrittenMockTypes: Set<String>
	private let moduleNames: Set<String>
}
