import PFeature
@MainActor protocol ViewLike {}
final class Leaf: H, ViewLike { let v: Int; init(v: Int) { self.v = v } }
struct Root: ViewLike { let host: Instantiator<L1>
  init() { host = makeSeamHost(__safeDI_Host_Fills(hOfL1: { id, _ in Leaf(v: id) }, hOfL2: { id, _ in Leaf(v: id) })) }
  func leak() { let h = host; Task.detached { _ = h.instantiate(1) } } }
