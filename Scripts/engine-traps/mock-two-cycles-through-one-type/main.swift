func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

@MainActor func describe(_ name: String, _ root: Root) {
	for (entry, token, aBuilder) in [("left", root.left.token, root.left.aBuilder), ("right", root.right.token, root.right.aBuilder), ("top", root.token, root.aBuilder)] {
		let a1 = aBuilder.instantiate()
		let b1 = a1.bBuilder.instantiate()
		let c1 = b1.cBuilder.instantiate()
		let b2 = c1.bBuilder.instantiate() // B again, through C, still beneath a1
		let c2 = b2.cBuilder.instantiate()
		let b3 = c2.bBuilder.instantiate()
		let a2 = b3.aBuilder.instantiate() // a new A, after two trips through C
		let b4 = a2.bBuilder.instantiate()
		let c3 = b4.cBuilder.instantiate()
		let b5 = c3.bBuilder.instantiate()
		report("\(name): \(entry): stamps (A1, A2)", [a1.stamp.name, a2.stamp.name])
		report("\(name): \(entry): leaves (A1, B1, C1, B2, C2, B3, A2, B4, C3, B5)", [a1.leaf.name, b1.leaf.name, c1.leaf.name, b2.leaf.name, c2.leaf.name, b3.leaf.name, a2.leaf.name, b4.leaf.name, c3.leaf.name, b5.leaf.name])
		report("\(name): \(entry): everything beneath A1 reads A1's stamp", [a1.leaf, b1.leaf, c1.leaf, b2.leaf, c2.leaf, b3.leaf].allSatisfy { $0.stamp === a1.stamp })
		report("\(name): \(entry): everything beneath A2 reads A2's stamp, a new one", [a2.leaf, b4.leaf, c3.leaf, b5.leaf].allSatisfy { $0.stamp === a2.stamp } && a2.stamp !== a1.stamp)
		report("\(name): \(entry): every leaf reads the entry's token", [a1.leaf, b1.leaf, c1.leaf, b2.leaf, c2.leaf, b3.leaf, a2.leaf, b4.leaf, c3.leaf, b5.leaf].allSatisfy { $0.token === token })
	}
}

describe("no overrides", Root.mock())
describe("names per entry", Root.mock(safeDIOverrides: .init(
	left: .init(aBuilder: .init(
		stamp: .init(name: "left stamp"),
		leaf: .init(name: "left A leaf"),
		bBuilder: .init(leaf: .init(name: "left B leaf"), cBuilder: .init(leaf: .init(name: "left C leaf"))),
	)),
	right: .init(aBuilder: .init(bBuilder: .init(cBuilder: .init(leaf: .init(name: "right C leaf"))))),
	aBuilder: .init(stamp: .init(name: "top stamp"), bBuilder: .init(leaf: .init(name: "top B leaf"))),
)))
describe("builders", Root.mock(safeDIOverrides: .init(
	left: .init(aBuilder: .init(bBuilder: .init(cBuilder: .init { leaf, bBuilder in C(leaf: Leaf(token: leaf.token, stamp: leaf.stamp, name: "left C from a builder"), bBuilder: bBuilder) }))),
	right: .init(aBuilder: .init(bBuilder: .init { leaf, aBuilder, cBuilder in B(leaf: Leaf(token: leaf.token, stamp: leaf.stamp, name: "right B from a builder"), aBuilder: aBuilder, cBuilder: cBuilder) })),
)))
describe("production", Root())
