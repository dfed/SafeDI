@Instantiable
public final class Service: Instantiable, Sendable { public init() {} }
@Instantiable
public final class Zeta: Instantiable, Sendable {
    public init(betaBuilder: SendableInstantiator<Beta>, service: Service) { self.betaBuilder = betaBuilder; self.service = service }
    @Instantiated let betaBuilder: SendableInstantiator<Beta>
    @Received let service: Service
}
@Instantiable(generateMock: true, customMockName: "customMock")
public final class Beta: Instantiable, Sendable {
    public init(zetaBuilder: SendableInstantiator<Zeta>, betaBuilder: SendableInstantiator<Beta>?, service: Service) { self.zetaBuilder = zetaBuilder; self.betaBuilder = betaBuilder; self.service = service }
    @Instantiated let zetaBuilder: SendableInstantiator<Zeta>
    @Received(onlyIfAvailable: true) let betaBuilder: SendableInstantiator<Beta>?
    @Received let service: Service
    #if DEBUG
    public static func customMock(zetaBuilder: SendableInstantiator<Zeta>, betaBuilder: SendableInstantiator<Beta>?, service: Service) -> Beta { Beta(zetaBuilder: zetaBuilder, betaBuilder: betaBuilder, service: service) }
    #endif
}
