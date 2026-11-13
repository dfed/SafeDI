import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

public struct PeerAddsStoredProperty: PeerMacro {
	public static func expansion(of _: AttributeSyntax, providingPeersOf _: some DeclSyntaxProtocol, in _: some MacroExpansionContext) throws -> [DeclSyntax] {
		["var addedByPeer: Int = 0"]
	}
}

public struct MemberAddsStoredProperty: MemberMacro {
	public static func expansion(of _: AttributeSyntax, providingMembersOf _: some DeclGroupSyntax, conformingTo _: [TypeSyntax], in _: some MacroExpansionContext) throws -> [DeclSyntax] {
		["var addedByMember: Int = 0"]
	}
}

@main
struct Plugin: CompilerPlugin {
	let providingMacros: [Macro.Type] = [PeerAddsStoredProperty.self, MemberAddsStoredProperty.self]
}
