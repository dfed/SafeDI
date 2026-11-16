import SafeDI
import Core
import M4
import M5
import M6
@Instantiable(generateDependencyTree: true) public final class Screen1: Screen, Instantiable { public init(id: Int, service: Service, model1: Model1, screen4Builder: Instantiator<Screen4>, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>) { self.id = id; self.service = service; self.model1 = model1; self.screen4Builder = screen4Builder; self.screen5Builder = screen5Builder; self.screen6Builder = screen6Builder; _ = screen4Builder.instantiate(id * 4 + 1); _ = screen5Builder.instantiate(id * 4 + 2); _ = screen6Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model1: Model1
    @Instantiated let screen4Builder: Instantiator<Screen4>
    @Instantiated let screen5Builder: Instantiator<Screen5>
    @Instantiated let screen6Builder: Instantiator<Screen6>
}
@Instantiable public final class Model1: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
