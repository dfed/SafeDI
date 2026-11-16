import SafeDI
import Core
import M12
import M13
import M14
import M16
import M17
import M18
import M19
import M20
import M21
import M22
import M23
@Instantiable(generateDependencyTree: true) public final class Screen10: Screen, Instantiable { public init(id: Int, service: Service, model10: Model10, screen12Builder: Instantiator<Screen12>, screen13Builder: Instantiator<Screen13>, screen14Builder: Instantiator<Screen14>) { self.id = id; self.service = service; self.model10 = model10; self.screen12Builder = screen12Builder; self.screen13Builder = screen13Builder; self.screen14Builder = screen14Builder; _ = screen12Builder.instantiate(id * 4 + 1); _ = screen13Builder.instantiate(id * 4 + 2); _ = screen14Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model10: Model10
    @Instantiated let screen12Builder: Instantiator<Screen12>
    @Instantiated let screen13Builder: Instantiator<Screen13>
    @Instantiated let screen14Builder: Instantiator<Screen14>
}
@Instantiable public final class Model10: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
