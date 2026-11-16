import SafeDI

public protocol Api: AnyObject {}

@Instantiable
public final class Logger: Instantiable { public init() {} }

@Instantiable
public final class Detail: Instantiable {
    public init(logger: Logger, api: any Api) { self.logger = logger; self.api = api }
    @Received public let logger: Logger
    @Instantiated public let api: any Api
}

@Instantiable(generateDependencyTree: true)
public final class Inner: Instantiable {
    public init(detail: Detail) { self.detail = detail }
    @Instantiated public let detail: Detail
}

@Instantiable(generateDependencyTree: true)
public final class Outer: Instantiable {
    public init(logger: Logger, inner: Inner) { self.logger = logger; self.inner = inner }
    @Instantiated public let logger: Logger
    @Instantiated public let inner: Inner
}
