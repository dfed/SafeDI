import SafeDI
import Feature

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class LiveApi: Instantiable, Api {
    public init(logger: Logger) { self.logger = logger }
    @Received public let logger: Logger
}

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(outer: Outer) { self.outer = outer }
    @Instantiated public let outer: Outer
}
