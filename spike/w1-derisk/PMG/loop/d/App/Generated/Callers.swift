import Core
import Feat
import Harness
import SafeDI

#if DEBUG
	// A hand-written caller of the readable mock; it must compile unchanged.
	func handWrittenCallers(api: any Api) -> [Store] {
		[Store.mock(apiBuilder: { api }), Store.mock { api }]
	}
#endif
