@Instantiable
public final class Service: Instantiable, Sendable { public init() {} }
@Instantiable
public final class Alpha: Instantiable, Sendable {
    public init(betaBuilder: SendableInstantiator<Beta>, service: Service) { self.betaBuilder = betaBuilder; self.service = service }
    @Instantiated let betaBuilder: SendableInstantiator<Beta>
    @Received let service: Service
}
@Instantiable(generateMock: true, customMockName: "customMock")
public final class Beta: Instantiable, Sendable {
    public init(alphaBuilder: SendableInstantiator<Alpha>, betaBuilder: SendableInstantiator<Beta>?, service: Service) { self.alphaBuilder = alphaBuilder; self.betaBuilder = betaBuilder; self.service = service }
    @Instantiated let alphaBuilder: SendableInstantiator<Alpha>
    @Received(onlyIfAvailable: true) let betaBuilder: SendableInstantiator<Beta>?
    @Received let service: Service
    #if DEBUG
    public static func customMock(alphaBuilder: SendableInstantiator<Alpha>, betaBuilder: SendableInstantiator<Beta>?, service: Service) -> Beta { Beta(alphaBuilder: alphaBuilder, betaBuilder: betaBuilder, service: service) }
    #endif
}
