// module: FuzzApp, fills a hole
import Cell2Feature
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
public final class Job: Instantiable {
    public init(client: Client) { self.client = client }
    @Received let client: Client
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Uploader: Instantiable {
    public init(jobBuilder: Instantiator<Job>, cache: LazilyInstantiated<Cache>) { self.jobBuilder = jobBuilder; self.cache = cache }
    @Instantiated let jobBuilder: Instantiator<Job>
    @Instantiated let cache: LazilyInstantiated<Cache>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Cache: Instantiable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable(fulfillingAdditionalTypes: [Api.self])
public final class ApiImpl: Instantiable, Api {
    public init(client: Client, uploader: Uploader) { self.client = client; self.uploader = uploader }
    @Instantiated let client: Client
    @Instantiated let uploader: Uploader
    let differentialValueCreationStamp = ProbeStamp.next()
}
