import QFeature
@MainActor protocol ViewLike {}
final class Leaf: H, ViewLike { let v: Int; init(v: Int) { self.v = v } }
nonisolated final class Root: Fills { let h1: (Int, M) -> any H; let e2: (Int, M) -> Fills
  init(h1: @escaping (Int, M) -> any H, e2: @escaping (Int, M) -> Fills) { self.h1 = h1; self.e2 = e2; super.init() }
  override func hOfL1(id: Int, m: M) -> any H { h1(id, m) }
  override func enterL2(id: Int, m: M) -> Fills { e2(id, m) } }
nonisolated final class Deep: Fills { let h2: (Int, M) -> any H
  init(h2: @escaping (Int, M) -> any H) { self.h2 = h2; super.init() }
  override func hOfL2(id: Int, m: M) -> any H { h2(id, m) } }
final class Carried { let id1: Int; init(id1: Int) { self.id1 = id1 } }
struct Root2: ViewLike { let host: Instantiator<L1>
  init() { host = makeSeamHost(Root(h1: { id, _ in Leaf(v: id) }, e2: { id, _ in let c = Carried(id1: id); return Deep(h2: { id, _ in Leaf(v: id &+ c.id1) }) })) }
}
