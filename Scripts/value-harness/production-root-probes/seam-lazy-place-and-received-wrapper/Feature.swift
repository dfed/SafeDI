// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

public protocol Api: AnyObject {}
@Instantiable(generateDependencyTree: true)
public final class Gallery: Instantiable {
    public init(api: LazilyInstantiated<any Api>, store: LazilyInstantiated<Store>, gridBuilder: Instantiator<Grid>) { self.api = api; self.store = store; self.gridBuilder = gridBuilder }
    @Instantiated let api: LazilyInstantiated<any Api>
    @Received let store: LazilyInstantiated<Store>
    @Instantiated let gridBuilder: Instantiator<Grid>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Store: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Grid: Instantiable {
    public init(store: Store, api: any Api) { self.store = store; self.api = api }
    @Received let store: Store
    @Received let api: any Api
    let differentialValueCreationStamp = ProbeStamp.next()
}
