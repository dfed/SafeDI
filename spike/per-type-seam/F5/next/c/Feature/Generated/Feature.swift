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
            nonisolated public struct api_Values {
                public let id: Int
            }

            nonisolated public struct next_Values {
                public let id: Int
                public let api: any Api
            }

            nonisolated public struct __safeDI_Builder<Built> {
                public let api: (api_Values) -> Built
                public let next: (next_Values) -> Screen_Scope.__safeDI_Builder<Built>

                public init(api: @escaping (api_Values) -> Built, next: @escaping (next_Values) -> Screen_Scope.__safeDI_Builder<Built>) {
                    self.api = api
                    self.next = next
                }

                public init(__safeDI_noScope builder: @escaping () -> Built) {
                    api = { _ in builder() }
                    next = { _ in .init(__safeDI_noScope: builder) }
                }
            }
        }
    }

    /// For code you write.
    public convenience init(apiBuilder: @escaping () -> any Api) {
        self.init(__safeDI_apiBuilder: .init(__safeDI_noScope: apiBuilder))
    }

    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
        let __safeDI_apiBuilder_screenBuilder = __safeDI_apiBuilder.screenBuilder(.init())
        func __safeDI_screenBuilder(id: Int) -> Screen {
            let api: any Api = __safeDI_apiBuilder_screenBuilder.api(.init(id: id))
            let __safeDI_apiBuilder_next = __safeDI_apiBuilder_screenBuilder.next(.init(id: id, api: api))
            func __safeDI_next(id: Int) -> Screen {
                let api: any Api = __safeDI_apiBuilder_next.api(.init(id: id))
                let next = Instantiator<Screen> {
                    __safeDI_next(id: $0)
                }
                return Screen(id: id, api: api, next: next)
            }
            let next = Instantiator<Screen> {
                __safeDI_next(id: $0)
            }
            return Screen(id: id, api: api, next: next)
        }
        let screenBuilder = Instantiator<Screen> {
            __safeDI_screenBuilder(id: $0)
        }
        self.init(screenBuilder: screenBuilder)
    }
}
