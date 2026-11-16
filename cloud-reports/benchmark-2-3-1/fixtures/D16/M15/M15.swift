import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen15: Screen, Instantiable { public init(id: Int, service: Service, model15: Model15) { self.id = id; self.service = service; self.model15 = model15; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model15: Model15
}
@Instantiable public final class Model15: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
