// module: FuzzApp, fills a hole
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(screen: Screen) { self.screen = screen }
    @Instantiated let screen: Screen
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(analytics: Analytics) { self.analytics = analytics }
    @Received let analytics: Analytics
    let differentialValueCreationStamp = ProbeStamp.next()
}
