import Feature
import Harness
import SafeDI

extension Root {
    public convenience init() {
        func __safeDI_hub() -> Hub {
            func __safeDI_apiBuilder_Hub() -> Hub.SafeDIScope_Api.__safeDI_Builder<any Api> {
                .init(t: { _ in __safeDI_apiBuilder_Hub_T_Scope() })
            }
            @Sendable func __safeDI_apiBuilder_Hub_T_Scope() -> Hub.SafeDIScope_Api.T_Scope.__safeDI_Builder<any Api> {
                @Sendable func __safeDI_liveApi() -> any Api {
                    LiveApi()
                }
                return .init(api: { _ in __safeDI_liveApi() })
            }
            func __safeDI_apiSendableBuilder_Hub() -> Hub.SafeDISendableScope_Api.__safeDI_Builder<any Api> {
                .init(tBuilder: { _ in __safeDI_apiBuilder_Hub_T_Scope() })
            }
            return Hub(__safeDI_apiBuilder: __safeDI_apiBuilder_Hub(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Hub())
        }
        let hub: Hub = __safeDI_hub()
        self.init(hub: hub)
    }
}
