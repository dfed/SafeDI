import SafeDI
import Core
import M10
import M11
import M12
import M13
import M14
import M15
import M4
import M5
import M7
import M8
import M9
@Instantiable(generateDependencyTree: true) public final class Screen1: Screen, Instantiable { public init(id: Int, service: Service, model1: Model1, screen4Builder: Instantiator<Screen4>, screen5Builder: Instantiator<Screen5>, screen7Builder: Instantiator<Screen7>) { self.id = id; self.service = service; self.model1 = model1; self.screen4Builder = screen4Builder; self.screen5Builder = screen5Builder; self.screen7Builder = screen7Builder; _ = screen4Builder.instantiate(id * 4 + 1); _ = screen5Builder.instantiate(id * 4 + 2); _ = screen7Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model1: Model1
    @Instantiated let screen4Builder: Instantiator<Screen4>
    @Instantiated let screen5Builder: Instantiator<Screen5>
    @Instantiated let screen7Builder: Instantiator<Screen7>
}
@Instantiable public final class Model1: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
