// SPIKE ONLY (in-tree parallel construction design, 2026-11-20). Never lands: env-gated per-place trace of one
// construction pass, read offline by a simulator. Off unless SAFEDI_SPIKE_TRACE names a file.
import Foundation

enum SpikeTrace {
	static let path: String? = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_TRACE"]

	static func now() -> UInt64 {
		DispatchTime.now().uptimeNanoseconds
	}

	/// One event of a pass, in walk order. kind: B build, F fill, H hit (front memo), S settled reuse, R root.
	struct Event {
		var id: Int
		var parent: Int
		var kind: Character
		var start: UInt64
		var end: UInt64 = 0
		var size: Int = 0
		var keyed: Bool = false
		var source: Int = -1
	}

	final class Pass {
		var events = [Event]()
		var placeByGenerator = [ObjectIdentifier: Int]()
		let tree: String
		let passStart = SpikeTrace.now()
		init(tree: String) {
			self.tree = tree
		}

		func write() {
			guard let path = SpikeTrace.path else { return }
			let passEnd = SpikeTrace.now()
			var text = "PASS \(tree) \(passEnd - passStart) \(events.count)\n"
			for e in events {
				text += "\(e.id) \(e.parent) \(e.kind) \(e.start - passStart) \(e.end - passStart) \(e.size) \(e.keyed ? 1 : 0) \(e.source)\n"
			}
			let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
			guard fd >= 0 else { return }
			text.withCString { pointer in
				_ = Foundation.write(fd, pointer, strlen(pointer))
			}
			close(fd)
		}
	}

	static func writeTree(_ label: String, nanoseconds: UInt64) {
		guard let path else { return }
		let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard fd >= 0 else { return }
		let text = "TREE \(label) \(nanoseconds)\n"
		text.withCString { pointer in
			_ = Foundation.write(fd, pointer, strlen(pointer))
		}
		close(fd)
	}
}
