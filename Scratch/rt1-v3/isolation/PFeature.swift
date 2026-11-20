public final class Instantiator<T> { let b: (Int) -> T; public init(_ b: @escaping (Int) -> T) { self.b = b }; public func instantiate(_ id: Int) -> T { b(id) } }
public final class M { public let x = 1; public init() {} }
public protocol H { var v: Int { get } }
public final class L1 { public let h: any H; public let next: Instantiator<L2>; init(h: any H, next: Instantiator<L2>) { self.h = h; self.next = next } }
public final class L2 { public let h: any H; init(h: any H) { self.h = h } }
public final class __safeDI_Host_Fills {
    let hOfL1: ((_ id: Int, _ m: M) -> any H)?; let hOfL2: ((_ id: Int, _ m: M) -> any H)?; let enterL2: ((_ id: Int, _ m: M) -> __safeDI_Host_Fills)?
    public init(hOfL1: ((_ id: Int, _ m: M) -> any H)? = nil, hOfL2: ((_ id: Int, _ m: M) -> any H)? = nil, enterL2: ((_ id: Int, _ m: M) -> __safeDI_Host_Fills)? = nil) { self.hOfL1 = hOfL1; self.hOfL2 = hOfL2; self.enterL2 = enterL2 } }
func buildL2(_ id: Int, _ c: __safeDI_Host_Fills) -> L2 { L2(h: c.hOfL2!(id, M())) }
func buildL1(_ id: Int, _ c: __safeDI_Host_Fills) -> L1 { let m = M(); let h = c.hOfL1!(id, m); let n = c.enterL2?(id, m) ?? c; return L1(h: h, next: Instantiator { buildL2($0, n) }) }
public func makeSeamHost(_ c: __safeDI_Host_Fills) -> Instantiator<L1> { Instantiator { buildL1($0, c) } }
