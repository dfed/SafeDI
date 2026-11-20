import PFeature
@MainActor protocol ViewLike {}
final class Leaf: H, ViewLike { let v: Int; init(v: Int) { self.v = v } }   // MainActor by conformance, like a View
struct Root { let host: Instantiator<L1>    // root MainActor by conformance, like an App
  init() { host = makeSeamHost(__safeDI_Host_Fills(hOfL1: { id, _ in Leaf(v: id) }, hOfL2: { id, _ in Leaf(v: id) })) } }
