// module: FuzzFeature
import SafeDI

public enum ProbeStamp {
    nonisolated(unsafe) private static var lastStamp = 0

    public static func next() -> Int {
        lastStamp += 1
        return lastStamp
    }
}

public protocol Api: AnyObject {}
@Instantiable(generateDependencyTree: true)
public final class Screen: Instantiable {
    public init(analytics: Analytics, profileBuilder: Instantiator<ProfileView>) { self.analytics = analytics; self.profileBuilder = profileBuilder }
    @Instantiated let analytics: Analytics
    @Instantiated let profileBuilder: Instantiator<ProfileView>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Analytics: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class ProfileView: Instantiable {
    public init(api: any Api, analytics: Analytics) { self.api = api; self.analytics = analytics }
    @Instantiated let api: any Api
    @Received let analytics: Analytics
    let differentialValueCreationStamp = ProbeStamp.next()
}
