// module: FuzzApp, fills a hole
import Cell1Feature
import SafeDI

@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(home: Home) { self.home = home }
    @Instantiated let home: Home
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Client: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Retry: Instantiable {
    public init(client: Client) { self.client = client }
    @Received let client: Client
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(client: Client, retryBuilder: Instantiator<Retry>) { self.client = client; self.retryBuilder = retryBuilder }
    @Instantiated let client: Client
    @Instantiated let retryBuilder: Instantiator<Retry>
    let differentialValueCreationStamp = ProbeStamp.next()
}
