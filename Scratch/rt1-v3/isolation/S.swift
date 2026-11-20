import QFeature
@MainActor protocol ViewLike {}
final class Leaf: H, ViewLike { let v: Int; init(v: Int) { self.v = v } }
nonisolated final class Root: Fills { let h1: (Int, M) -> any H; let e2: (Int, M) -> Fills
  init(h1: @escaping (Int, M) -> any H, e2: @escaping (Int, M) -> Fills) { self.h1 = h1; self.e2 = e2; super.init() }
  override func hOfL1(id: Int, m: M) -> any H { h1(id, m) }
  override func enterL2(id: Int, m: M) -> Fills { e2(id, m) } }
nonisolated final class Deep: Fills { let id1: Int; let h2: (Int, M, Int) -> any H
  init(id1: Int, h2: @escaping (Int, M, Int) -> any H) { self.id1 = id1; self.h2 = h2; super.init() }
  override func hOfL2(id: Int, m: M) -> any H { h2(id, m, id1) } }
struct AppRoot: ViewLike { let host: Instantiator<L1>
  init() { host = makeSeamHost(Root(h1: { id, m in AppRoot.__safeDI_fill_hOfL1(id: id, m: m) }, e2: { id, _ in Deep(id1: id, h2: { id, m, id1 in AppRoot.__safeDI_fill_hOfL2(id: id, m: m, id1: id1) }) })) } }
extension AppRoot {
  static func __safeDI_fill_hOfL1(id: Int, m: M) -> any H { Leaf(v: id) }
  static func __safeDI_fill_hOfL2(id: Int, m: M, id1: Int) -> any H { Leaf(v: id &+ id1) } }
