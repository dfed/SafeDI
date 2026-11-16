import SafeDI
import Feature
@Instantiable(fulfillingAdditionalTypes: [Service.self])
public final class Impl: Instantiable, Service {
    public init(tag: Tag?) { self.tag = tag }
    @Received(onlyIfAvailable: true) public let tag: Tag?
}
@Instantiable(isRoot: true)
public final class Root: Instantiable {
    public init(tag: LazilyInstantiated<Tag>, seam: Seam) { self.tag = tag; self.seam = seam }
    @Instantiated public let tag: LazilyInstantiated<Tag>
    @Instantiated public let seam: Seam
}
public func probeResult() -> String {
    let root = Root()
    let impl = root.seam.service as! Impl
    return "impl.tag is root's: \(impl.tag.map { $0 === root.tag.instance } ?? false) (nil: \(impl.tag == nil))"
}
