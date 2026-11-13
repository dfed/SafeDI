import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// Appends one line per expansion to /tmp/expansions.log: role, declaration, and the
/// frontend job that asked (its mode and primary files, read from /proc on Linux).
func log(_ role: String, _ declaration: some SyntaxProtocol, _ context: some MacroExpansionContext) {
	let type = context.lexicalContext.lazy.compactMap { $0.asProtocol(NamedDeclSyntax.self)?.name.text }.first
	let name = declaration.as(VariableDeclSyntax.self)?.bindings.first?.pattern.trimmedDescription
		?? declaration.as(FunctionDeclSyntax.self)?.name.text
		?? declaration.asProtocol(NamedDeclSyntax.self)?.name.text ?? "?"
	let line = Array("\(role) \([type, name].compactMap(\.self).joined(separator: ".")) \(job)\n".utf8)
	// O_APPEND, so lines from the compiler's concurrent jobs don't overwrite each other.
	let file = open("/tmp/expansions.log", O_WRONLY | O_APPEND | O_CREAT, 0o644)
	_ = line.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
	close(file)
}

let job: String = {
	let parent = getppid()
	guard let data = FileManager.default.contents(atPath: "/proc/\(parent)/cmdline") else { return "frontend-pid=\(parent)" }
	let arguments = data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
	let mode = arguments.contains("-c") ? "compile" : arguments.contains("-emit-module") ? "emit-module" : "other"
	let primaries = arguments.indices.dropLast().filter { arguments[$0] == "-primary-file" }
		.map { URL(fileURLWithPath: arguments[$0 + 1]).lastPathComponent }
	return primaries.isEmpty ? mode : "\(mode)[\(primaries.joined(separator: ","))]"
}()

public struct NoopPeerMacro: PeerMacro {
	public static func expansion(of _: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
		log("peer", declaration, context)
		return []
	}
}

public struct NoopMemberMacro: MemberMacro {
	public static func expansion(of _: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo _: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
		log("member", declaration, context)
		return []
	}
}

@main
struct Plugin: CompilerPlugin {
	let providingMacros: [Macro.Type] = [NoopPeerMacro.self, NoopMemberMacro.self]
}
