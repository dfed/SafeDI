import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable, Sendable {
    public init(session: Session, aBuilder: SendableInstantiator<Alpha>) { self.session = session; self.aBuilder = aBuilder }
    @Instantiated let session: Session
    @Instantiated let aBuilder: SendableInstantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Session: Instantiable, Sendable {
    public init() {}
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
    public init(session: Session, aBuilder: SendableInstantiator<Alpha>) { self.session = session; self.aBuilder = aBuilder }
    @Received let session: Session
    @Instantiated let aBuilder: SendableInstantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}
