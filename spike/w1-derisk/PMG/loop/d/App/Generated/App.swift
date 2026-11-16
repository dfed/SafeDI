import Core
import Feat
import Harness
import SafeDI

#if DEBUG
	extension Root {
		/// Overrides for the mock dependency tree.
		struct SafeDIOverrides {
			init(
				store: Store.SafeDIOverrides = .init(),
			) {
				self.store = store
			}

			let store: Store.SafeDIOverrides
		}

		static func mock(
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Root {
			func __safeDI_store() -> Store {
				func __safeDI_apiBuilder_Store() -> Store.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
					.init(aBuilder: { values in __safeDI_apiBuilder_Store_A_Scope(sideBuilder: values.sideBuilder) })
				}
				func __safeDI_apiBuilder_Store_A_Scope(sideBuilder: Instantiator<Side>) -> Store.SafeDIMockScope_Api.A_Scope.__safeDI_Builder<any Api> {
					func __safeDI_liveApi() -> any Api {
						LiveApi(sideBuilder: sideBuilder)
					}
					return .init(api: { _ in __safeDI_liveApi() })
				}
				return Store.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_Store(), safeDIOverrides: safeDIOverrides.store)
			}
			let store: Store = __safeDI_store()
			return Root(store: store)
		}
	}
#endif
