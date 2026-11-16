import SafeDI
import Core
import M10
import M11
import M12
import M13
import M14
import M15
import M8
@Instantiable(generateDependencyTree: true) public final class Screen4: Screen, Instantiable { public init(id: Int, service: Service, model4: Model4, screen8Builder: Instantiator<Screen8>, screen10Builder: Instantiator<Screen10>, screen11Builder: Instantiator<Screen11>) { self.id = id; self.service = service; self.model4 = model4; self.screen8Builder = screen8Builder; self.screen10Builder = screen10Builder; self.screen11Builder = screen11Builder; _ = screen8Builder.instantiate(id * 4 + 1); _ = screen10Builder.instantiate(id * 4 + 2); _ = screen11Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model4: Model4
    @Instantiated let screen8Builder: Instantiator<Screen8>
    @Instantiated let screen10Builder: Instantiator<Screen10>
    @Instantiated let screen11Builder: Instantiator<Screen11>
}
@Instantiable public final class Model4: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
