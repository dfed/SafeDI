import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(aBuilder: Instantiator<Alpha>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Alpha: Instantiable {
    public init(bBuilder: Instantiator<Beta>, model: Model) { self.bBuilder = bBuilder; self.model = model }
    @Instantiated let bBuilder: Instantiator<Beta>
    @Instantiated let model: Model
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Beta: Instantiable {
    public init(model: Model, aBuilder: Instantiator<Alpha>) { self.model = model; self.aBuilder = aBuilder }
    @Received let model: Model
    @Instantiated let aBuilder: Instantiator<Alpha>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Model: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
