import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen8: Screen, Instantiable { public init(id: Int, service: Service, model8: Model8) { self.id = id; self.service = service; self.model8 = model8; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model8: Model8
}
@Instantiable public final class Model8: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
