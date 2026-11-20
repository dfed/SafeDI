import Feature
final class Leaf: H { let v: Int; init(v: Int) { self.v = v } }   // MainActor under default isolation
nonisolated final class Root: Fills { override func hOfL1(id: Int, m: M) -> any H { Leaf(v: id) } }
func make() -> Int { useFills(Root()) }
