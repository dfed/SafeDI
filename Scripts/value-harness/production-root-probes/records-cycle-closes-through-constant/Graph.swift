import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(aBuilder: Instantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Alpha: Instantiable {
    public init(b: Beta) { self.b = b }
    @Instantiated let b: Beta
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Beta: Instantiable {
    public init(aBuilder: Instantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}
