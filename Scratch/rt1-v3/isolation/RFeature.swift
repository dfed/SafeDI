public final class Instantiator<T> { let b: (Int) -> T; public init(_ b: @escaping (Int) -> T) { self.b = b }; public func instantiate(_ id: Int) -> T { b(id) } }
public final class M { public let x = 1; public init() {} }
public protocol H { var v: Int { get } }
public final class L1 { public let h: any H; public let next: Instantiator<L2>; init(h: any H, next: Instantiator<L2>) { self.h = h; self.next = next } }
public final class L2 { public let h: any H; init(h: any H) { self.h = h } }
nonisolated open class Fills { public init() {}
    open func hOfL1(id: Int, m: M) -> any H { fatalError() }
    open func enterL2(id: Int, m: M) -> Fills { fatalError() }
    open func hOfL2(id: Int, m: M) -> any H { fatalError() } }
func buildL2(_ id: Int, _ f: Fills) -> L2 { L2(h: f.hOfL2(id: id, m: M())) }
func buildL1(_ id: Int, _ f: Fills) -> L1 { let m = M(); let h = f.hOfL1(id: id, m: m); let g = f.enterL2(id: id, m: m); return L1(h: h, next: Instantiator { buildL2($0, g) }) }
public func makeSeamHost(_ f: Fills) -> Instantiator<L1> { Instantiator { buildL1($0, f) } }
