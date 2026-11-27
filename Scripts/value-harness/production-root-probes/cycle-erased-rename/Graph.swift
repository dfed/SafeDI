import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(store: Store, listBuilder: Instantiator<ListScreen>) { self.store = store; self.listBuilder = listBuilder }
    @Instantiated let store: Store
    @Instantiated let listBuilder: Instantiator<ListScreen>
    let differentialValueCreationStamp = ProbeStamp.next()
}

public protocol Storing: AnyObject {}
public struct AnyStoring { public let base: any Storing; public init(_ base: any Storing) { self.base = base } }

@Instantiable
public final class Store: Instantiable, Storing {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class ListScreen: Instantiable {
    public init(storing: AnyStoring, detailBuilder: Instantiator<DetailScreen>) { self.storing = storing; self.detailBuilder = detailBuilder }
    @Received(fulfilledByDependencyNamed: "store", ofType: Store.self, erasedToConcreteExistential: true) let storing: AnyStoring
    @Instantiated let detailBuilder: Instantiator<DetailScreen>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class DetailScreen: Instantiable {
    public init(storing: AnyStoring, listBuilder: Instantiator<ListScreen>, store: Store) { self.storing = storing; self.listBuilder = listBuilder; self.store = store }
    @Received let storing: AnyStoring
    @Instantiated let listBuilder: Instantiator<ListScreen>
    @Instantiated let store: Store
    let differentialValueCreationStamp = ProbeStamp.next()
}
