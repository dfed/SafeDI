import SafeDI
import Core
import M20
import M21
import M23
@Instantiable(generateDependencyTree: true) public final class Screen16: Screen, Instantiable { public init(id: Int, service: Service, model16: Model16, screen20Builder: Instantiator<Screen20>, screen21Builder: Instantiator<Screen21>, screen23Builder: Instantiator<Screen23>) { self.id = id; self.service = service; self.model16 = model16; self.screen20Builder = screen20Builder; self.screen21Builder = screen21Builder; self.screen23Builder = screen23Builder; _ = screen20Builder.instantiate(id * 4 + 1); _ = screen21Builder.instantiate(id * 4 + 2); _ = screen23Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model16: Model16
    @Instantiated let screen20Builder: Instantiator<Screen20>
    @Instantiated let screen21Builder: Instantiator<Screen21>
    @Instantiated let screen23Builder: Instantiator<Screen23>
}
@Instantiable public final class Model16: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
