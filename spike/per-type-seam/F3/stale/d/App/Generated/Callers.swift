import Core
import Feat
import Harness
import SafeDI

#if DEBUG
	// Hand-written callers of the readable mock; they must compile unchanged against (c) and (d).
	func handWrittenCallers() -> [Home] {
		[
			Home.mock(apiBuilder: { Live(cache: Cache()) }),
			Home.mock { Live(cache: Cache()) },
		]
	}
#endif
