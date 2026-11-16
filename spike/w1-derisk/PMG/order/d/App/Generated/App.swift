import Core
import Feat
import Harness
import SafeDI

#if DEBUG
	extension Root {
		/// Overrides for the mock dependency tree.
		struct SafeDIOverrides {
			init(
				home: Home.SafeDIOverrides = .init(),
			) {
				self.home = home
			}

			let home: Home.SafeDIOverrides
		}

		static func mock(
			safeDIOverrides: SafeDIOverrides = .init(),
		) -> Root {
			func __safeDI_home() -> Home {
				// One level function per scope type; each takes what the levels above bound, `nil` where a path bound nothing.
				func __safeDI_apiBuilder_Home() -> Home.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
					.init(
						a: { values in __safeDI_apiBuilder_Home_Sub_Scope(meter: values.meter, badge: nil) },
						b: { values in __safeDI_apiBuilder_Home_Sub_Scope(meter: values.previous.meter, badge: values.badge) },
					)
				}
				func __safeDI_apiBuilder_Home_Sub_Scope(meter: Meter, badge: Badge?) -> Home.SafeDIMockScope_Api.Sub_Scope.__safeDI_Builder<any Api> {
					func __safeDI_live() -> any Api {
						Live(meter: meter, badge: badge)
					}
					return .init(api: { _ in __safeDI_live() })
				}
				return Home.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_Home(), safeDIOverrides: safeDIOverrides.home)
			}
			let home: Home = __safeDI_home()
			return Root(home: home)
		}
	}
#endif
