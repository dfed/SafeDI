import SafeDI
import Core
import M10
import M11
import M12
import M13
import M14
import M15
import M16
import M17
import M18
import M19
import M5
import M6
import M7
import M8
import M9
@Instantiable(generateDependencyTree: true) public final class Screen3: Screen, Instantiable { public init(id: Int, service: Service, model3: Model3, screen5Builder: Instantiator<Screen5>, screen6Builder: Instantiator<Screen6>, screen7Builder: Instantiator<Screen7>) { self.id = id; self.service = service; self.model3 = model3; self.screen5Builder = screen5Builder; self.screen6Builder = screen6Builder; self.screen7Builder = screen7Builder; _ = screen5Builder.instantiate(id * 4 + 1); _ = screen6Builder.instantiate(id * 4 + 2); _ = screen7Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model3: Model3
    @Instantiated let screen5Builder: Instantiator<Screen5>
    @Instantiated let screen6Builder: Instantiator<Screen6>
    @Instantiated let screen7Builder: Instantiator<Screen7>
}
@Instantiable public final class Model3: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
