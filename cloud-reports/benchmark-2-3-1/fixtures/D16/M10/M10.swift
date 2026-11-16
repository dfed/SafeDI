import SafeDI
import Core
import M12
import M14
import M15
@Instantiable(generateDependencyTree: true) public final class Screen10: Screen, Instantiable { public init(id: Int, service: Service, model10: Model10, screen12Builder: Instantiator<Screen12>, screen14Builder: Instantiator<Screen14>, screen15Builder: Instantiator<Screen15>) { self.id = id; self.service = service; self.model10 = model10; self.screen12Builder = screen12Builder; self.screen14Builder = screen14Builder; self.screen15Builder = screen15Builder; _ = screen12Builder.instantiate(id * 4 + 1); _ = screen14Builder.instantiate(id * 4 + 2); _ = screen15Builder.instantiate(id * 4 + 3); super.init() }
    @Forwarded let id: Int
    @Received let service: Service
    @Instantiated let model10: Model10
    @Instantiated let screen12Builder: Instantiator<Screen12>
    @Instantiated let screen14Builder: Instantiator<Screen14>
    @Instantiated let screen15Builder: Instantiator<Screen15>
}
@Instantiable public final class Model10: Instantiable { public init(id: Int, service: Service) { self.id = id; self.service = service }
    @Received let id: Int
    @Received let service: Service
}
