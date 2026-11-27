// module: FuzzApp, fills a hole
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(store: LazilyInstantiated<Store>, gallery: Gallery) { self.store = store; self.gallery = gallery }
    @Instantiated let store: LazilyInstantiated<Store>
    @Instantiated let gallery: Gallery
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(store: Store) { self.store = store }
    @Received let store: Store
    let differentialValueCreationStamp = ProbeStamp.next()
}
