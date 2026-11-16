import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen16: Screen, Instantiable { public init(id: Int, service: Service, model16: Model16) { self.id = id; self.service = service; self.model16 = model16; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model16: Model16
}
@Instantiable public final class Model16: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
