import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(session: Session, aBuilder: Instantiator<Alpha>) { self.session = session; self.aBuilder = aBuilder }
    @Instantiated let session: Session
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Session: Instantiable {
    public init() {}
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
    public init(session: Session?, aBuilder: Instantiator<Alpha>) { self.session = session; self.aBuilder = aBuilder }
    @Received(onlyIfAvailable: true) let session: Session?
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}
