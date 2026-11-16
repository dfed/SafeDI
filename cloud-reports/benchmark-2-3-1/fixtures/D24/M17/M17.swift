import SafeDI
import Core
import M20
import M22
import M23
@Instantiable(generateDependencyTree: true) public final class Screen17: Screen, Instantiable { public init(id: Int, service: Service, model17: Model17, screen20Builder: Instantiator<Screen20>, screen22Builder: Instantiator<Screen22>, screen23Builder: Instantiator<Screen23>) { self.id = id; self.service = service; self.model17 = model17; self.screen20Builder = screen20Builder; self.screen22Builder = screen22Builder; self.screen23Builder = screen23Builder; _ = screen20Builder.instantiate(id * 4 + 1); _ = screen22Builder.instantiate(id * 4 + 2); _ = screen23Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model17: Model17
    @Instantiated let screen20Builder: Instantiator<Screen20>
    @Instantiated let screen22Builder: Instantiator<Screen22>
    @Instantiated let screen23Builder: Instantiator<Screen23>
}
@Instantiable public final class Model17: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
