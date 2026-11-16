import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Home] {
	[
		Home { Live(id: 0) },
		Home(apiBuilder: { Live(id: 1) }),
	]
}
