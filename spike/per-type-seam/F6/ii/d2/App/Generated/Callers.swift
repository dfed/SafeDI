import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Home] {
	[
		Home(apiBuilder: { LiveApi() }, apiSendableBuilder: { LiveApi() }),
		Home(apiBuilder: LiveApi.init, apiSendableBuilder: LiveApi.init),
	]
}
