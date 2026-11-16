import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen12: Screen, Instantiable { public init(id: Int, service: Service, model12: Model12) { self.id = id; self.service = service; self.model12 = model12; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model12: Model12
}
@Instantiable public final class Model12: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
