func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

let root = Root.mock(
	clock: SystemClock(),
	safeDIOverrides: .init(
		firstBuilder: .init(header: .init(name: "first's header")),
		secondBuilder: .init({ header, clock in Screen(header: Header(clock: clock, name: "second's screen override"), clock: clock) }),
		plain: .init(header: .init { clock, _ in Header(clock: clock, name: "plain's header override") }),
	),
)
let first = root.firstBuilder.instantiate()
let firstAgain = root.firstBuilder.instantiate()
let second = root.secondBuilder.instantiate()
report("first's header", first.header.name)
report("second's header", second.header.name)
report("plain's header", root.plain.header.name)
report("each construction creates its own clock", first.clock !== firstAgain.clock && first.clock !== second.clock && first.clock !== root.plain.clock)
report("a screen and its header share the screen's clock", first.clock === first.header.clock && firstAgain.clock === firstAgain.header.clock && second.clock === second.header.clock && root.plain.clock === root.plain.header.clock)
