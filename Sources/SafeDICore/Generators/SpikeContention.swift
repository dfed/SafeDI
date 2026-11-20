// SPIKE ONLY (PR 10 kill gate A, 2026-11-20). Never lands. With SAFEDI_SPIKE_CONTENTION=ROUNDS, each production root is
// first constructed ROUNDS times alone and then K = 2, 3, 4 at once on K threads, each with its own memo and no code
// started, and the per-construction times are printed to standard error: whether K independent serial constructions
// in one process slow each other down (allocator, reference counting, memory bandwidth).
import Foundation

enum SpikeContention {
	static let rounds: Int? = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_CONTENTION"].flatMap(Int.init)

	/// With SAFEDI_SPIKE_CONTENTION_OWN_TABLE=1, each thread constructs from a table and records frozen for it alone.
	static let stubsReplay = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_REPLAY"] == "stub"
	static let memoOff = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_REPLAY"] == "off"

	static let ownTable = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_CONTENTION_OWN_TABLE"] == "1"

	static func measure(label: String, _ construct: @escaping @Sendable () throws -> Void) throws {
		try measure(label: label, constructions: [construct, construct, construct, construct])
	}

	static func measure(label: String, constructions: [@Sendable () throws -> Void]) throws {
		guard let rounds else { return }
		// Warm up once.
		for construct in constructions {
			try ConstructionMemo.$isEnabled.withValue(!memoOff) {
				try construct()
			}
		}
		for round in 0..<rounds {
			for threads in (ProcessInfo.processInfo.environment["SAFEDI_SPIKE_CONTENTION_KS"].map { $0.split(separator: ",").compactMap { Int($0) } } ?? [1, 2, 3, 4]) {
				let times = Times(count: threads)
				let start = DispatchTime.now().uptimeNanoseconds
				DispatchQueue.concurrentPerform(iterations: threads) { index in
					let threadStart = DispatchTime.now().uptimeNanoseconds
					ConstructionMemo.$isEnabled.withValue(!memoOff) {
						try? constructions[index]()
					}
					times.set(index, DispatchTime.now().uptimeNanoseconds - threadStart)
				}
				let wall = DispatchTime.now().uptimeNanoseconds - start
				let each = times.values.map { String(format: "%.3f", Double($0) / 1e9) }.joined(separator: ",")
				FileHandle.standardError.write(Data("CONTENTION \(label) round \(round) K \(threads) wall \(String(format: "%.3f", Double(wall) / 1e9)) each \(each)\n".utf8))
			}
		}
	}

	/// One slot per thread; each thread writes only its own.
	final class Times: Sendable {
		init(count: Int) {
			storage = UnsafeMutableBufferPointer<UInt64>.allocate(capacity: count)
			storage.initialize(repeating: 0)
		}

		deinit {
			storage.deallocate()
		}

		func set(_ index: Int, _ value: UInt64) {
			storage[index] = value
		}

		var values: [UInt64] {
			Array(storage)
		}

		nonisolated(unsafe) let storage: UnsafeMutableBufferPointer<UInt64>
	}
}
