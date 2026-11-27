@Instantiable(generateMock: true)
public final class Host: Instantiable {
    public init(node: Node, peer: Peer) { self.node = node; self.peer = peer }
    @Instantiated let node: Node
    @Received let peer: Peer
}
@Instantiable
public actor Node: Instantiable {
    public init(loopBuilder: Instantiator<Loop>) { self.loopBuilder = loopBuilder }
    @Instantiated let loopBuilder: Instantiator<Loop>
}
@Instantiable
public final class Loop: Instantiable {
    public init(node: Node) { self.node = node }
    @Instantiated let node: Node
}
@Instantiable
public final class Peer: Instantiable {
    public init(node: Other) { self.node = node }
    @Received let node: Other
}
@Instantiable
public final class Other: Instantiable { public init() {} }
