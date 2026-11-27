import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(aBuilder: Instantiator<Alpha>, other: Other) { self.aBuilder = aBuilder; self.other = other }
    @Instantiated let aBuilder: Instantiator<Alpha>
    @Instantiated let other: Other
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Alpha: Instantiable {
    public init(bBuilder: Instantiator<Beta>) { self.bBuilder = bBuilder }
    @Instantiated let bBuilder: Instantiator<Beta>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Beta: Instantiable {
    public init(aBuilder: Instantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
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
