import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen5: Screen, Instantiable { public init(id: Int, service: Service, model5: Model5) { self.id = id; self.service = service; self.model5 = model5; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model5: Model5
}
@Instantiable public final class Model5: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
