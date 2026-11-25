func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

@MainActor func describe(_ name: String, _ root: Root) {
	let leftBuilt = root.left.holderBuilder.instantiate()
	let rightBuilt = root.right.holderBuilder.instantiate()
	report("\(name): holders (left, left built, right, right built)", [root.left.holder.name, leftBuilt.name, root.right.holder.name, rightBuilt.name])
	report("\(name): leaves (left, left built, right, right built)", [root.left.holder.leaf.name, leftBuilt.leaf.name, root.right.holder.leaf.name, rightBuilt.leaf.name])
	report("\(name): left's holders and leaves read left's token", [root.left.holder, leftBuilt].allSatisfy { $0.token === root.left.token && $0.leaf.token === root.left.token })
	report("\(name): right's holders and leaves read right's token", [root.right.holder, rightBuilt].allSatisfy { $0.token === root.right.token && $0.leaf.token === root.right.token })
	report("\(name): the tokens differ", root.left.token !== root.right.token)
}

describe("no overrides", Root.mock())
describe("a name at each place", Root.mock(safeDIOverrides: .init(
	left: .init(holder: .init(leaf: .init(name: "left leaf"), name: "left"), holderBuilder: .init(leaf: .init(name: "left built leaf"), name: "left built")),
	right: .init(holder: .init(leaf: .init(name: "right leaf"), name: "right"), holderBuilder: .init(leaf: .init(name: "right built leaf"), name: "right built")),
)))
describe("one place only", Root.mock(safeDIOverrides: .init(right: .init(holderBuilder: .init(leaf: .init(name: "right built leaf"))))))

let leftToken = Token()
let withBuilders = Root.mock(safeDIOverrides: .init(
	left: .init(token: { leftToken }, holderBuilder: .init(leaf: .init { token, _ in Leaf(token: token, name: "left built leaf from a builder") })),
	right: .init(holder: .init { token, leaf, _ in Holder(token: token, leaf: leaf, name: "right from a builder") }),
))
describe("builders", withBuilders)
report("builders: left's token is the overriding one", withBuilders.left.token === leftToken)
describe("production", Root())
