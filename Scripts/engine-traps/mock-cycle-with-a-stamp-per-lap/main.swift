func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

@MainActor func describe(_ name: String, _ root: Root) {
	var allStamps: [Stamp] = []
	for (entry, token, aBuilder) in [("left", root.left.token, root.left.aBuilder), ("right", root.right.token, root.right.aBuilder), ("top", root.token, root.aBuilder)] {
		let a1 = aBuilder.instantiate()
		let b1 = a1.bBuilder.instantiate()
		let b1Again = a1.bBuilder.instantiate()
		let a2 = b1.aBuilder.instantiate()
		let b2 = a2.bBuilder.instantiate()
		let a3 = b2.aBuilder.instantiate()
		let other = aBuilder.instantiate()
		allStamps += [a1.stamp, a2.stamp, a3.stamp, other.stamp]
		report("\(name): \(entry): stamps (A1, A2, A3, another A1)", [a1.stamp.name, a2.stamp.name, a3.stamp.name, other.stamp.name])
		report("\(name): \(entry): leaves (A1, B1, A2, B2, A3)", [a1.leaf.name, b1.leaf.name, a2.leaf.name, b2.leaf.name, a3.leaf.name])
		report("\(name): \(entry): each A's leaf reads that A's stamp", a1.leaf.stamp === a1.stamp && a2.leaf.stamp === a2.stamp && a3.leaf.stamp === a3.stamp && other.leaf.stamp === other.stamp)
		report("\(name): \(entry): each B's leaf reads the stamp of the A that built it", b1.leaf.stamp === a1.stamp && b1Again.leaf.stamp === a1.stamp && b2.leaf.stamp === a2.stamp)
		report("\(name): \(entry): every leaf reads the entry's token", [a1.leaf, b1.leaf, b1Again.leaf, a2.leaf, b2.leaf, a3.leaf, other.leaf].allSatisfy { $0.token === token })
	}
	report("\(name): distinct stamps among twelve constructions of A", Set(allStamps.map(ObjectIdentifier.init)).count)
}

describe("no overrides", Root.mock())
describe("names per entry", Root.mock(safeDIOverrides: .init(
	left: .init(aBuilder: .init(stamp: .init(name: "left stamp"), leaf: .init(name: "left A leaf"), bBuilder: .init(leaf: .init(name: "left B leaf")))),
	right: .init(aBuilder: .init(bBuilder: .init(leaf: .init(name: "right B leaf")))),
	aBuilder: .init(stamp: .init(name: "top stamp"), leaf: .init(name: "top A leaf")),
)))

var stampsMade = 0
let counted = Root.mock(safeDIOverrides: .init(
	right: .init(aBuilder: .init(stamp: .init { _ in
		stampsMade += 1
		return Stamp(name: "right stamp \(stampsMade)")
	})),
))
describe("a counting builder at the right entry", counted)
report("stamps the right entry's builder made", stampsMade)
describe("production", Root())
