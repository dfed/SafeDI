import SafeDI
import Feature

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class LiveApi: Instantiable, Api {
    public init(logger: Logger) { self.logger = logger }
    @Received public let logger: Logger
}

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(logger: Logger, outer: Outer) { self.logger = logger; self.outer = outer }
    @Instantiated public let logger: Logger
    @Instantiated public let outer: Outer
}

public func probeResult() -> Bool {
    let root = Root()
    let api = root.outer.inner.detail.api as! LiveApi
    return api.logger === root.outer.logger
}
