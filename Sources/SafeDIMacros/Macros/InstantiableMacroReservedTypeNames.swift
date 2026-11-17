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
	/// The prefixes of the names of the types SafeDI’s generated code declares beside the types a person declares, each
	/// reserved whole so that no generated name can collide with a person’s type: a seam’s root enums, `SafeDIScope_<Stem>`
	/// and `SafeDISendableScope_<Stem>`, which the seam’s module declares in an extension of the seam, and in which the
	/// types of the seam’s tree are spelled (`ScopeTypeNames.seam` in `SeamBuilderFamilies.swift`, which this target does
	/// not compile), and `ReservedName.builderFunctionNamePrefix`, the prefix of the builder struct `__safeDI_Builder`
	/// each of those enums declares.
	static let reservedTypeNamePrefixes = ["SafeDIScope_", "SafeDISendableScope_", ReservedName.builderFunctionNamePrefix]

	/// Reports `name`, the name of the type the macro decorates or extends, and the name of each type declared among
	/// `members` – in every clause of an `#if` block, and inside another type declared there – that begins with one of
	/// `reservedTypeNamePrefixes`. A type declared there that is itself `@Instantiable` is left to its own expansion,
	/// which reports its name and the types declared inside it, so that no name is reported twice.
	///
	/// The macro sees only these declarations, so it reports no type of such a name declared anywhere else: in a plain
	/// extension of the decorated type, or a type that is not `@Instantiable`.
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

	/// The token that names the type `type` spells, when it names one by itself or as a member of another type – `Api`
	/// in `Api` and in `Feature.Api` – or `nil` when it spells another kind of type.
	static func typeNameToken(of type: TypeSyntax) -> TokenSyntax? {
		IdentifierTypeSyntax(type)?.name ?? MemberTypeSyntax(type)?.name
	}

	/// Reports `name` when it begins with one of `reservedTypeNamePrefixes`.
	private static func diagnoseReservedTypeName(_ name: TokenSyntax, context: some MacroExpansionContext) {
		let typeName = name.text.spelledWithoutBackticks
		for prefix in reservedTypeNamePrefixes where typeName.utf8.starts(with: prefix.utf8) {
			context.diagnose(Diagnostic(
				node: name,
				message: ReservedTypeNameDiagnostic(typeName: typeName, prefix: prefix),
			))
		}
	}
}

// MARK: - ReservedTypeNameDiagnostic

/// The error at a type whose name begins with a prefix SafeDI reserves for the types in the code it generates.
private struct ReservedTypeNameDiagnostic: DiagnosticMessage {
	/// The error at the type named `typeName`, which begins with `prefix`.
	init(typeName: String, prefix: String) {
		message = "The type name `\(typeName)` begins with `\(prefix)`, a prefix SafeDI reserves for names in the code it generates. Rename the type so that its name does not begin with `\(prefix)`."
		diagnosticID = MessageID(domain: "\(Self.self)", id: "reservedTypeName")
		severity = .error
	}

	let message: String
	let diagnosticID: MessageID
	let severity: DiagnosticSeverity
}
