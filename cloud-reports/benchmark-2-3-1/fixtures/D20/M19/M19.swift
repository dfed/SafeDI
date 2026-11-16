import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen19: Screen, Instantiable { public init(id: Int, service: Service, model19: Model19) { self.id = id; self.service = service; self.model19 = model19; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model19: Model19
}
@Instantiable public final class Model19: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
