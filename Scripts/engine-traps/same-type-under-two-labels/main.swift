func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

let root = Root.mock(safeDIOverrides: .init(
	first: .init(mid: .init(leaf: .init(name: "first's leaf"))),
	thirdBuilder: .init(leaf: .init(name: "third's leaf")),
))
let third = root.thirdBuilder.instantiate()
report("first's leaf", root.first.mid.leaf.name)
report("second's leaf", root.second.mid.leaf.name)
report("third's leaf", third.leaf.name)
report("three tokens", root.first.token !== root.second.token && root.first.token !== root.token && root.second.token !== root.token)
report("first's mid reads first's token", root.first.mid.token === root.first.token)
report("first's leaf reads first's token", root.first.mid.leaf.token === root.first.token)
report("second's mid reads second's token", root.second.mid.token === root.second.token)
report("second's leaf reads second's token", root.second.mid.leaf.token === root.second.token)
report("third's mid reads the root's token", third.token === root.token)
report("third's leaf reads the root's token", third.leaf.token === root.token)

let other = Root.mock(safeDIOverrides: .init(
	second: .init(mid: .init({ leaf, token in Mid(leaf: Leaf(token: token, name: "second's mid override"), token: token) })),
))
report("first's leaf, second overridden", other.first.mid.leaf.name)
report("second's leaf, second overridden", other.second.mid.leaf.name)
report("third's leaf, second overridden", other.thirdBuilder.instantiate().leaf.name)

let production = Root()
let productionThird = production.thirdBuilder.instantiate()
report("production: first's mid and leaf read first's token", production.first.mid.token === production.first.token && production.first.mid.leaf.token === production.first.token)
report("production: second's mid and leaf read second's token", production.second.mid.token === production.second.token && production.second.mid.leaf.token === production.second.token)
report("production: third's mid and leaf read the root's token", productionThird.token === production.token && productionThird.leaf.token === production.token)
