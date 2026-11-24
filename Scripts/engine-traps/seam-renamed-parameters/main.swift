func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

var created: [String] = []
@MainActor func makeSession(_ name: String) -> Session {
	created.append(name)
	return Session(name: name)
}

let feature = Feature(
	__safeDI_first: makeSession("first"),
	__safeDI_second: makeSession("second"),
	__safeDI_session: makeSession("session"),
)
report("sessions created once the tree is built", created)
let right = feature.rightBuilder.instantiate()
report("sessions created after the right", created)
report("the right's holder", right.holder.session.name)
report("the right's built holder", right.holderBuilder.instantiate().session.name)
let top = feature.holderBuilder.instantiate()
report("sessions created after the top holder", created)
report("the top holder", top.session.name)
let left = feature.leftBuilder.instantiate()
report("sessions created after the left", created)
report("the left's holder", left.holder.session.name)
report("the left's built holder", left.holderBuilder.instantiate().session.name)
report("a second right's holder shares the session", feature.rightBuilder.instantiate().holder.session === right.session)
report("sessions created at the end", created)
