import SafeDI
import Core
import M12
import M13
import M15
@Instantiable(generateDependencyTree: true) public final class Screen11: Screen, Instantiable { public init(id: Int, service: Service, model11: Model11, screen12Builder: Instantiator<Screen12>, screen13Builder: Instantiator<Screen13>, screen15Builder: Instantiator<Screen15>) { self.id = id; self.service = service; self.model11 = model11; self.screen12Builder = screen12Builder; self.screen13Builder = screen13Builder; self.screen15Builder = screen15Builder; _ = screen12Builder.instantiate(id * 4 + 1); _ = screen13Builder.instantiate(id * 4 + 2); _ = screen15Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model11: Model11
    @Instantiated let screen12Builder: Instantiator<Screen12>
    @Instantiated let screen13Builder: Instantiator<Screen13>
    @Instantiated let screen15Builder: Instantiator<Screen15>
}
@Instantiable public final class Model11: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
