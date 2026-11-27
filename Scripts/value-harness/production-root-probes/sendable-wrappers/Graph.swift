import SafeDI

@Instantiable(isRoot: true)
public final class Root: Instantiable, Sendable {
    public init(client: SendableLazilyInstantiated<Client>, workerBuilder: SendableInstantiator<Worker>, monitor: Monitor) { self.client = client; self.workerBuilder = workerBuilder; self.monitor = monitor }
    @Instantiated let client: SendableLazilyInstantiated<Client>
    @Instantiated let workerBuilder: SendableInstantiator<Worker>
    @Instantiated let monitor: Monitor
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Client: Instantiable, Sendable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Worker: Instantiable, Sendable {
    public init(client: Client, jobBuilder: SendableInstantiator<Job>) { self.client = client; self.jobBuilder = jobBuilder }
    @Received let client: Client
    @Instantiated let jobBuilder: SendableInstantiator<Job>
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Job: Instantiable, Sendable {
    public init(client: SendableLazilyInstantiated<Client>, monitor: Monitor?) { self.client = client; self.monitor = monitor }
    @Received let client: SendableLazilyInstantiated<Client>
    @Received(onlyIfAvailable: true) let monitor: Monitor?
    let differentialValueCreationStamp = ProbeStamp.next()
}

@Instantiable
public final class Monitor: Instantiable, Sendable {
    public init() {}
    let differentialValueCreationStamp = ProbeStamp.next()
}
