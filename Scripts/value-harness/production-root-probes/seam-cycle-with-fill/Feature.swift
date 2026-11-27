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
public final class Browser: Instantiable {
    public init(tag: Tag, pageBuilder: Instantiator<Page>) { self.tag = tag; self.pageBuilder = pageBuilder }
    @Instantiated let tag: Tag
    @Instantiated let pageBuilder: Instantiator<Page>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Tag: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Page: Instantiable {
    public init(api: any Api, linkBuilder: Instantiator<Link>, tag: Tag) { self.api = api; self.linkBuilder = linkBuilder; self.tag = tag }
    @Instantiated let api: any Api
    @Instantiated let linkBuilder: Instantiator<Link>
    @Received let tag: Tag
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Link: Instantiable {
    public init(tag: Tag, pageBuilder: Instantiator<Page>) { self.tag = tag; self.pageBuilder = pageBuilder }
    @Instantiated let tag: Tag
    @Instantiated let pageBuilder: Instantiator<Page>
    let differentialValueCreationStamp = ProbeStamp.next()
}
