import Core
import Feat
import Harness
import SafeDI

#if DEBUG
extension Root {
    /// Overrides for the mock dependency tree.
    struct SafeDIOverrides {
        init(
            home: Home.SafeDIOverrides = .init()
        ) {
            self.home = home
        }

        let home: Home.SafeDIOverrides
    }

    static func mock(
        safeDIOverrides: SafeDIOverrides = .init()
    ) -> Root {
        func __safeDI_home() -> Home {
            func __safeDI_apiBuilder_Home() -> Home.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
                .init(screen: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
            }
            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
                .init(stepBuilder: { values in __safeDI_apiBuilder_Home_Step_Scope(cache: values.cache) })
            }
            func __safeDI_apiBuilder_Home_Step_Scope(cache: Cache) -> Home.SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api> {
                func __safeDI_live() -> any Api {
                    Live(cache: cache)
                }
                return .init(
                    api: { _ in __safeDI_live() },
                    screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }
                )
            }
            return Home.__safeDI_mock(apiBuilder: __safeDI_apiBuilder_Home(), safeDIOverrides: safeDIOverrides.home)
        }
        let home: Home = __safeDI_home()
        return Root(home: home)
    }
}
#endif
