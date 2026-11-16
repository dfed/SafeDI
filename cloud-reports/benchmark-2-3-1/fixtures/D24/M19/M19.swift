import SafeDI
import Core
import M21
import M22
import M23
@Instantiable(generateDependencyTree: true) public final class Screen19: Screen, Instantiable { public init(id: Int, service: Service, model19: Model19, screen21Builder: Instantiator<Screen21>, screen22Builder: Instantiator<Screen22>, screen23Builder: Instantiator<Screen23>) { self.id = id; self.service = service; self.model19 = model19; self.screen21Builder = screen21Builder; self.screen22Builder = screen22Builder; self.screen23Builder = screen23Builder; _ = screen21Builder.instantiate(id * 4 + 1); _ = screen22Builder.instantiate(id * 4 + 2); _ = screen23Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model19: Model19
    @Instantiated let screen21Builder: Instantiator<Screen21>
    @Instantiated let screen22Builder: Instantiator<Screen22>
    @Instantiated let screen23Builder: Instantiator<Screen23>
}
@Instantiable public final class Model19: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
