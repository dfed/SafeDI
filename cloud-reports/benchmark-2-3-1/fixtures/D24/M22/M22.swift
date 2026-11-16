import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen22: Screen, Instantiable { public init(id: Int, service: Service, model22: Model22) { self.id = id; self.service = service; self.model22 = model22; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model22: Model22
}
@Instantiable public final class Model22: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
