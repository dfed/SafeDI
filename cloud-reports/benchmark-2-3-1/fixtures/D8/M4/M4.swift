import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen4: Screen, Instantiable { public init(id: Int, service: Service, model4: Model4) { self.id = id; self.service = service; self.model4 = model4; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model4: Model4
}
@Instantiable public final class Model4: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
