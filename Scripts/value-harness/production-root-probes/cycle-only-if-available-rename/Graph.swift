import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(token: Token, aBuilder: Instantiator<Gate>) { self.token = token; self.aBuilder = aBuilder }
    @Instantiated let token: Token
    @Instantiated let aBuilder: Instantiator<Gate>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Token: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Gate: Instantiable {
    public init(maybeToken: Token?, bBuilder: Instantiator<Door>) { self.maybeToken = maybeToken; self.bBuilder = bBuilder }
    @Received(fulfilledByDependencyNamed: "token", ofType: Token.self, onlyIfAvailable: true) let maybeToken: Token?
    @Instantiated let bBuilder: Instantiator<Door>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Door: Instantiable {
    public init(maybeToken: Token?, token: Token, aBuilder: Instantiator<Gate>) { self.maybeToken = maybeToken; self.token = token; self.aBuilder = aBuilder }
    @Received(onlyIfAvailable: true) let maybeToken: Token?
    @Instantiated let token: Token
    @Instantiated let aBuilder: Instantiator<Gate>
    let differentialValueCreationStamp = ProbeStamp.next()
}
