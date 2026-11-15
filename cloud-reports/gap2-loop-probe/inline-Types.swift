import SafeDI

public protocol Api { var sideBuilder: Instantiator<Side> { get } }

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(store: Store) { self.store = store }
    @Instantiated public let store: Store
}

@Instantiable
public final class Store: Instantiable {
    public init(aBuilder: Instantiator<A>, sideBuilder: Instantiator<Side>) { self.aBuilder = aBuilder; self.sideBuilder = sideBuilder }
    @Instantiated public let aBuilder: Instantiator<A>
    @Instantiated public let sideBuilder: Instantiator<Side>
}

@Instantiable
public final class A: Instantiable {
    public init(api: any Api) { self.api = api }
    @Instantiated(fulfilledByType: "LiveApi") public let api: any Api
}

@Instantiable
public final class LiveApi: Api, Instantiable {
    public init(sideBuilder: Instantiator<Side>) { self.sideBuilder = sideBuilder }
    @Received public let sideBuilder: Instantiator<Side>
}

@Instantiable
public final class Side: Instantiable {
    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
    @Received public let aBuilder: Instantiator<A>
}
