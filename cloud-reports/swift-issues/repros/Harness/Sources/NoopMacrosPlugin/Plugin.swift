import Foundation
import SwiftCompilerPlugin
@_spi(PluginMessage) import SwiftCompilerPluginMessageHandling
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - The macros: each expands to nothing and logs one line.

public struct NoopPeerMacro: PeerMacro {
	public static func expansion(
		of _: AttributeSyntax,
		providingPeersOf declaration: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext,
	) throws -> [DeclSyntax] {
		Log.expansion("peer", of: declaration, in: context)
		return []
	}
}

public struct NoopMemberMacro: MemberMacro {
	public static func expansion(
		of _: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo _: [TypeSyntax],
		in context: some MacroExpansionContext,
	) throws -> [DeclSyntax] {
		Log.expansion("member", of: declaration, in: context)
		return []
	}
}

// MARK: - Logging

enum Log {
	/// Appends to $NOOP_MACRO_LOG, or /tmp/noop-macro.log.
	static let path = ProcessInfo.processInfo.environment["NOOP_MACRO_LOG"] ?? "/tmp/noop-macro.log"

	/// Which frontend job this plugin process serves, read from the parent's command line (Linux).
	static let job: String = {
		guard let data = FileManager.default.contents(atPath: "/proc/\(getppid())/cmdline") else { return "unknown" }
		var arguments: [String] = []
		for argument in data.split(separator: 0).map({ String(decoding: $0, as: UTF8.self) }) {
			// Expand response files (`@path`, one argument per line, possibly quoted).
			if argument.hasPrefix("@"), let contents = try? String(contentsOfFile: String(argument.dropFirst()), encoding: .utf8) {
				arguments += contents.split(separator: "\n").map {
					$0.count >= 2 && $0.hasPrefix("\"") && $0.hasSuffix("\"") ? String($0.dropFirst().dropLast()) : String($0)
				}
			} else {
				arguments.append(argument)
			}
		}
		var primaries: [String] = []
		for (index, argument) in arguments.enumerated() where index + 1 < arguments.count {
			if argument == "-primary-file" {
				primaries.append((arguments[index + 1] as NSString).lastPathComponent)
			} else if argument == "-primary-filelist",
			          let list = try? String(contentsOfFile: arguments[index + 1], encoding: .utf8)
			{
				primaries += list.split(separator: "\n").map { ($0 as NSString).lastPathComponent }
			}
		}
		let kind: String = if arguments.contains("-c") {
			arguments.contains("-whole-module-optimization") ? "compile-wmo" : "compile"
		} else if arguments.contains("-emit-module") {
			arguments.contains("-whole-module-optimization") ? "emit-module-wmo" : "emit-module"
		} else {
			"other"
		}
		if primaries.isEmpty, FileManager.default.fileExists(atPath: "/tmp/noop-macro-arguments") {
			_ = FileManager.default.createFile(atPath: "/tmp/noop-macro-arguments/\(getppid()).txt", contents: Data(arguments.joined(separator: "\n").utf8))
		}
		return primaries.isEmpty ? kind : "\(kind)[\(primaries.joined(separator: ","))]"
	}()

	/// User plus system CPU time this plugin process has used so far.
	static func cpuMicroseconds() -> Int {
		var usage = rusage()
		getrusage(0 /* RUSAGE_SELF */, &usage)
		return (Int(usage.ru_utime.tv_sec) + Int(usage.ru_stime.tv_sec)) * 1_000_000
			+ Int(usage.ru_utime.tv_usec) + Int(usage.ru_stime.tv_usec)
	}

	static func append(_ line: String) {
		let fileDescriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard fileDescriptor >= 0 else { return }
		let bytes = Array((line + "\n").utf8)
		_ = bytes.withUnsafeBytes { write(fileDescriptor, $0.baseAddress, $0.count) }
		close(fileDescriptor)
	}

	static func expansion(_ role: String, of declaration: some SyntaxProtocol, in context: some MacroExpansionContext) {
		let name: String = if let variable = declaration.as(VariableDeclSyntax.self) {
			variable.bindings.map(\.pattern.trimmedDescription).joined(separator: ",")
		} else if let group = declaration.asProtocol(NamedDeclSyntax.self) {
			group.name.text
		} else {
			declaration.kind.syntaxNodeType == FunctionDeclSyntax.self ? "func" : "\(declaration.kind)"
		}
		var parent = ""
		for node in context.lexicalContext {
			if let named = node.asProtocol(NamedDeclSyntax.self) {
				parent = named.name.text; break
			}
		}
		append("expand\t\(role)\t\(parent.isEmpty ? name : parent + "." + name)\t\(job)\t\(getppid())\t\(cpuMicroseconds())")
	}
}

// MARK: - A message connection that records each request's size

/// Same framing as swift-syntax's StandardIOMessageConnection (8-byte little-endian length, then JSON),
/// plus one log line per message with its size and the size of its `staticBuildConfiguration` string.
struct MeasuringConnection: MessageConnection {
	let input: CInt
	let output: CInt
	/// Saves the first two expansion requests of each plugin process here, if the directory exists.
	static let sampleDirectory: String? = FileManager.default.fileExists(atPath: "/tmp/noop-macro-samples") ? "/tmp/noop-macro-samples" : nil
	nonisolated(unsafe) static var samplesWritten = 0
	/// When /tmp/noop-macro-drop-configuration exists, hands swift-syntax each request without its
	/// `staticBuildConfiguration` string, so the handler skips decoding it (measurement only).
	static let dropConfiguration = FileManager.default.fileExists(atPath: "/tmp/noop-macro-drop-configuration")

