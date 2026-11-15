import Feature
import Harness
import Inner
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_store() -> Store {
			func __safeDI_apiSendableBuilder_Store() -> Store.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
				@Sendable
				func __safeDI_liveApi(sideBuilder: SendableInstantiator<Side>) -> any Api {
					LiveApi(sideBuilder: sideBuilder)
				}
				@Sendable
				func __safeDI_apiBuilder_A_InnerT_Scope(sideBuilder: SendableInstantiator<Side>) -> A.SafeDIScope_Api.InnerT_Scope.__safeDI_Builder<any Api> {
					.init(api: { _ in __safeDI_liveApi(sideBuilder: sideBuilder) })
				}
				return .init(aBuilder: { values in .init(tBuilder: { _ in __safeDI_apiBuilder_A_InnerT_Scope(sideBuilder: values.sideBuilder) }) })
			}
			return Store(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Store())
		}
		let store: Store = __safeDI_store()
		self.init(store: store)
	}
}
