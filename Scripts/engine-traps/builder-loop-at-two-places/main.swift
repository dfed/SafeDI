func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

let root = Root.mock()
let leftB = root.left.aBuilder.instantiate().bBuilder.instantiate()
let rightB = root.right.aBuilder.instantiate().bBuilder.instantiate()
report("the two parents hold tokens of their own", root.left.token !== root.right.token)
report("left's B, built by left's A, reads left's token", leftB.token === root.left.token)
report("right's B, built by right's A, reads right's token", rightB.token === root.right.token)
report("right's B on the second lap reads right's token", rightB.aBuilder.instantiate().bBuilder.instantiate().token === root.right.token)
report("right's B built directly reads right's token", root.right.bBuilder.instantiate().token === root.right.token)
report("left's B on the second lap reads left's token", leftB.aBuilder.instantiate().bBuilder.instantiate().token === root.left.token)

let marked = Root.mock(safeDIOverrides: .init(
	left: .init(bBuilder: { aBuilder, token in
		let b = B(aBuilder: aBuilder, token: token)
		b.note = "left's B override"
		return b
	}),
	right: .init(aBuilder: { bBuilder in
		let a = A(bBuilder: bBuilder)
		a.note = "right's A override"
		return a
	}),
))
report("left's B built directly", marked.left.bBuilder.instantiate().note)
report("left's B built by left's A", marked.left.aBuilder.instantiate().bBuilder.instantiate().note)
report("left's A", marked.left.aBuilder.instantiate().note)
report("left's A built by left's B", marked.left.bBuilder.instantiate().aBuilder.instantiate().note)
report("right's B built directly", marked.right.bBuilder.instantiate().note)
report("right's B built by right's A", marked.right.aBuilder.instantiate().bBuilder.instantiate().note)
report("right's A", marked.right.aBuilder.instantiate().note)
report("right's A built by right's B", marked.right.bBuilder.instantiate().aBuilder.instantiate().note)

let production = Root()
let productionRightB = production.right.aBuilder.instantiate().bBuilder.instantiate()
report("production: left's B, built by left's A, reads left's token", production.left.aBuilder.instantiate().bBuilder.instantiate().token === production.left.token)
report("production: right's B, built by right's A, reads right's token", productionRightB.token === production.right.token)
report("production: right's B on the second lap reads right's token", productionRightB.aBuilder.instantiate().bBuilder.instantiate().token === production.right.token)
