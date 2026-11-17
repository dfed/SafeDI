// R0 PROTOTYPE PROBE — measurement only, never for a pull request.
//
// Counts the generators a memo of subtree construction would build, per tree and across roots, by simulating the memo
// over a build without it: a place is a hit when an equal (key, read log) entry was stored before it started, and a
// place inside a hit is never built. Enabled by the environment variable SAFEDI_R0_PROBE (a file to append the report to).

import Foundation

struct R0Hash: Hashable, Sendable {
	var first: Int
	var second: Int

	static func of(_ build: (inout Hasher) -> Void) -> R0Hash {
		var first = Hasher()
		first.combine(0x5AFE)
		build(&first)
		var second = Hasher()
		second.combine(0xD1D1)
		build(&second)
		return R0Hash(first: first.finalize(), second: second.finalize())
	}
}

/// The deduplicated value log of a subtree's reads of its context.
struct R0Log: Sendable {
	var entries = Set<R0Hash>()

	mutating func record(_ build: (inout Hasher) -> Void) {
		guard R0Probe.isEnabled else { return }
		entries.insert(R0Hash.of(build))
	}

	mutating func formUnion(_ other: R0Log) {
		guard R0Probe.isEnabled else { return }
		entries.formUnion(other.entries)
	}

	var canonicalHash: R0Hash {
		let sorted = entries.sorted { ($0.first, $0.second) < ($1.first, $1.second) }
		return R0Hash.of { hasher in
			hasher.combine(sorted.count)
			for entry in sorted {
				hasher.combine(entry)
			}
		}
	}
}

/// One place's record in a tree.
struct R0Place: Sendable {
	var parent: Int?
	var start: Int
	var finish = -1
	/// `nil` when the place is excluded from the memo.
	var classKey: R0Hash?
	var pass: Int
	var subtreeScopeCount = 1
}

struct R0Tree: Sendable {
	var places = [R0Place]()
	var event = 0
	var flags: String

	mutating func nextEvent() -> Int {
		event += 1
		return event
	}
}

final class R0Probe: @unchecked Sendable {
	static let path = ProcessInfo.processInfo.environment["SAFEDI_R0_PROBE"]
	static let isEnabled = path != nil
	static let shared = R0Probe()

	private let lock = NSLock()
	private var classByGenerator = [ObjectIdentifier: R0Hash]()
	private var uniqueCounter = 0
	private var crossRootStored = Set<R0Hash>()
	private var totals = [String: [String: Int]]()
	private var registeredExit = false
	private var emissions = 0
	private var sharedEmissionKeys = Set<R0Hash>()
	private var mockEmissions = 0
	private var sharedMockEmissionKeys = Set<R0Hash>()
	private var codeHashByClassAndKey = [R0Hash: Int]()
	private var codeMismatches = 0
	private var codeChecks = 0

	/// The oracle: every emission of one (class, key) must produce the same code.
	func checkEmission(generator: ScopeGenerator, key: some Hashable, code: String) {
		lock.lock()
		defer { lock.unlock() }
		codeChecks += 1
		let classKey = classByGenerator[ObjectIdentifier(generator)] ?? R0Hash(first: ObjectIdentifier(generator).hashValue, second: 7)
		let combined = R0Hash.of { hasher in
			hasher.combine(classKey)
			hasher.combine(key)
		}
		let codeHash = code.hashValue
		if let existing = codeHashByClassAndKey[combined] {
			if existing != codeHash { codeMismatches += 1 }
		} else {
			codeHashByClassAndKey[combined] = codeHash
		}
	}

	func recordEmission(generator: ScopeGenerator, key: some Hashable) {
		lock.lock()
		defer { lock.unlock() }
		emissions += 1
		let classKey = classByGenerator[ObjectIdentifier(generator)] ?? R0Hash(first: ObjectIdentifier(generator).hashValue, second: 7)
		sharedEmissionKeys.insert(R0Hash.of { hasher in
			hasher.combine(classKey)
			hasher.combine(key)
		})
	}

	func recordMockEmission(generator: ScopeGenerator, unavailableProperties: Set<Property>, propertiesGeneratedLater: Set<Property>, builderFunctionNames: some Hashable) {
		lock.lock()
		defer { lock.unlock() }
		mockEmissions += 1
		let classKey = classByGenerator[ObjectIdentifier(generator)] ?? R0Hash(first: ObjectIdentifier(generator).hashValue, second: 7)
		sharedMockEmissionKeys.insert(R0Hash.of { hasher in
			hasher.combine(classKey)
			hasher.combine(unavailableProperties.sorted())
			hasher.combine(propertiesGeneratedLater.sorted())
			hasher.combine(builderFunctionNames)
		})
	}

