import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen11: Screen, Instantiable { public init(id: Int, service: Service, model11: Model11) { self.id = id; self.service = service; self.model11 = model11; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model11: Model11
}
@Instantiable public final class Model11: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
