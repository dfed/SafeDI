import SafeDI
import Core
import M16
import M17
import M18
import M20
import M21
import M22
import M23
@Instantiable(generateDependencyTree: true) public final class Screen14: Screen, Instantiable { public init(id: Int, service: Service, model14: Model14, screen16Builder: Instantiator<Screen16>, screen17Builder: Instantiator<Screen17>, screen18Builder: Instantiator<Screen18>) { self.id = id; self.service = service; self.model14 = model14; self.screen16Builder = screen16Builder; self.screen17Builder = screen17Builder; self.screen18Builder = screen18Builder; _ = screen16Builder.instantiate(id * 4 + 1); _ = screen17Builder.instantiate(id * 4 + 2); _ = screen18Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model14: Model14
    @Instantiated let screen16Builder: Instantiator<Screen16>
    @Instantiated let screen17Builder: Instantiator<Screen17>
    @Instantiated let screen18Builder: Instantiator<Screen18>
}
@Instantiable public final class Model14: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
