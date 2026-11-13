// DecodeBench FILE... : times the two decodes swift-syntax 604's plugin message handler performs for
// each expansion request: the request itself, then the `staticBuildConfiguration` JSON string inside it.
import Foundation
@_spi(PluginMessage) import SwiftCompilerPluginMessageHandling
import SwiftIfConfig

func measure(_ iterations: Int, _ body: () throws -> Void) rethrows -> Double {
	let start = DispatchTime.now().uptimeNanoseconds
	for _ in 0..<iterations {
		try body()
	}
	return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1_000
}

let iterations = Int(ProcessInfo.processInfo.environment["ITERATIONS"] ?? "20000") ?? 20_000
for path in CommandLine.arguments.dropFirst() {
	let payload = Array(try Data(contentsOf: URL(fileURLWithPath: path)))
	let message = try payload.withUnsafeBufferPointer { try JSON.decode(HostToPluginMessage.self, from: $0) }
	guard case let .expandAttachedMacro(_, _, _, _, _, _, _, _, _, configurationString?) = message else {
		print("\(path): no staticBuildConfiguration"); continue
	}
	let configurationBytes = Array(configurationString.utf8)
	// The request with the configuration string removed, for comparison.
	var object = try JSONSerialization.jsonObject(with: Data(payload)) as! [String: [String: Any]]
	object["expandAttachedMacro"]?.removeValue(forKey: "staticBuildConfiguration")
	let strippedPayload = Array(try JSONSerialization.data(withJSONObject: object))

	let requestMicroseconds = try measure(iterations) {
		_ = try payload.withUnsafeBufferPointer { try JSON.decode(HostToPluginMessage.self, from: $0) }
	}
	let strippedMicroseconds = try measure(iterations) {
		_ = try strippedPayload.withUnsafeBufferPointer { try JSON.decode(HostToPluginMessage.self, from: $0) }
	}
	let configurationMicroseconds = try measure(iterations) {
		_ = try configurationBytes.withUnsafeBufferPointer { try JSON.decode(StaticBuildConfiguration.self, from: $0) }
	}
	let configuration = try configurationBytes.withUnsafeBufferPointer { try JSON.decode(StaticBuildConfiguration.self, from: $0) }
	print("""
	\((path as NSString).lastPathComponent): request \(payload.count) bytes, of which staticBuildConfiguration \(configurationBytes.count) bytes; request without it \(strippedPayload.count) bytes
	  decode request:                         \(String(format: "%.2f", requestMicroseconds)) µs
	  decode request without configuration:   \(String(format: "%.2f", strippedMicroseconds)) µs
	  decode StaticBuildConfiguration string: \(String(format: "%.2f", configurationMicroseconds)) µs
	  configuration: \(configuration.attributes.count) attributes, \(configuration.features.count) features, \(configuration.customConditions.count) custom conditions
	""")
}
