import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen9: Screen, Instantiable { public init(id: Int, service: Service, model9: Model9) { self.id = id; self.service = service; self.model9 = model9; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model9: Model9
}
@Instantiable public final class Model9: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
