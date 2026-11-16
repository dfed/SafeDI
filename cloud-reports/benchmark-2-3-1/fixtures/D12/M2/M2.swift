import SafeDI
import Core
import M10
import M11
import M4
import M6
import M7
import M8
import M9
@Instantiable(generateDependencyTree: true) public final class Screen2: Screen, Instantiable { public init(id: Int, service: Service, model2: Model2, screen4Builder: Instantiator<Screen4>, screen6Builder: Instantiator<Screen6>, screen7Builder: Instantiator<Screen7>) { self.id = id; self.service = service; self.model2 = model2; self.screen4Builder = screen4Builder; self.screen6Builder = screen6Builder; self.screen7Builder = screen7Builder; _ = screen4Builder.instantiate(id * 4 + 1); _ = screen6Builder.instantiate(id * 4 + 2); _ = screen7Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model2: Model2
    @Instantiated let screen4Builder: Instantiator<Screen4>
    @Instantiated let screen6Builder: Instantiator<Screen6>
    @Instantiated let screen7Builder: Instantiator<Screen7>
}
@Instantiable public final class Model2: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
