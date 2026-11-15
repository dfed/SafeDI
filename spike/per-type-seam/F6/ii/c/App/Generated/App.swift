import Feature
import Harness
import SafeDI

extension Root {
    public convenience init() {
        func __safeDI_home() -> Home {
            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
                .init(screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
            }
            @Sendable func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
                @Sendable func __safeDI_liveApi() -> any Api {
                    LiveApi()
                }
                return .init(api: { _ in __safeDI_liveApi() })
            }
            func __safeDI_apiSendableBuilder_Home() -> Home.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
                .init(screenBuilder_Sendable: { _ in __safeDI_apiSendableBuilder_Home_Screen_Scope() })
            }
            @Sendable func __safeDI_apiSendableBuilder_Home_Screen_Scope() -> Home.SafeDISendableScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
                .init(again: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
            }
            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
        }
        let home: Home = __safeDI_home()
        self.init(home: home)
    }
}
