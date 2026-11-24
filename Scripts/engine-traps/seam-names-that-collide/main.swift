func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

var created: [String] = []
@MainActor func makeSession(_ name: String) -> Session {
	created.append(name)
	return Session(name: name)
}

let feature = Feature(
	__safeDI_first: makeSession("first"),
	__safeDI_holderBuilder_: makeSession("holderBuilder_"),
	__safeDI_second: makeSession("second"),
	__safeDI_session: makeSession("session"),
	__safeDI_session_: makeSession("session_"),
)
report("sessions created once the tree is built", created)
report("the eager values", "\(feature.eager.holderBuilder_.name) \(feature.eager.session_.name)")
let right = feature.rightBuilder.instantiate()
report("the right's holders", "\(right.holder.session.name) \(right.holderBuilder.instantiate().session.name)")
report("the top holder", feature.holderBuilder.instantiate().session.name)
let left = feature.leftBuilder.instantiate()
report("the left's holders", "\(left.holder.session.name) \(left.holderBuilder.instantiate().session.name)")
report("sessions created at the end", created)
