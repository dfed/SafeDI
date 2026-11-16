import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen7: Screen, Instantiable { public init(id: Int, service: Service, model7: Model7) { self.id = id; self.service = service; self.model7 = model7; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model7: Model7
}
@Instantiable public final class Model7: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
