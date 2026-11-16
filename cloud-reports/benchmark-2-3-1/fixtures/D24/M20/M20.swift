import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen20: Screen, Instantiable { public init(id: Int, service: Service, model20: Model20) { self.id = id; self.service = service; self.model20 = model20; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model20: Model20
}
@Instantiable public final class Model20: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
