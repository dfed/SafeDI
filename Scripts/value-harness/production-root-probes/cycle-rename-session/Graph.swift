import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(session: Session, homeBuilder: Instantiator<Home>) { self.session = session; self.homeBuilder = homeBuilder }
    @Instantiated let session: Session
    @Instantiated let homeBuilder: Instantiator<Home>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Session: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Home: Instantiable {
    public init(currentSession: Session, profileBuilder: Instantiator<Profile>) { self.currentSession = currentSession; self.profileBuilder = profileBuilder }
    @Received(fulfilledByDependencyNamed: "session", ofType: Session.self) let currentSession: Session
    @Instantiated let profileBuilder: Instantiator<Profile>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Profile: Instantiable {
    public init(currentSession: Session, session: Session, homeBuilder: Instantiator<Home>) { self.currentSession = currentSession; self.session = session; self.homeBuilder = homeBuilder }
    @Received let currentSession: Session
    @Received let session: Session
    @Instantiated let homeBuilder: Instantiator<Home>
    let differentialValueCreationStamp = ProbeStamp.next()
}
