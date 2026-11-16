import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen14: Screen, Instantiable { public init(id: Int, service: Service, model14: Model14) { self.id = id; self.service = service; self.model14 = model14; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model14: Model14
}
@Instantiable public final class Model14: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
