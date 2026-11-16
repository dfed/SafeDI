import SafeDI
import Core
import M13
import M14
import M15
@Instantiable(generateDependencyTree: true) public final class Screen8: Screen, Instantiable { public init(id: Int, service: Service, model8: Model8, screen13Builder: Instantiator<Screen13>, screen14Builder: Instantiator<Screen14>, screen15Builder: Instantiator<Screen15>) { self.id = id; self.service = service; self.model8 = model8; self.screen13Builder = screen13Builder; self.screen14Builder = screen14Builder; self.screen15Builder = screen15Builder; _ = screen13Builder.instantiate(id * 4 + 1); _ = screen14Builder.instantiate(id * 4 + 2); _ = screen15Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model8: Model8
    @Instantiated let screen13Builder: Instantiator<Screen13>
    @Instantiated let screen14Builder: Instantiator<Screen14>
    @Instantiated let screen15Builder: Instantiator<Screen15>
}
@Instantiable public final class Model8: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
