func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

@MainActor func describe(_ name: String, _ root: Root) {
	var stamps: [Stamp] = []
	var clocks: [any Clock] = []
	for (entry, screenBuilder) in [("left", root.left.screenBuilder), ("right", root.right.screenBuilder), ("top", root.screenBuilder)] {
		let one = screenBuilder.instantiate("\(entry) one")
		let two = screenBuilder.instantiate("\(entry) two")
		let oneBuilt = one.headerBuilder.instantiate()
		let oneBuiltAgain = one.headerBuilder.instantiate()
		let twoBuilt = two.headerBuilder.instantiate()
		stamps += [one.stamp, two.stamp]
		clocks += [one.clock, two.clock]
		report("\(name): \(entry): stamps (one, two)", [one.stamp.name, two.stamp.name])
		report("\(name): \(entry): headers (one, one built, one built again, two, two built)", [one.header.name, oneBuilt.name, oneBuiltAgain.name, two.header.name, twoBuilt.name])
		report("\(name): \(entry): ids (one, one built, two, two built)", [one.header.id, oneBuilt.id, two.header.id, twoBuilt.id])
		report("\(name): \(entry): a screen's headers read that screen's stamp and clock", [(one, [one.header, oneBuilt, oneBuiltAgain]), (two, [two.header, twoBuilt])].allSatisfy { screen, headers in headers.allSatisfy { $0.stamp === screen.stamp && $0.clock === screen.clock } })
	}
	report("\(name): distinct stamps and clocks among six screens", "\(Set(stamps.map(ObjectIdentifier.init)).count) \(Set(clocks.map { ObjectIdentifier($0) }).count)")
}

describe("no overrides", Root.mock(clock: SystemClock()))
describe("names per entry", Root.mock(
	clock: SystemClock(),
	safeDIOverrides: .init(
		left: .init(screenBuilder: .init(stamp: .init(name: "left stamp"), header: .init(name: "left header"), headerBuilder: .init(name: "left built header"))),
		right: .init(screenBuilder: .init(headerBuilder: .init(name: "right built header"))),
		screenBuilder: .init(stamp: .init(name: "top stamp"), header: .init(name: "top header")),
	),
))
describe("names asked for at each construction, and builders", Root.mock(
	clock: SystemClock(),
	safeDIOverrides: .init(
		left: .init(screenBuilder: .init(stamp: .init(name: Names.next("left stamp")), headerBuilder: .init(name: Names.next("left built header")))),
		right: .init(screenBuilder: .init(header: .init { id, stamp, clock, _ in Header(id: id, stamp: stamp, clock: clock, name: "right header from a builder") })),
		screenBuilder: .init { id, stamp, clock, header, headerBuilder in Screen(id: id + " through a builder", stamp: stamp, clock: clock, header: header, headerBuilder: headerBuilder) },
	),
))
report("times each name was asked for", Names.asked.withLock { asked in asked.keys.sorted().map { "\($0): \(asked[$0] ?? 0)" } })
