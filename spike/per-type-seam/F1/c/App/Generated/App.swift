// The calling module's code under the leak fix, written by hand: one level function per level. (c) and (d) share it.
import Feature
import Harness
import SafeDI

extension Root {
    public convenience init() {
        let session = Session()
        func __safeDI_service() -> Service {
            func __safeDI_userServiceBuilder_Service() -> Service.SafeDIScope_UserService.__safeDI_Builder<any UserService> {
                .init(
                    home: { values in __safeDI_userServiceBuilder_Service_Home_Scope(analytics: values.analytics) },
                    settings: { values in __safeDI_userServiceBuilder_Service_Settings_Scope(analytics: values.analytics, session: session) }
                )
            }
            func __safeDI_userServiceBuilder_Service_Home_Scope(analytics: Analytics) -> Service.SafeDIScope_UserService.Home_Scope.__safeDI_Builder<any UserService> {
                .init(avatar: { values in __safeDI_userServiceBuilder_Service_Avatar_Scope(analytics: analytics, session: values.session) })
            }
            func __safeDI_userServiceBuilder_Service_Avatar_Scope(analytics: Analytics, session: Session?) -> Service.SafeDIScope_UserService.Avatar_Scope.__safeDI_Builder<any UserService> {
                func __safeDI_defaultUserService() -> any UserService {
                    DefaultUserService(analytics: analytics, session: session)
                }
                return .init(userService: { _ in __safeDI_defaultUserService() })
            }
            func __safeDI_userServiceBuilder_Service_Settings_Scope(analytics: Analytics, session: Session?) -> Service.SafeDIScope_UserService.Settings_Scope.__safeDI_Builder<any UserService> {
                .init(avatar: { _ in __safeDI_userServiceBuilder_Service_Avatar_Scope(analytics: analytics, session: session) })
            }
            return Service(__safeDI_userServiceBuilder: __safeDI_userServiceBuilder_Service())
        }
        let service: Service = __safeDI_service()
        self.init(session: session, service: service)
    }
}
