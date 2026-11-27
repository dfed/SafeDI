import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(tag: Tag, homeBuilder: Instantiator<Home>) { self.tag = tag; self.homeBuilder = homeBuilder }
    @Instantiated let tag: Tag
    @Instantiated let homeBuilder: Instantiator<Home>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Tag: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Home: Instantiable {
    public init(reader: Reader, profileBuilder: Instantiator<Profile>) { self.reader = reader; self.profileBuilder = profileBuilder }
    @Instantiated let reader: Reader
    @Instantiated let profileBuilder: Instantiator<Profile>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Reader: Instantiable {
    public init(tag: Tag) { self.tag = tag }
    @Received let tag: Tag
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Profile: Instantiable {
    public init(tag: Tag, homeBuilder: Instantiator<Home>) { self.tag = tag; self.homeBuilder = homeBuilder }
    @Instantiated let tag: Tag
    @Instantiated let homeBuilder: Instantiator<Home>
    let differentialValueCreationStamp = ProbeStamp.next()
}
