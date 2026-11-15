import Harness
import SafeDI

extension Home {
    nonisolated public enum SafeDIScope_Api {
        nonisolated public struct screenBuilder_Values {}

        nonisolated public struct __safeDI_Builder<Built> {
            public let screenBuilder: (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>

            public init(screenBuilder: @escaping (screenBuilder_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
                self.screenBuilder = screenBuilder
            }

            public init(__safeDI_noScope builder: @escaping () -> Built) {
                screenBuilder = { _ in .init(__safeDI_noScope: builder) }
            }
        }

        nonisolated public enum Screen_Scope {
            nonisolated public struct api_Values {}

            nonisolated public struct __safeDI_Builder<Built> {
                public let api: (api_Values) -> Built

                public init(api: @escaping (api_Values) -> Built) {
                    self.api = api
                }

                public init(__safeDI_noScope builder: @escaping () -> Built) {
                    api = { _ in builder() }
                }
            }
        }
    }

    nonisolated public enum SafeDISendableScope_Api {
        nonisolated public struct screenBuilder_Sendable_Values: Sendable {}

        nonisolated public struct __safeDI_Builder<Built>: Sendable {
            public let screenBuilder_Sendable: @Sendable (screenBuilder_Sendable_Values) -> Screen_Scope.__safeDI_Builder<Built>

            public init(screenBuilder_Sendable: @escaping @Sendable (screenBuilder_Sendable_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
                self.screenBuilder_Sendable = screenBuilder_Sendable
            }

            public init(__safeDI_noScope builder: @escaping @Sendable () -> Built) {
                screenBuilder_Sendable = { _ in .init(__safeDI_noScope: builder) }
            }
        }

        nonisolated public enum Screen_Scope {
            nonisolated public struct again_Values: Sendable {}

            nonisolated public struct __safeDI_Builder<Built>: Sendable {
                public let again: @Sendable (again_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<Built>

                public init(again: @escaping @Sendable (again_Values) -> SafeDIScope_Api.Screen_Scope.__safeDI_Builder<Built>) {
                    self.again = again
                }

                public init(__safeDI_noScope builder: @escaping @Sendable () -> Built) {
                    again = { _ in .init(__safeDI_noScope: builder) }
                }
            }
        }
    }

    /// For code you write.
    public convenience init(apiBuilder: @escaping () -> any Api, apiSendableBuilder: @escaping @Sendable () -> any Api) {
        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder), __safeDI_apiSendableBuilder: .init(__safeDI_noScope: apiSendableBuilder))
    }

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>, __safeDI_apiSendableBuilder: SafeDISendableScope_Api.__safeDI_Builder<any Api>) {
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        func __safeDI_screenBuilder() -> Screen {
            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(.init())
            let __safeDI_apiSendableBuilder_screenBuilder = __safeDI_apiSendableBuilder.screenBuilder_Sendable(.init())
            @Sendable nonisolated func __safeDI_again() -> Screen {
                let __safeDI_apiBuilder_again = __safeDI_apiSendableBuilder_screenBuilder.again(.init())
                let api: any Api = __safeDI_apiBuilder_again.api(.init())
                let again = SendableInstantiator<Screen>(__safeDI_again)
                return Screen(api: api, again: again)
            }
            let again = SendableInstantiator<Screen>(__safeDI_again)
            return Screen(api: api, again: again)
        }
        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
        self.init(screenBuilder: screenBuilder)
    }
}
