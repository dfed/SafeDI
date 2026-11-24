func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

var created = 0
@MainActor func makeSession() -> Session {
	created += 1
	return Session()
}

let feature = Feature(__safeDI_session: makeSession())
report("sessions created once the tree is built", created)
let panel = feature.panelBuilder.instantiate()
report("sessions created after the panel", created)
report("the panel's inner reads the panel's session", panel.inner.readerBuilder.instantiate().session === panel.session)
report("the panel's built inner reads the panel's session", panel.innerBuilder.instantiate().readerBuilder.instantiate().session === panel.session)
report("sessions created after the panel's readers", created)
let inner = feature.innerBuilder.instantiate()
report("sessions created after the top inner", created)
let reader = inner.readerBuilder.instantiate()
report("sessions created after the top reader", created)
report("the top reader does not read the panel's session", reader.session !== panel.session)
report("a second top inner's reader shares the caller's session", feature.innerBuilder.instantiate().readerBuilder.instantiate().session === reader.session)
report("sessions created at the end", created)
