// (d) per-type, written by hand: (c)'s struct, unchanged, with one function per type in the body.
import Harness
import SafeDI

extension Service {
    nonisolated public enum SafeDIScope_UserService {
        nonisolated public struct home_Values {
            public let analytics: Analytics
        }

        nonisolated public struct settings_Values {
            public let analytics: Analytics
            public let home: Home
        }

        nonisolated public struct __safeDI_Builder<Built> {
            public let home: (home_Values) -> Home_Scope.__safeDI_Builder<Built>
            public let settings: (settings_Values) -> Settings_Scope.__safeDI_Builder<Built>

            public init(home: @escaping (home_Values) -> Home_Scope.__safeDI_Builder<Built>, settings: @escaping (settings_Values) -> Settings_Scope.__safeDI_Builder<Built>) {
                self.home = home
                self.settings = settings
            }

            public init(__safeDI_noScope builder: @escaping () -> Built) {
                home = { _ in .init(__safeDI_noScope: builder) }
                settings = { _ in .init(__safeDI_noScope: builder) }
            }
        }

        nonisolated public enum Home_Scope {
            nonisolated public struct avatar_Values {
                public let session: Session
            }

            nonisolated public struct __safeDI_Builder<Built> {
                public let avatar: (avatar_Values) -> Avatar_Scope.__safeDI_Builder<Built>

                public init(avatar: @escaping (avatar_Values) -> Avatar_Scope.__safeDI_Builder<Built>) {
                    self.avatar = avatar
                }

                public init(__safeDI_noScope builder: @escaping () -> Built) {
                    avatar = { _ in .init(__safeDI_noScope: builder) }
                }
            }
        }

        nonisolated public enum Settings_Scope {
            nonisolated public struct avatar_Values {
                public let theme: Theme
            }

            nonisolated public struct __safeDI_Builder<Built> {
                public let avatar: (avatar_Values) -> Avatar_Scope.__safeDI_Builder<Built>

                public init(avatar: @escaping (avatar_Values) -> Avatar_Scope.__safeDI_Builder<Built>) {
                    self.avatar = avatar
                }

                public init(__safeDI_noScope builder: @escaping () -> Built) {
                    avatar = { _ in .init(__safeDI_noScope: builder) }
                }
            }
        }

        nonisolated public enum Avatar_Scope {
            nonisolated public struct userService_Values {}

            nonisolated public struct __safeDI_Builder<Built> {
                public let userService: (userService_Values) -> Built

                public init(userService: @escaping (userService_Values) -> Built) {
                    self.userService = userService
                }

                public init(__safeDI_noScope builder: @escaping () -> Built) {
                    userService = { _ in builder() }
                }
            }
        }
    }

    /// For code you write.
    public convenience init(userServiceBuilder: @escaping () -> any UserService) {
        self.init(__safeDI_userServiceBuilder: .init(__safeDI_noScope: userServiceBuilder))
    }

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_userServiceBuilder: SafeDIScope_UserService.__safeDI_Builder<any UserService>) {
        func __safeDI_avatar(_ __safeDI_userServiceBuilder: SafeDIScope_UserService.Avatar_Scope.__safeDI_Builder<any UserService>) -> Avatar {
            let userService: any UserService = __safeDI_userServiceBuilder.userService(.init())
            return Avatar(userService: userService)
        }
        let analytics = Analytics()
        let __safeDI_userServiceBuilder_home = __safeDI_userServiceBuilder.home(.init(analytics: analytics))
        func __safeDI_home() -> Home {
            let session = Session()
            let avatar: Avatar = __safeDI_avatar(__safeDI_userServiceBuilder_home.avatar(.init(session: session)))
            return Home(session: session, avatar: avatar)
        }
        let home: Home = __safeDI_home()
        let __safeDI_userServiceBuilder_settings = __safeDI_userServiceBuilder.settings(.init(analytics: analytics, home: home))
        func __safeDI_settings() -> Settings {
            let theme = Theme()
            let avatar: Avatar = __safeDI_avatar(__safeDI_userServiceBuilder_settings.avatar(.init(theme: theme)))
            return Settings(theme: theme, avatar: avatar)
        }
        let settings: Settings = __safeDI_settings()
        self.init(analytics: analytics, home: home, settings: settings)
    }
}
