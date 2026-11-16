import Core
import Feat
import Harness
import SafeDI

#if DEBUG
	// Hand-written callers of the readable mock; they must compile unchanged.
	func handWrittenCallers() -> [Home] {
		[
			Home.mock(apiBuilder: { Live(meter: Meter(), badge: nil) }),
			Home.mock(apiBuilder: { Live(meter: Meter(), badge: nil) }, safeDIOverrides: .init(meter: { Meter() })),
		]
	}
#endif
