import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(manager: Manager, aBuilder: Instantiator<Shelf>) { self.manager = manager; self.aBuilder = aBuilder }
    @Instantiated let manager: Manager
    @Instantiated let aBuilder: Instantiator<Shelf>
    let differentialValueCreationStamp = ProbeStamp.next()
}

public protocol Vending: AnyObject {}

@Instantiable
public final class Manager: Instantiable, Vending {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Shelf: Instantiable {
    public init(vendor: any Vending, bBuilder: Instantiator<Bin>) { self.vendor = vendor; self.bBuilder = bBuilder }
    @Received(fulfilledByDependencyNamed: "manager", ofType: Manager.self) let vendor: any Vending
    @Instantiated let bBuilder: Instantiator<Bin>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Bin: Instantiable {
    public init(vendor: any Vending, manager: Manager, aBuilder: Instantiator<Shelf>) { self.vendor = vendor; self.manager = manager; self.aBuilder = aBuilder }
    @Received let vendor: any Vending
    @Received let manager: Manager
    @Instantiated let aBuilder: Instantiator<Shelf>
    let differentialValueCreationStamp = ProbeStamp.next()
}
