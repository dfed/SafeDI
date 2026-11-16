import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen6: Screen, Instantiable { public init(id: Int, service: Service, model6: Model6) { self.id = id; self.service = service; self.model6 = model6; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model6: Model6
}
@Instantiable public final class Model6: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
