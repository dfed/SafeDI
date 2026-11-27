import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(aBuilder: SendableInstantiator<Alpha>, other: Other) { self.aBuilder = aBuilder; self.other = other }
    @Instantiated let aBuilder: SendableInstantiator<Alpha>
    @Instantiated let other: Other
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Alpha: Instantiable, Sendable {
    public init(bBuilder: SendableInstantiator<Beta>) { self.bBuilder = bBuilder }
    @Instantiated let bBuilder: SendableInstantiator<Beta>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Beta: Instantiable, Sendable {
    public init(aBuilder: SendableInstantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: SendableInstantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Other: Instantiable {
    public init(aBuilder: Instantiator<Leaf>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Leaf>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Leaf: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
