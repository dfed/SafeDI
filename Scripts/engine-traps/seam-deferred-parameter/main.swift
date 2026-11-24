func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

var created = 0
@MainActor func makeSession() -> Session {
	created += 1
	return Session()
}

let feature = Feature(__safeDI_session: makeSession())
report("sessions created once the tree is built", created)
let panelScreen = feature.panel.screenBuilder.instantiate()
report("the panel's screen reads the panel's session", panelScreen.session === feature.panel.session)
report("sessions created after the panel's screen", created)
let screen = feature.screenBuilder.instantiate()
report("sessions created after the top screen", created)
let sub = feature.subBuilder.instantiate()
report("sessions created after the sub", created)
report("the top screen and the sub's screen share the caller's session", screen.session === sub.screen.session)
report("the caller's session is not the panel's", screen.session !== feature.panel.session)
report("a second top screen shares it too", feature.screenBuilder.instantiate().session === screen.session)
report("sessions created at the end", created)
