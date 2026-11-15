import Feature
import Harness
import Inner
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_store() -> Store {
			func __safeDI_apiSendableBuilder_Store() -> Store.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
				@Sendable func __safeDI_liveApi(db: Db) -> any Api {
					LiveApi(db: db)
				}
				return .init(aBuilder: { values in .init(api: { _ in __safeDI_liveApi(db: values.db) }) })
			}
			return Store(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Store())
		}
		let store: Store = __safeDI_store()
		self.init(store: store)
	}
}
