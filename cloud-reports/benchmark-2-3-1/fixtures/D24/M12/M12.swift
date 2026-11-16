import SafeDI
import Core
import M16
import M18
import M19
import M20
import M21
import M22
import M23
@Instantiable(generateDependencyTree: true) public final class Screen12: Screen, Instantiable { public init(id: Int, service: Service, model12: Model12, screen16Builder: Instantiator<Screen16>, screen18Builder: Instantiator<Screen18>, screen19Builder: Instantiator<Screen19>) { self.id = id; self.service = service; self.model12 = model12; self.screen16Builder = screen16Builder; self.screen18Builder = screen18Builder; self.screen19Builder = screen19Builder; _ = screen16Builder.instantiate(id * 4 + 1); _ = screen18Builder.instantiate(id * 4 + 2); _ = screen19Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model12: Model12
    @Instantiated let screen16Builder: Instantiator<Screen16>
    @Instantiated let screen18Builder: Instantiator<Screen18>
    @Instantiated let screen19Builder: Instantiator<Screen19>
}
@Instantiable public final class Model12: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
