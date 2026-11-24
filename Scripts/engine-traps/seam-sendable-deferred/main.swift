func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

@Sendable func makeSession() -> Session {
	Counts.sessionsFromTheCaller.withLock { $0 += 1 }
	return Session()
}

func created() -> Int { Counts.sessionsFromTheCaller.withLock { $0 } }

let feature = Feature(__safeDI_session: makeSession())
report("sessions created once the tree is built", created())
let panel = feature.panelBuilder.instantiate()
let panelScreen = panel.screenBuilder.instantiate("panel")
report("sessions created after the panel's screen", created())
report("the panel's reader", "\(panelScreen.reader.id) \(panelScreen.reader.session === panel.session)")
let panelBuilt = panelScreen.readerBuilder.instantiate()
report("the panel's built reader", "\(panelBuilt.id) \(panelBuilt.session === panel.session)")
let first = feature.screenBuilder.instantiate("first")
report("sessions created after the first screen", created())
let second = feature.screenBuilder.instantiate("second")
let secondBuilt = second.readerBuilder.instantiate()
let firstBuilt = first.readerBuilder.instantiate()
report("the first screen's readers", "\(first.reader.id) \(firstBuilt.id)")
report("the second screen's readers", "\(second.reader.id) \(secondBuilt.id)")
report("the top readers share the caller's session", first.reader.session === secondBuilt.session && firstBuilt.session === second.reader.session)
report("the caller's session is not the panel's", first.reader.session !== panel.session)
report("sessions created at the end", created())
