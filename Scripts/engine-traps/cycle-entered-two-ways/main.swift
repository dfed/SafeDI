func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

let root = Root.mock(safeDIOverrides: .init(
	aBuilder: .init(bBuilder: .init(leaf: .init(name: "B beneath A's entry")), leaf: .init(name: "A's entry")),
	bBuilder: .init(leaf: .init(name: "B's entry")),
))
let a = root.aBuilder.instantiate()
report("entered at A, lap 1, A's leaf", a.leaf.name)
let aB = a.bBuilder.instantiate()
report("entered at A, lap 1, B's leaf", aB.leaf.name)
let aBA = aB.aBuilder.instantiate()
report("entered at A, lap 2, A's leaf", aBA.leaf.name)
let aBAB = aBA.bBuilder.instantiate()
report("entered at A, lap 2, B's leaf", aBAB.leaf.name)
report("entered at A, lap 3, A's leaf", aBAB.aBuilder.instantiate().leaf.name)
let b = root.bBuilder.instantiate()
report("entered at B, lap 1, B's leaf", b.leaf.name)
let bA = b.aBuilder.instantiate()
report("entered at B, lap 1, A's leaf", bA.leaf.name)
let bAB = bA.bBuilder.instantiate()
report("entered at B, lap 2, B's leaf", bAB.leaf.name)
let bABA = bAB.aBuilder.instantiate()
report("entered at B, lap 2, A's leaf", bABA.leaf.name)
report("entered at B, lap 3, B's leaf", bABA.bBuilder.instantiate().leaf.name)
