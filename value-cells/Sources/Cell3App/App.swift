// module: FuzzApp, fills a hole
import Cell3Feature
import SafeDI

@MainActor
@Instantiable(isRoot: true)
public final class AppRoot: Instantiable {
    public init(home: Home) { self.home = home }
    @Instantiated let home: Home
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Client: Instantiable, Sendable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Retry: Instantiable, Sendable {
    public init(client: Client) { self.client = client }
    @Received let client: Client
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api, Sendable {
    public init(client: Client, retryBuilder: SendableInstantiator<Retry>) { self.client = client; self.retryBuilder = retryBuilder }
    @Instantiated let client: Client
    @Instantiated let retryBuilder: SendableInstantiator<Retry>
    let differentialValueCreationStamp = ProbeStamp.next()
}
