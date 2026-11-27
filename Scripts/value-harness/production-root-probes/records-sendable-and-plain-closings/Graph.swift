import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(aBuilder: Instantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Alpha: Instantiable {
    public init(bBuilder: SendableInstantiator<Beta>, cBuilder: Instantiator<Gamma>) { self.bBuilder = bBuilder; self.cBuilder = cBuilder }
    @Instantiated let bBuilder: SendableInstantiator<Beta>
    @Instantiated let cBuilder: Instantiator<Gamma>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Beta: Instantiable, Sendable {
    public init(token: Token) { self.token = token }
    @Instantiated let token: Token
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Token: Instantiable, Sendable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Gamma: Instantiable {
    public init(aBuilder: Instantiator<Alpha>, bBuilder: SendableInstantiator<Beta>) { self.aBuilder = aBuilder; self.bBuilder = bBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
    @Instantiated let bBuilder: SendableInstantiator<Beta>
    let differentialValueCreationStamp = ProbeStamp.next()
}
