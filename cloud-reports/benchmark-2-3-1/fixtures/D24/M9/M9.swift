import SafeDI
import Core
import M13
import M14
import M15
import M16
import M17
import M18
import M19
import M20
import M21
import M22
import M23
@Instantiable(generateDependencyTree: true) public final class Screen9: Screen, Instantiable { public init(id: Int, service: Service, model9: Model9, screen13Builder: Instantiator<Screen13>, screen14Builder: Instantiator<Screen14>, screen15Builder: Instantiator<Screen15>) { self.id = id; self.service = service; self.model9 = model9; self.screen13Builder = screen13Builder; self.screen14Builder = screen14Builder; self.screen15Builder = screen15Builder; _ = screen13Builder.instantiate(id * 4 + 1); _ = screen14Builder.instantiate(id * 4 + 2); _ = screen15Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model9: Model9
    @Instantiated let screen13Builder: Instantiator<Screen13>
    @Instantiated let screen14Builder: Instantiator<Screen14>
    @Instantiated let screen15Builder: Instantiator<Screen15>
}
@Instantiable public final class Model9: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
