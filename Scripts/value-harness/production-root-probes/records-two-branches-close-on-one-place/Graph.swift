import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(aBuilder: Instantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Alpha: Instantiable {
    public init(bBuilder: Instantiator<Beta>, cBuilder: Instantiator<Gamma>) { self.bBuilder = bBuilder; self.cBuilder = cBuilder }
    @Instantiated let bBuilder: Instantiator<Beta>
    @Instantiated let cBuilder: Instantiator<Gamma>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Beta: Instantiable {
    public init(cBuilder: Instantiator<Gamma>) { self.cBuilder = cBuilder }
    @Instantiated let cBuilder: Instantiator<Gamma>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Gamma: Instantiable {
    public init(aBuilder: Instantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}
