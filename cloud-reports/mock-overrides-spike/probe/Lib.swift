import SafeDI

@Instantiable public final class Service: Instantiable {
    public init() {}
}

@Instantiable public final class Leaf2: Instantiable {
    public init(name: String = "leaf2") { self.name = name }
    public let name: String
}

@Instantiable public final class Leaf: Instantiable {
    public init(service: Service, count: Int = 3) { self.service = service; self.count = count }
    @Received public let service: Service
    public let count: Int
}

@Instantiable public final class Pane: Instantiable {
    init(leaf2: Leaf2) { self.leaf2 = leaf2 }
    @Instantiated public let leaf2: Leaf2
}

/// A public mock whose `SafeDIOverrides` nests configurations, one of which nests another.
@Instantiable(generateMock: .public) public final class Feature: Instantiable {
    public init(service: Service, leaf: Leaf, pane: Pane) { self.service = service; self.leaf = leaf; self.pane = pane }
    @Received public let service: Service
    @Instantiated public let leaf: Leaf
    @Instantiated public let pane: Pane
}

/// An internal mock whose configurations nest.
@Instantiable(generateMock: true) public final class Holder: Instantiable {
    public init(service: Service, pane: Pane, leafBuilder: Instantiator<Leaf>) { self.service = service; self.pane = pane; self.leafBuilder = leafBuilder }
    @Instantiated public let service: Service
    @Instantiated public let pane: Pane
    @Instantiated public let leafBuilder: Instantiator<Leaf>
}

/// An internal mock with no nested configuration: its output must not change.
@Instantiable(generateMock: true) public final class Flat: Instantiable {
    public init(service: Service, leaf2: Leaf2) { self.service = service; self.leaf2 = leaf2 }
    @Instantiated public let service: Service
    @Instantiated public let leaf2: Leaf2
}