	init() {
		input = dup(STDIN_FILENO)
		close(STDIN_FILENO)
		output = dup(STDOUT_FILENO)
		dup2(STDERR_FILENO, STDOUT_FILENO)
	}

	func readExactly(_ count: Int) -> [UInt8]? {
		var buffer = [UInt8](repeating: 0, count: count)
		var offset = 0
		while offset < count {
			let readCount = buffer.withUnsafeMutableBytes { read(input, $0.baseAddress! + offset, count - offset) }
			guard readCount > 0 else { return nil }
			offset += readCount
		}
		return buffer
	}

	func sendMessage(_ message: some Encodable) throws {
		let payload = try JSON.encode(message)
		var header = UInt64(payload.count).littleEndian
		var bytes = withUnsafeBytes(of: &header) { Array($0) }
		bytes += payload
		var offset = 0
		while offset < bytes.count {
			let written = bytes.withUnsafeBytes { write(output, $0.baseAddress! + offset, bytes.count - offset) }
			guard written > 0 else { throw CocoaError(.fileWriteUnknown) }
			offset += written
		}
	}

	func waitForNextMessage<RX: Decodable>(_ type: RX.Type) throws -> RX? {
		guard let header = readExactly(8) else { return nil }
		let count = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian)
		// An empty message is the host's termination signal.
		guard count > 0, let payload = readExactly(count) else { return nil }
		let message: RX
		do {
			message = try payload.withUnsafeBufferPointer { try JSON.decode(type, from: $0) }
		} catch {
			Log.append("decode-error\t\(count)\t\(Log.job)\t\(error)")
			throw error
		}
		if Self.dropConfiguration, let message = message as? HostToPluginMessage,
		   case let .expandAttachedMacro(macro, role, discriminator, attribute, declaration, parent, extendedType, conformances, lexicalContext, _) = message
		{
			Log.append("message\texpandAttachedMacro.\(role.rawValue)\t\(count)\tdropped\t\(Log.job)")
			return HostToPluginMessage.expandAttachedMacro(
				macro: macro, macroRole: role, discriminator: discriminator, attributeSyntax: attribute,
				declSyntax: declaration, parentDeclSyntax: parent, extendedTypeSyntax: extendedType,
				conformanceListSyntax: conformances, lexicalContext: lexicalContext, staticBuildConfiguration: nil,
			) as? RX
		}
		if let message = message as? HostToPluginMessage {
			switch message {
			case let .expandAttachedMacro(_, role, _, _, _, _, _, _, _, configuration):
				Log.append("message\texpandAttachedMacro.\(role.rawValue)\t\(count)\t\(configuration?.utf8.count ?? 0)\t\(Log.job)")
				if let directory = Self.sampleDirectory, Self.samplesWritten < 2 {
					Self.samplesWritten += 1
					_ = FileManager.default.createFile(
						atPath: "\(directory)/\(getpid())-\(Self.samplesWritten).json",
						contents: Data(payload),
					)
				}
			case let .expandFreestandingMacro(_, _, _, _, _, configuration):
				Log.append("message\texpandFreestandingMacro\t\(count)\t\(configuration?.utf8.count ?? 0)\t\(Log.job)")
			case .getCapability:
				Log.append("message\tgetCapability\t\(count)\t0\t\(Log.job)")
			case .loadPluginLibrary:
				Log.append("message\tloadPluginLibrary\t\(count)\t0\t\(Log.job)")
			}
		}
		return message
	}
}

struct Provider: PluginProvider {
	func resolveMacro(moduleName _: String, typeName: String) throws -> Macro.Type {
		switch typeName {
		case "NoopPeerMacro": NoopPeerMacro.self
		case "NoopMemberMacro": NoopMemberMacro.self
		default: throw CocoaError(.featureUnsupported)
		}
	}

	func loadPluginLibrary(libraryPath _: String, moduleName _: String) throws {
		throw CocoaError(.featureUnsupported)
	}

	var features: [PluginFeature] {
		[]
	}
}

/// Reports protocol version 7 instead of swift-syntax's 8 when /tmp/noop-macro-protocol7 exists (measurement only).
struct VersionOverridingHandler: PluginMessageHandler {
	let base = PluginProviderMessageHandler(provider: Provider())
	static let override = FileManager.default.fileExists(atPath: "/tmp/noop-macro-protocol7")

	func handleMessage(_ message: HostToPluginMessage) -> PluginToHostMessage {
		let result = base.handleMessage(message)
		if Self.override, case let .getCapabilityResult(capability) = result {
			return .getCapabilityResult(capability: .init(protocolVersion: 7, features: capability.features))
		}
		return result
	}

	func shutDown() throws {
		try base.shutDown()
	}
}

@main
struct NoopPlugin {
	static func main() throws {
		defer {
			var usage = rusage()
			getrusage(0 /* RUSAGE_SELF */, &usage)
			let microseconds = (Int(usage.ru_utime.tv_sec) + Int(usage.ru_stime.tv_sec)) * 1_000_000
				+ Int(usage.ru_utime.tv_usec) + Int(usage.ru_stime.tv_usec)
			Log.append("exit\t\(Log.job)\t\(microseconds)\t\(VersionOverridingHandler.override ? 7 : 8)")
		}
		Log.append("launch\t\(Log.job)\t\(getppid())\t\((try? String(contentsOfFile: "/proc/\(getppid())/cmdline", encoding: .utf8))?.count ?? -1)")
		try CompilerPluginMessageListener(connection: MeasuringConnection(), messageHandler: VersionOverridingHandler()).main()
	}
}
