// Seam module, v4 form. Home -> Screen (let child: Home binds nothing visible) ; Screen -> Detail (entry: Screen binds id, model)
// Screen -> Screen (cycle edge with entry taking the carrier) ; Home -> Work under a @Sendable builder, Work -> Detail plain (per entry).
nonisolated public protocol Api { func v() -> Int }
nonisolated public final class Instantiator<T> { let b: (Int) -> T; public init(_ b: @escaping (Int) -> T) { self.b = b }; public func instantiate(_ id: Int) -> T { b(id) } }
nonisolated public final class SendableInstantiator<T>: Sendable { let b: @Sendable (Int) -> T; public init(_ b: @escaping @Sendable (Int) -> T) { self.b = b }; public func instantiate(_ id: Int) -> T { b(id) } }
nonisolated public final class Model { public let n: Int; public init(n: Int) { self.n = n } }
nonisolated public final class Service { public init() {} }
nonisolated public final class Detail { public let api: any Api; public let service: Service; init(api: any Api, service: Service) { self.api = api; self.service = service } }
nonisolated public final class Screen {
    public let api: any Api; public let detail: Instantiator<Detail>; public let next: Instantiator<Screen>
    init(api: any Api, detail: Instantiator<Detail>, next: Instantiator<Screen>) { self.api = api; self.detail = detail; self.next = next }
}
nonisolated public final class Work { public let api: any Api; public let detail: Instantiator<Detail>; init(api: any Api, detail: Instantiator<Detail>) { self.api = api; self.detail = detail } }
public final class Home {
    public let screen: Instantiator<Screen>
    public let work: SendableInstantiator<Work>
    public init(__safeDI_home carrier: __safeDI_HomeCarrier, __safeDI_homeSendable sendableCarrier: __safeDI_HomeSendableCarrier) {
        let service = Service()
        let context = __safeDI_HomeContext(screen: carrier.screen, service: service)
        screen = Instantiator { id in Home.__safeDI_screen(id: id, context.screen, service: context.service) }
        let work = sendableCarrier.work
        self.work = SendableInstantiator { id in Home.__safeDI_work(id: id, work) }
    }
}
extension Home {
    nonisolated public final class __safeDI_DetailCarrier {
        public let apiOfDetail: (_ id: Int) -> any Api
        public init(apiOfDetail: @escaping (_ id: Int) -> any Api) { self.apiOfDetail = apiOfDetail }
    }
    nonisolated public final class __safeDI_ScreenCarrier {
        public let apiOfScreen: (_ id: Int) -> any Api
        public let enterDetailOfScreen: (_ id: Int, _ model: Model) -> __safeDI_DetailCarrier
        public let enterNextOfScreen: (_ carrier: __safeDI_ScreenCarrier, _ id: Int, _ model: Model) -> __safeDI_ScreenCarrier
        public init(apiOfScreen: @escaping (_ id: Int) -> any Api, enterDetailOfScreen: @escaping (_ id: Int, _ model: Model) -> __safeDI_DetailCarrier, enterNextOfScreen: @escaping (_ carrier: __safeDI_ScreenCarrier, _ id: Int, _ model: Model) -> __safeDI_ScreenCarrier) {
            self.apiOfScreen = apiOfScreen; self.enterDetailOfScreen = enterDetailOfScreen; self.enterNextOfScreen = enterNextOfScreen
        }
    }
    nonisolated public final class __safeDI_HomeCarrier {
        public let screen: __safeDI_ScreenCarrier
        public init(screen: __safeDI_ScreenCarrier) { self.screen = screen }
    }
    nonisolated public final class __safeDI_WorkSendableCarrier: Sendable {
        public let apiOfWork: @Sendable (_ id: Int) -> any Api
        public let enterDetailOfWork: @Sendable (_ id: Int) -> __safeDI_DetailCarrier
        public init(apiOfWork: @escaping @Sendable (_ id: Int) -> any Api, enterDetailOfWork: @escaping @Sendable (_ id: Int) -> __safeDI_DetailCarrier) { self.apiOfWork = apiOfWork; self.enterDetailOfWork = enterDetailOfWork }
    }
    nonisolated public final class __safeDI_HomeSendableCarrier: Sendable {
        public let work: __safeDI_WorkSendableCarrier
        public init(work: __safeDI_WorkSendableCarrier) { self.work = work }
    }
    nonisolated final class __safeDI_HomeContext { let screen: __safeDI_ScreenCarrier; let service: Service; init(screen: __safeDI_ScreenCarrier, service: Service) { self.screen = screen; self.service = service } }
    nonisolated final class __safeDI_ScreenContext { let detail: __safeDI_DetailCarrier; let next: __safeDI_ScreenCarrier; let service: Service
        init(detail: __safeDI_DetailCarrier, next: __safeDI_ScreenCarrier, service: Service) { self.detail = detail; self.next = next; self.service = service } }
    nonisolated static func __safeDI_screen(id: Int, _ carrier: __safeDI_ScreenCarrier, service: Service) -> Screen {
        let model = Model(n: id)
        let context = __safeDI_ScreenContext(detail: carrier.enterDetailOfScreen(id, model), next: carrier.enterNextOfScreen(carrier, id, model), service: service)
        return Screen(api: carrier.apiOfScreen(id),
                      detail: Instantiator { id in Detail(api: context.detail.apiOfDetail(id), service: context.service) },
                      next: Instantiator { id in Home.__safeDI_screen(id: id, context.next, service: context.service) })
    }
    nonisolated static func __safeDI_work(id: Int, _ carrier: __safeDI_WorkSendableCarrier) -> Work {
        let detail = carrier.enterDetailOfWork(id)
        return Work(api: carrier.apiOfWork(id), detail: Instantiator { id in Detail(api: detail.apiOfDetail(id), service: Service()) })
    }
}
