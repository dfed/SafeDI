import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable, Sendable {
    public init(source: Source, aBuilder: SendableInstantiator<Ping>) { self.source = source; self.aBuilder = aBuilder }
    @Instantiated let source: Source
    @Instantiated let aBuilder: SendableInstantiator<Ping>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Source: Instantiable, Sendable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Ping: Instantiable, Sendable {
    public init(source: Source, bBuilder: SendableInstantiator<Pong>) { self.source = source; self.bBuilder = bBuilder }
    @Received let source: Source
    @Instantiated let bBuilder: SendableInstantiator<Pong>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Pong: Instantiable, Sendable {
    public init(aBuilder: SendableInstantiator<Ping>, origin: Source) { self.aBuilder = aBuilder; self.origin = origin }
    @Instantiated let aBuilder: SendableInstantiator<Ping>
    @Received(fulfilledByDependencyNamed: "source", ofType: Source.self) let origin: Source
    let differentialValueCreationStamp = ProbeStamp.next()
}
