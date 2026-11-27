import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(session: Session, aBuilder: Instantiator<Alpha>) { self.session = session; self.aBuilder = aBuilder }
    @Instantiated let session: Session
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Session: Instantiable, Sendable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Alpha: Instantiable, Sendable {
    public init(bBuilder: SendableInstantiator<Beta>, tag: Tag) { self.bBuilder = bBuilder; self.tag = tag }
    @Instantiated let bBuilder: SendableInstantiator<Beta>
    @Instantiated let tag: Tag
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Tag: Instantiable, Sendable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Beta: Instantiable, Sendable {
    public init(tag: Tag, session: Session?, aBuilder: SendableInstantiator<Alpha>) { self.tag = tag; self.session = session; self.aBuilder = aBuilder }
    @Received let tag: Tag
    @Received(onlyIfAvailable: true) let session: Session?
    @Instantiated let aBuilder: SendableInstantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}
