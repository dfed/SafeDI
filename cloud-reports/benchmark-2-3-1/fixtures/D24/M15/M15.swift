import SafeDI
import Core
import M16
import M17
import M19
import M20
import M21
import M22
import M23
@Instantiable(generateDependencyTree: true) public final class Screen15: Screen, Instantiable { public init(id: Int, service: Service, model15: Model15, screen16Builder: Instantiator<Screen16>, screen17Builder: Instantiator<Screen17>, screen19Builder: Instantiator<Screen19>) { self.id = id; self.service = service; self.model15 = model15; self.screen16Builder = screen16Builder; self.screen17Builder = screen17Builder; self.screen19Builder = screen19Builder; _ = screen16Builder.instantiate(id * 4 + 1); _ = screen17Builder.instantiate(id * 4 + 2); _ = screen19Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model15: Model15
    @Instantiated let screen16Builder: Instantiator<Screen16>
    @Instantiated let screen17Builder: Instantiator<Screen17>
    @Instantiated let screen19Builder: Instantiator<Screen19>
}
@Instantiable public final class Model15: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
