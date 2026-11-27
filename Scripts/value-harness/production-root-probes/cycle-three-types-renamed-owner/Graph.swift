import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(user: User, aBuilder: Instantiator<StepA>) { self.user = user; self.aBuilder = aBuilder }
    @Instantiated let user: User
    @Instantiated let aBuilder: Instantiator<StepA>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class User: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class StepA: Instantiable {
    public init(reader: OwnerReader, bBuilder: Instantiator<StepB>) { self.reader = reader; self.bBuilder = bBuilder }
    @Instantiated let reader: OwnerReader
    @Instantiated let bBuilder: Instantiator<StepB>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class OwnerReader: Instantiable {
    public init(owner: User?, user: User) { self.owner = owner; self.user = user }
    @Received(onlyIfAvailable: true) let owner: User?
    @Received let user: User
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class StepB: Instantiable {
    public init(owner: User, cBuilder: Instantiator<StepC>) { self.owner = owner; self.cBuilder = cBuilder }
    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let owner: User
    @Instantiated let cBuilder: Instantiator<StepC>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class StepC: Instantiable {
    public init(owner: User, user: User, aBuilder: Instantiator<StepA>) { self.owner = owner; self.user = user; self.aBuilder = aBuilder }
    @Received let owner: User
    @Instantiated let user: User
    @Instantiated let aBuilder: Instantiator<StepA>
    let differentialValueCreationStamp = ProbeStamp.next()
}
