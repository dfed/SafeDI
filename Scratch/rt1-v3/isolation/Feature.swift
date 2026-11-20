public final class M { public let x = 1; public init() {} }
public protocol H { var v: Int { get } }
open class Fills { public init() {}
    open func hOfL1(id: Int, m: M) -> any H { fatalError() } }
public func useFills(_ f: Fills) -> Int { f.hOfL1(id: 1, m: M()).v }
