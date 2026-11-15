// Gap 2's loop: a builder loop between a call of a seam (`aBuilder`, seam `A` with the hole `api`) and a sibling
// (`sideBuilder`) that the call's own fill reads, while `Side` receives `aBuilder`.
// INLINE: SafeDITool's own output for the shape with no seam. SEAM: the per-type form, in which the function that
// builds the hole's builder struct is a local function, so the fill reaches `__safeDI_sideBuilder` by name.
final class Counter: @unchecked Sendable {
    static let shared = Counter()
    var log: [String] = []
    var live: [String: Int] = [:]
    func made(_ name: String) { log.append(name); live[name, default: 0] += 1 }
    func freed(_ name: String) { live[name, default: 0] -= 1 }
    var summary: String { live.keys.sorted().map { "\($0) \(live[$0] ?? 0)" }.joined(separator: ", ") }
}

public struct Instantiator<T> {
    public init(_ builder: @escaping () -> T) { self.builder = builder }
    public func instantiate() -> T { builder() }
    private let builder: () -> T
}

public protocol Api: AnyObject { var sideBuilder: Instantiator<Side> { get } }

public final class Root {
    public init(store: Store) { self.store = store; Counter.shared.made("Root") }
    deinit { Counter.shared.freed("Root") }
    public let store: Store
}

public final class Store {
    public init(aBuilder: Instantiator<A>, sideBuilder: Instantiator<Side>) { self.aBuilder = aBuilder; self.sideBuilder = sideBuilder; Counter.shared.made("Store") }
    deinit { Counter.shared.freed("Store") }
    public let aBuilder: Instantiator<A>
    public let sideBuilder: Instantiator<Side>
}

public final class A {
    public init(api: any Api) { self.api = api; Counter.shared.made("A") }
    deinit { Counter.shared.freed("A") }
    public let api: any Api
}

public final class LiveApi: Api {
    public init(sideBuilder: Instantiator<Side>) { self.sideBuilder = sideBuilder; Counter.shared.made("LiveApi") }
    deinit { Counter.shared.freed("LiveApi") }
    public let sideBuilder: Instantiator<Side>
}

public final class Side {
    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder; Counter.shared.made("Side") }
    deinit { Counter.shared.freed("Side") }
    public let aBuilder: Instantiator<A>
}

#if SEAM
// What the seam's module (Feature) generates for `A`, in the builder-struct form the leak fix gives it.
extension A {
    public enum SafeDIScope_Api {
        public struct api_Values { public init() {} }
        public struct __safeDI_Builder<Built> {
            public init(api: @escaping (api_Values) -> Built) { self.api = api }
            public let api: (api_Values) -> Built
        }
    }
    public convenience init(__safeDI_apiBuilder: SafeDIScope_Api.__safeDI_Builder<any Api>) {
        let api: any Api = __safeDI_apiBuilder.api(.init())
        self.init(api: api)
    }
}

// What the calling module (App) generates.
extension Root {
    public convenience init() {
        func __safeDI_store() -> Store {
            // The per-type form: the hole's builder struct comes from a local function, which names the sibling's
            // function, declared below it. Nothing is captured before it is declared, and nothing holds a box.
            func __safeDI_apiBuilder_A() -> A.SafeDIScope_Api.__safeDI_Builder<any Api> {
                .init(api: { _ in
                    let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
                    return LiveApi(sideBuilder: sideBuilder)
                })
            }
            func __safeDI_aBuilder() -> A {
                A(__safeDI_apiBuilder: __safeDI_apiBuilder_A())
            }
            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
            func __safeDI_sideBuilder() -> Side {
                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
                return Side(aBuilder: aBuilder)
            }
            let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
            return Store(aBuilder: aBuilder, sideBuilder: sideBuilder)
        }
        let store: Store = __safeDI_store()
        self.init(store: store)
    }
}
#else
// SafeDITool's output for the shape with `A` inline (no seam), copied.
extension Root {
    public convenience init() {
        func __safeDI_store() -> Store {
            func __safeDI_aBuilder() -> A {
                let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
                let api: any Api = LiveApi(sideBuilder: sideBuilder)
                return A(api: api)
            }
            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
            func __safeDI_sideBuilder() -> Side {
                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
                return Side(aBuilder: aBuilder)
            }
            let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
            return Store(aBuilder: aBuilder, sideBuilder: sideBuilder)
        }
        let store: Store = __safeDI_store()
        self.init(store: store)
    }
}
#endif

func step(_ title: String) { print("\(title): \(Counter.shared.summary)") }

// Run 1: walk the loop four levels deep, then release from the top down and from the bottom up.
func run(holdDeepestOnly: Bool, viaSideFirst: Bool) {
    Counter.shared.log = []
    var root: Root? = Root()
    var a1: A? = viaSideFirst ? root!.store.sideBuilder.instantiate().aBuilder.instantiate() : root!.store.aBuilder.instantiate()
    var side1: Side? = a1!.api.sideBuilder.instantiate()
    var a2: A? = side1!.aBuilder.instantiate()
    var side2: Side? = a2!.api.sideBuilder.instantiate()
    var a3: A? = side2!.aBuilder.instantiate()
    print("created: \(Counter.shared.log.joined(separator: " "))")
    step("all held")
    if holdDeepestOnly {
        root = nil; a1 = nil; side1 = nil; a2 = nil; side2 = nil
        step("only the deepest A held")
        let side3 = a3!.api.sideBuilder.instantiate()
        let a4 = side3.aBuilder.instantiate()
        _ = a4
        step("deepest A builds on after the root is gone")
    } else {
        a3 = nil; side2 = nil; a2 = nil; side1 = nil; a1 = nil
        step("only the root held")
    }
    root = nil; a1 = nil; side1 = nil; a2 = nil; side2 = nil; a3 = nil
    step("nothing held")
}

for holdDeepestOnly in [false, true] {
    for viaSideFirst in [false, true] {
        print("-- hold deepest only \(holdDeepestOnly), via side first \(viaSideFirst)")
        run(holdDeepestOnly: holdDeepestOnly, viaSideFirst: viaSideFirst)
    }
}
