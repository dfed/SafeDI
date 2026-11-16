import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen23: Screen, Instantiable { public init(id: Int, service: Service, model23: Model23) { self.id = id; self.service = service; self.model23 = model23; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model23: Model23
}
@Instantiable public final class Model23: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
