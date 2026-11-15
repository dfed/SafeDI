import Feature
import Harness
import SafeDI

// Hand-written callers of the readable initializer; they must compile unchanged against (c) and (d).
func handWrittenCallers() -> [Hub] {
	[
		Hub(apiBuilder: { LiveApi() }, apiSendableBuilder: { LiveApi() }),
		Hub(apiBuilder: LiveApi.init, apiSendableBuilder: LiveApi.init),
	]
}
