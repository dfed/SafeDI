import Feature
import Harness
import Inner
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_store() -> Store {
			// Per-type: one fill function for LiveApi, used by both families' level functions.
			@Sendable
			func __safeDI_liveApi(db: Db) -> any Api {
				LiveApi(db: db)
			}
			func __safeDI_apiBuilder_Store() -> Store.SafeDIScope_Api.__safeDI_Builder<any Api> {
				.init(a: { values in .init(api: { _ in __safeDI_liveApi(db: values.db) }) })
			}
			func __safeDI_apiSendableBuilder_Store() -> Store.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
				.init(aBuilder: { values in .init(api: { _ in __safeDI_liveApi(db: values.db) }) })
			}
			return Store(__safeDI_apiBuilder: __safeDI_apiBuilder_Store(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Store())
		}
		let store: Store = __safeDI_store()
		self.init(store: store)
	}
}
