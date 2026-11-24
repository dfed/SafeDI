func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

let root = Root.mock(safeDIOverrides: .init(
	left: .init(
		aBuilder: .init(bBuilder: .init(leaf: .init(name: "left B")), leaf: .init(name: "left A")),
		nodeBuilder: .init(reader: .init(name: "left reader")),
	),
	right: .init(
		aBuilder: .init(leaf: .init(name: "right A")),
	),
))
for (side, token, aBuilder, nodeBuilder) in [("left", root.left.token, root.left.aBuilder, root.left.nodeBuilder), ("right", root.right.token, root.right.aBuilder, root.right.nodeBuilder)] {
	let a1 = aBuilder.instantiate()
	let b1 = a1.bBuilder.instantiate()
	let a2 = b1.aBuilder.instantiate()
	let b2 = a2.bBuilder.instantiate()
	report("\(side): leaves by lap (A, B, A, B)", [a1.leaf.name, b1.leaf.name, a2.leaf.name, b2.leaf.name])
	report("\(side): every lap's leaf reads \(side)'s token", [a1.leaf, b1.leaf, a2.leaf, b2.leaf].allSatisfy { $0.token === token })
	let ids = [ID(), ID(), ID()]
	let node1 = nodeBuilder.instantiate(ids[0])
	let node2 = node1.nodeBuilder.instantiate(ids[1])
	let node3 = node2.nodeBuilder.instantiate(ids[2])
	report("\(side): each lap's reader reads the id its node was forwarded", node1.reader.id === ids[0] && node2.reader.id === ids[1] && node3.reader.id === ids[2])
	report("\(side): each lap's reader reads \(side)'s token", [node1, node2, node3].allSatisfy { $0.reader.token === token })
	report("\(side): readers by lap", [node1.reader.name, node2.reader.name, node3.reader.name])
}
