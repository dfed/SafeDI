import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(left: LeftHub, right: RightHub) { self.left = left; self.right = right }
    @Instantiated let left: LeftHub
    @Instantiated let right: RightHub
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class LeftHub: Instantiable {
    public init(aBuilder: Instantiator<LeftA>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<LeftA>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class LeftA: Instantiable {
    public init(bBuilder: Instantiator<LeftB>) { self.bBuilder = bBuilder }
    @Instantiated let bBuilder: Instantiator<LeftB>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class LeftB: Instantiable {
    public init(aBuilder: Instantiator<LeftA>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<LeftA>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class RightHub: Instantiable {
    public init(aBuilder: Instantiator<RightA>) { self.aBuilder = aBuilder }
    @Instantiated let aBuilder: Instantiator<RightA>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class RightA: Instantiable {
    public init(bBuilder: Instantiator<RightB>, mark: Mark) { self.bBuilder = bBuilder; self.mark = mark }
    @Instantiated let bBuilder: Instantiator<RightB>
    @Instantiated let mark: Mark
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class RightB: Instantiable {
    public init(aBuilder: Instantiator<RightA>, mark: Mark) { self.aBuilder = aBuilder; self.mark = mark }
    @Instantiated let aBuilder: Instantiator<RightA>
    @Received let mark: Mark
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Mark: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
