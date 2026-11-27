import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(profile: Profile, screen: ProfileScreen) { self.profile = profile; self.screen = screen }
    @Instantiated let profile: Profile
    @Instantiated let screen: ProfileScreen
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Profile: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class ProfileScreen: Instantiable {
    public init(optionalProfile: Profile?, cell: ProfileCell) { self.optionalProfile = optionalProfile; self.cell = cell }
    @Received(fulfilledByDependencyNamed: "profile", ofType: Profile?.self, onlyIfAvailable: true) let optionalProfile: Profile?
    @Instantiated let cell: ProfileCell
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class ProfileCell: Instantiable {
    public init(optionalProfile: Profile?, profile: Profile?) { self.optionalProfile = optionalProfile; self.profile = profile }
    @Received(onlyIfAvailable: true) let optionalProfile: Profile?
    @Received(onlyIfAvailable: true) let profile: Profile?
    let differentialValueCreationStamp = ProbeStamp.next()
}
