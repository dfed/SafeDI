import PFeature
final class Leaf: H { let v: Int; init(v: Int) { self.v = v } }   // MainActor under default isolation
final class Carried { let id1: Int; init(id1: Int) { self.id1 = id1 } }
struct Root { let host: Instantiator<L1>
  init() { host = makeSeamHost(__safeDI_Host_Fills(hOfL1: { id, _ in Leaf(v: id) }, enterL2: { id, _ in let c = Carried(id1: id); return __safeDI_Host_Fills(hOfL2: { id, _ in Leaf(v: id &+ c.id1) }) })) } }