	func uniqueHash() -> R0Hash {
		lock.lock()
		defer { lock.unlock() }
		uniqueCounter += 1
		return R0Hash(first: -uniqueCounter, second: -uniqueCounter)
	}

	func register(generator: ScopeGenerator, classKey: R0Hash) {
		lock.lock()
		classByGenerator[ObjectIdentifier(generator)] = classKey
		lock.unlock()
	}

	func classKey(of generator: ScopeGenerator?) -> R0Hash? {
		guard let generator else { return nil }
		lock.lock()
		defer { lock.unlock() }
		return classByGenerator[ObjectIdentifier(generator)]
	}

	/// Simulates the memo over `places`, with `stored` holding the entries stored before the tree; returns the count built.
	private static func simulate(_ places: [R0Place], stored: inout Set<R0Hash>) -> (built: Int, hits: Int) {
		var events = [(time: Int, index: Int, isStart: Bool)]()
		events.reserveCapacity(places.count * 2)
		for (index, place) in places.enumerated() {
			events.append((place.start, index, true))
			events.append((place.finish, index, false))
		}
		events.sort { $0.time < $1.time }
		var skipped = [Bool](repeating: false, count: places.count)
		var hit = [Bool](repeating: false, count: places.count)
		var built = 0
		var hits = 0
		for event in events {
			let place = places[event.index]
			if event.isStart {
				if let parent = place.parent, skipped[parent] || hit[parent] {
					skipped[event.index] = true
				} else if let key = place.classKey, stored.contains(key) {
					hit[event.index] = true
					hits += 1
				} else {
					built += 1
				}
			} else if !skipped[event.index], !hit[event.index], let key = place.classKey {
				stored.insert(key)
			}
		}
		return (built, hits)
	}

	func submit(_ tree: R0Tree) {
		var perTreeStored = Set<R0Hash>()
		let perTree = Self.simulate(tree.places, stored: &perTreeStored)
		let excluded = tree.places.count(where: { $0.classKey == nil })
		let passes = (tree.places.map(\.pass).max() ?? 0) + 1
		let distinctClasses = Set(tree.places.compactMap(\.classKey)).count
		lock.lock()
		let crossRoot = Self.simulate(tree.places, stored: &crossRootStored)
		for group in ["all", tree.flags] {
			var entry = totals[group, default: [:]]
			entry["trees", default: 0] += 1
			entry["places", default: 0] += tree.places.count
			entry["builtPerTree", default: 0] += perTree.built
			entry["builtCrossRoot", default: 0] += crossRoot.built
			entry["excluded", default: 0] += excluded
			entry["passes", default: 0] += passes
			entry["distinctClassesPerTree", default: 0] += distinctClasses
			totals[group] = entry
		}
		if !registeredExit {
			registeredExit = true
			atexit { R0Probe.shared.report() }
		}
		lock.unlock()
	}

	func report() {
		guard let path = Self.path else { return }
		lock.lock()
		defer { lock.unlock() }
		var text = ""
		for group in totals.keys.sorted() {
			guard let entry = totals[group] else { continue }
			let places = Double(entry["places", default: 0])
			let perTree = Double(entry["builtPerTree", default: 0])
			let crossRoot = Double(entry["builtCrossRoot", default: 0])
			text += "group=\(group) trees=\(entry["trees", default: 0]) passes=\(entry["passes", default: 0]) places=\(Int(places)) excluded=\(entry["excluded", default: 0]) distinctClassesPerTree=\(entry["distinctClassesPerTree", default: 0]) builtPerTree=\(Int(perTree)) builtCrossRoot=\(Int(crossRoot)) ratioPerTree=\(String(format: "%.4f", perTree / max(places, 1))) ratioCrossRoot=\(String(format: "%.4f", crossRoot / max(places, 1)))\n"
		}
		text += "emissions=\(emissions) emissionsWithSharedGenerators=\(sharedEmissionKeys.count) mockEmissions=\(mockEmissions) mockEmissionsIfCachedOnSharedGenerators=\(sharedMockEmissionKeys.count) codeChecks=\(codeChecks) codeMismatches=\(codeMismatches)\n"
		if let handle = FileHandle(forWritingAtPath: path) {
			handle.seekToEndOfFile()
			handle.write(Data(text.utf8))
			handle.closeFile()
		} else {
			FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
		}
	}
}
