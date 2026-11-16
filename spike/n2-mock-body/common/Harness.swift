// The spike's counting harness: every fixture type holds a `Tracker`, which numbers the instances of its type, logs
// what each instance received, and keeps a live count per type that `Registry.alive()` reports.
import Synchronization
#if canImport(Glibc)
	import Glibc
#endif

/// Set to false by timing runs, so a value's cost is the generated code's, not the trace's.
public let tracingEnabled = Atomic<Bool>(true)

public final class Tracker: Sendable {
	public let typeName: String
	public let number: Int

	public init(_ typeName: String) {
		self.typeName = typeName
		number = Registry.state.withLock { state in
			state.created[typeName, default: 0] += 1
			state.live[typeName, default: 0] += 1
			return state.created[typeName, default: 0]
		}
	}

	deinit {
		let typeName = typeName
		Registry.state.withLock { state in
			state.live[typeName, default: 0] -= 1
		}
	}

	public var name: String {
		"\(typeName)#\(number)"
	}
}

public protocol Traced {
	var tracker: Tracker { get }
}

public enum Registry {
	public struct State: Sendable {
		var created = [String: Int]()
		var live = [String: Int]()
		var trace = [String]()
	}

	public static let state = Mutex(State())

	/// Records that `value` was created holding `received`, each described by the instance it names.
	public static func created(_ value: some Traced, _ received: KeyValuePairs<String, Any?>) {
		guard tracingEnabled.load(ordering: .relaxed) else { return }
		let line = value.tracker.name + "(" + received.map { "\($0.key): \(describe($0.value))" }.joined(separator: ", ") + ")"
		state.withLock { $0.trace.append(line) }
	}

	public static func note(_ line: String) {
		guard tracingEnabled.load(ordering: .relaxed) else { return }
		state.withLock { $0.trace.append(line) }
	}

	public static func describe(_ value: Any?) -> String {
		guard let value else { return "nil" }
		if let traced = value as? Traced {
			return traced.tracker.name
		}
		let mirror = Mirror(reflecting: value)
		if mirror.displayStyle == .optional {
			guard let child = mirror.children.first else { return "nil" }
			return describe(child.value)
		}
		if let int = value as? Int {
			return String(int)
		}
		return "builder"
	}

	/// Prints the trace and empties it.
	public static func printTrace() {
		let trace = state.withLock { state in
			defer { state.trace = [] }
			return state.trace
		}
		for line in trace {
			print("  " + line)
		}
	}

	/// Prints every type with a live instance, in name order.
	public static func printAlive(_ heading: String) {
		let live = state.withLock { $0.live }
		let alive = live.filter { $0.value != 0 }.sorted { $0.key < $1.key }
		print("alive \(heading): " + (alive.isEmpty ? "none" : alive.map { "\($0.key) \($0.value)" }.joined(separator: ", ")))
	}
}

/// Reads `BENCH` from the environment without Foundation.
public enum ProcessInfoLite {
	public static var benchIterations: Int? {
		guard let value = getenv("BENCH") else { return nil }
		return Int(String(cString: value))
	}
}

public enum FileHandleLite {
	public static func error(_ line: String) {
		let text = line + "\n"
		_ = text.withCString { write(2, $0, strlen($0)) }
	}
}
