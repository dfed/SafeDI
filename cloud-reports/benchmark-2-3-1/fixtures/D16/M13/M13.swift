import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen13: Screen, Instantiable { public init(id: Int, service: Service, model13: Model13) { self.id = id; self.service = service; self.model13 = model13; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model13: Model13
}
@Instantiable public final class Model13: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
