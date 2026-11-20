// One plain carrier type formed at two positions: in a @MainActor root initializer, and per entry inside a @Sendable entry.
@MainActor final class View { init() {} }
nonisolated final class DetailCarrier { let view: () -> View; init(view: @escaping () -> View) { self.view = view } }
nonisolated final class ScreenSendableCarrier: Sendable { let enterDetail: @Sendable () -> DetailCarrier; init(enterDetail: @escaping @Sendable () -> DetailCarrier) { self.enterDetail = enterDetail } }
@MainActor struct Root {
    let detail: DetailCarrier
    let screen: ScreenSendableCarrier
    init() {
        detail = Self.__safeDI_form_Detail()                       // position 1: @MainActor context
        screen = ScreenSendableCarrier(enterDetail: { Self.__safeDI_form_Detail() })   // position 2: inside @Sendable
    }
    @MainActor static func __safeDI_fill_view() -> View { View() }
#if SHARED_NONISOLATED
    nonisolated static func __safeDI_form_Detail() -> DetailCarrier { DetailCarrier(view: { Self.__safeDI_fill_view() }) }
#else
    @MainActor static func __safeDI_form_Detail() -> DetailCarrier { DetailCarrier(view: { Self.__safeDI_fill_view() }) }
#endif
}
