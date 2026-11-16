import SafeDI
import Core
@Instantiable(generateDependencyTree: true) public final class Screen17: Screen, Instantiable { public init(id: Int, service: Service, model17: Model17) { self.id = id; self.service = service; self.model17 = model17; super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model17: Model17
}
@Instantiable public final class Model17: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
