import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Home] {
	[
		Home { Live(cache: Cache()) },
		Home(apiBuilder: { Live(cache: Cache()) }),
	]
}
