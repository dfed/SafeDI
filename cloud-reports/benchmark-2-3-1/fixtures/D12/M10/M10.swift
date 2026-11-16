import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen10: Screen, Instantiable { public init(id: Int, service: Service, model10: Model10) { self.id = id; self.service = service; self.model10 = model10; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model10: Model10
}
@Instantiable public final class Model10: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
