import SafeDI
import Feature

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class LiveApi: Instantiable, Api {
    public init(logger: Logger, tag: Tag?) { self.logger = logger; self.tag = tag }
    @Received public let logger: Logger
    @Received(onlyIfAvailable: true) public let tag: Tag?
}

@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(logger: Logger, tag: Tag, outer: Outer) { self.logger = logger; self.tag = tag; self.outer = outer }
    @Instantiated public let logger: Logger
    @Instantiated public let tag: Tag
    @Instantiated public let outer: Outer
}

public func probeResult() -> String {
    let root = Root()
    let detail = root.outer.middle.inner.detailBuilder.instantiate()
    let api = detail.api as! LiveApi
    return "logger is Outer's: \(api.logger === root.outer.logger); tag is Middle's: \(api.tag === root.outer.middle.tag); detail.tag is Middle's: \(detail.tag === root.outer.middle.tag)"
}
