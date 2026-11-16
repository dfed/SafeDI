import SafeDI
public protocol Service: AnyObject {}
@Instantiable public final class Tag: Instantiable { public init() {} }
@Instantiable public final class Reader: Instantiable {
    public init(tag: LazilyInstantiated<Tag>?) { self.tag = tag }
    @Received(onlyIfAvailable: true) public let tag: LazilyInstantiated<Tag>?
}
@Instantiable(generateDependencyTree: true) public final class Seam: Instantiable {
    public init(reader: Reader, service: any Service) { self.reader = reader; self.service = service }
    @Instantiated public let reader: Reader
    @Instantiated public let service: any Service
}
