import Feature
@MainActor protocol ViewLike {}
final class Leaf: H, ViewLike { let v: Int; init(v: Int) { self.v = v } }   // MainActor by conformance, like a View
final class Root: Fills { override func hOfL1(id: Int, m: M) -> any H { Leaf(v: id) } }
