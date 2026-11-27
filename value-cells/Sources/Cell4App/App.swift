// module: FuzzApp, fills a hole
import Cell4Feature
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

@Instantiable
public final class Audit: Instantiable {
    public init(client: Client) { self.client = client }
    @Received let client: Client
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(client: Client, retryBuilder: Instantiator<Retry>, auditBuilder: Instantiator<Audit>) { self.client = client; self.retryBuilder = retryBuilder; self.auditBuilder = auditBuilder }
    @Instantiated let client: Client
    @Instantiated let retryBuilder: Instantiator<Retry>
    @Instantiated let auditBuilder: Instantiator<Audit>
    let differentialValueCreationStamp = ProbeStamp.next()
}
