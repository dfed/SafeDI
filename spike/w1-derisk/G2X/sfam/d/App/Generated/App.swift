import Feature
import Harness
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_store() -> Store {
			@Sendable
			func __safeDI_apiSendableBuilder_A() -> A.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
				.init(innerBuilder: { _ in __safeDI_apiBuilder_A_Inner_Scope() })
			}
			@Sendable
			func __safeDI_apiBuilder_A_Inner_Scope() -> A.SafeDIScope_Api.Inner_Scope.__safeDI_Builder<any Api> {
				@Sendable
				func __safeDI_liveApi() -> any Api {
					let sideBuilder = SendableInstantiator<Side>(__safeDI_sideBuilder)
					return LiveApi(sideBuilder: sideBuilder)
				}
				return .init(api: { _ in __safeDI_liveApi() })
			}
			@Sendable
			func __safeDI_aBuilder() -> A {
				A(__safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_A())
			}
			let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			@Sendable
			func __safeDI_sideBuilder() -> Side {
				let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
				return Side(aBuilder: aBuilder)
			}
			let sideBuilder = SendableInstantiator<Side>(__safeDI_sideBuilder)
			return Store(aBuilder: aBuilder, sideBuilder: sideBuilder)
		}
		let store: Store = __safeDI_store()
		self.init(store: store)
	}
}
