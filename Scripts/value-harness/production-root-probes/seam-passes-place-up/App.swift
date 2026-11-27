// module: FuzzApp, fills a hole
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(outer: Outer) { self.outer = outer }
    @Instantiated let outer: Outer
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(mark: Mark?) { self.mark = mark }
    @Received(onlyIfAvailable: true) let mark: Mark?
    let differentialValueCreationStamp = ProbeStamp.next()
}
