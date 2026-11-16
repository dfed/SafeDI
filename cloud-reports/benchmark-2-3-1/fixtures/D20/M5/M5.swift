import SafeDI
import Core
import M11
import M12
import M13
import M14
import M15
import M16
import M17
import M18
import M19
import M8
import M9
@Instantiable(generateDependencyTree: true) public final class Screen5: Screen, Instantiable { public init(id: Int, service: Service, model5: Model5, screen8Builder: Instantiator<Screen8>, screen9Builder: Instantiator<Screen9>, screen11Builder: Instantiator<Screen11>) { self.id = id; self.service = service; self.model5 = model5; self.screen8Builder = screen8Builder; self.screen9Builder = screen9Builder; self.screen11Builder = screen11Builder; _ = screen8Builder.instantiate(id * 4 + 1); _ = screen9Builder.instantiate(id * 4 + 2); _ = screen11Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model5: Model5
    @Instantiated let screen8Builder: Instantiator<Screen8>
    @Instantiated let screen9Builder: Instantiator<Screen9>
    @Instantiated let screen11Builder: Instantiator<Screen11>
}
@Instantiable public final class Model5: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
