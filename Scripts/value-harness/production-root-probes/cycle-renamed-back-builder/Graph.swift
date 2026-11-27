import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(homeBuilder: Instantiator<Home>) { self.homeBuilder = homeBuilder }
    @Instantiated let homeBuilder: Instantiator<Home>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Home: Instantiable {
    public init(profileBuilder: Instantiator<Profile>, badge: Badge) { self.profileBuilder = profileBuilder; self.badge = badge }
    @Instantiated let profileBuilder: Instantiator<Profile>
    @Instantiated let badge: Badge
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Badge: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Profile: Instantiable {
    public init(backBuilder: Instantiator<Home>, badge: Badge) { self.backBuilder = backBuilder; self.badge = badge }
    @Received(fulfilledByDependencyNamed: "homeBuilder", ofType: Instantiator<Home>.self) let backBuilder: Instantiator<Home>
    @Received let badge: Badge
    let differentialValueCreationStamp = ProbeStamp.next()
}
