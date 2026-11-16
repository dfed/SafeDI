import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen21: Screen, Instantiable { public init(id: Int, service: Service, model21: Model21) { self.id = id; self.service = service; self.model21 = model21; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model21: Model21
}
@Instantiable public final class Model21: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
