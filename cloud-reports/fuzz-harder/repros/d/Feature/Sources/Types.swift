import SafeDI

public protocol Api: AnyObject {}

@Instantiable
public final class Logger: Instantiable { public init() {} }

@Instantiable
public final class Tag: Instantiable { public init() {} }

@Instantiable
public final class Detail: Instantiable {
    public init(logger: Logger, tag: Tag?, api: any Api) { self.logger = logger; self.tag = tag; self.api = api }
    @Received public let logger: Logger
    @Received(onlyIfAvailable: true) public let tag: Tag?
    @Instantiated public let api: any Api
}

@Instantiable(generateDependencyTree: true)
public final class Inner: Instantiable {
    public init(detailBuilder: Instantiator<Detail>) { self.detailBuilder = detailBuilder }
    @Instantiated public let detailBuilder: Instantiator<Detail>
}

@Instantiable(generateDependencyTree: true)
public final class Middle: Instantiable {
    public init(tag: Tag, inner: Inner) { self.tag = tag; self.inner = inner }
    @Instantiated public let tag: Tag
    @Instantiated public let inner: Inner
}

@Instantiable(generateDependencyTree: true)
public final class Outer: Instantiable {
    public init(logger: Logger, middle: Middle) { self.logger = logger; self.middle = middle }
    @Instantiated public let logger: Logger
    @Instantiated public let middle: Middle
}
