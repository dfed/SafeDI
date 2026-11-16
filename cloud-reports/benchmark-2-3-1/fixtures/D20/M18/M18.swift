import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen18: Screen, Instantiable { public init(id: Int, service: Service, model18: Model18) { self.id = id; self.service = service; self.model18 = model18; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model18: Model18
}
@Instantiable public final class Model18: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
