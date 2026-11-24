func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

var created = 0
@MainActor func makeToken() -> Token {
	created += 1
	return Token()
}

let feature = Feature(__safeDI_token: makeToken())
report("tokens created once the tree is built", created)
let left = feature.leftBuilder.instantiate()
var tokens: [Token] = []
for (side, token, aBuilder, nodeBuilder) in [("left", left.token as Token?, left.aBuilder, left.nodeBuilder), ("right", feature.right.token, feature.right.aBuilder, feature.right.nodeBuilder), ("top", nil, feature.aBuilder, feature.nodeBuilder)] {
	let a1 = aBuilder.instantiate()
	report("\(side): tokens created after the first lap", created)
	let b1 = a1.bBuilder.instantiate()
	let a2 = b1.aBuilder.instantiate()
	let b2 = a2.bBuilder.instantiate()
	let expected = token ?? a1.leaf.token
	tokens.append(expected)
	report("\(side): every lap's leaf reads \(side)'s token", [a1.leaf, b1.leaf, a2.leaf, b2.leaf].allSatisfy { $0.token === expected })
	let ids = [ID(), ID(), ID()]
	let node1 = nodeBuilder.instantiate(ids[0])
	let node2 = node1.nodeBuilder.instantiate(ids[1])
	let node3 = node2.nodeBuilder.instantiate(ids[2])
	report("\(side): each lap's reader reads the id its node was forwarded", node1.reader.id === ids[0] && node2.reader.id === ids[1] && node3.reader.id === ids[2])
	report("\(side): each lap's reader reads \(side)'s token", [node1, node2, node3].allSatisfy { $0.reader.token === expected })
}
report("the three tokens differ", tokens[0] !== tokens[1] && tokens[1] !== tokens[2] && tokens[0] !== tokens[2])
report("tokens created at the end", created)
