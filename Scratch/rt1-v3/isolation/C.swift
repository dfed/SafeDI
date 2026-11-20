import Feature
final class Leaf: H { let v: Int; init(v: Int) { self.v = v } }
final class Root: Fills { override func hOfL1(id: Int, m: M) -> any H { Leaf(v: id) } }
@MainActor struct AppRoot { func make() -> Int { useFills(Root()) } }   // isolated root, nonisolated fill types
