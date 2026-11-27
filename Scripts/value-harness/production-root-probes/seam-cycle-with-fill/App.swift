// module: FuzzApp, fills a hole
import FuzzFeature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(browser: Browser) { self.browser = browser }
    @Instantiated let browser: Browser
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(tag: Tag) { self.tag = tag }
    @Received let tag: Tag
    let differentialValueCreationStamp = ProbeStamp.next()
}
