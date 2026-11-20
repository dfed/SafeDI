import Seam
@MainActor protocol AppLike { init() }
#if MAIN_IMPL
@MainActor final class Impl: Api { let id: Int; init(id: Int) { self.id = id }; nonisolated func v() -> Int { 0 } }
#else
final class Impl: Api { let id: Int; init(id: Int) { self.id = id }; func v() -> Int { id } }
#endif
nonisolated final class Plain: Api, Sendable { init() {}; func v() -> Int { 1 } }
final class Analytics { init() {} }
#if ATTR_ROOT
nonisolated final class Root { let home: Home
    @MainActor init() { home = Root.__safeDI_make() } }
#elseif CLASS_ROOT
@MainActor class Root { let home: Home
    init() { home = Self.__safeDI_make() } }
#else
struct Root: AppLike { let home: Home
    init() { home = Root.__safeDI_make() } }
#endif
extension Root {
    nonisolated final class __safeDI_Home_RootContext { let analytics: Analytics; init(analytics: Analytics) { self.analytics = analytics } }
    nonisolated final class __safeDI_Home_DetailContext { let analytics: Analytics; let model: Model; init(analytics: Analytics, model: Model) { self.analytics = analytics; self.model = model } }
#if ATTR_ROOT
    @MainActor
#endif
    static func __safeDI_fill_apiOfScreen(id: Int, analytics: Analytics) -> any Api { Impl(id: id) }
#if ATTR_ROOT
    @MainActor
#endif
    static func __safeDI_fill_apiOfDetail(id: Int, analytics: Analytics, model: Model) -> any Api { Impl(id: id &+ model.n) }
    nonisolated static func __safeDI_fill_apiOfWork(id: Int) -> any Api { Plain() }
    nonisolated static func __safeDI_fill_apiOfDetail_1(id: Int) -> any Api { Plain() }
#if ATTR_ROOT
    @MainActor
#endif
    static func __safeDI_form_Detail(_ context: __safeDI_Home_DetailContext) -> Home.__safeDI_DetailCarrier {
        .init(apiOfDetail: { id in Self.__safeDI_fill_apiOfDetail(id: id, analytics: context.analytics, model: context.model) })
    }
    nonisolated static func __safeDI_form_Detail_1() -> Home.__safeDI_DetailCarrier {
        .init(apiOfDetail: { id in Self.__safeDI_fill_apiOfDetail_1(id: id) })
    }
#if ATTR_ROOT
    @MainActor
#endif
    static func __safeDI_form_Home(_ context: __safeDI_Home_RootContext) -> Home.__safeDI_HomeCarrier {
        let screenCarrier = Home.__safeDI_ScreenCarrier(
            apiOfScreen: { id in Self.__safeDI_fill_apiOfScreen(id: id, analytics: context.analytics) },
            enterDetailOfScreen: { _, model in Self.__safeDI_form_Detail(.init(analytics: context.analytics, model: model)) },
            enterNextOfScreen: { carrier, _, _ in carrier })
        return .init(screen: screenCarrier)
    }
    nonisolated static func __safeDI_form_HomeSendable() -> Home.__safeDI_HomeSendableCarrier {
        .init(work: .init(apiOfWork: { id in Self.__safeDI_fill_apiOfWork(id: id) }, enterDetailOfWork: { _ in Self.__safeDI_form_Detail_1() }))
    }
#if ATTR_ROOT
    @MainActor
#endif
    static func __safeDI_make() -> Home {
        Home(__safeDI_home: __safeDI_form_Home(.init(analytics: Analytics())), __safeDI_homeSendable: __safeDI_form_HomeSendable())
    }
}
