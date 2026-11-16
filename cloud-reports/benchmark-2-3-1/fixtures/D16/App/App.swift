import SafeDI
import Core
import M0
import M1
import M10
import M11
import M12
import M13
import M14
import M15
import M2
import M3
import M4
import M5
import M6
import M7
import M8
import M9
@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init() {} }
@Instantiable(isRoot: true, generateMock: true) public final class Root: Instantiable {  init(service: Service, screen0Builder: Instantiator<Screen0>, screen1Builder: Instantiator<Screen1>, screen2Builder: Instantiator<Screen2>, screen3Builder: Instantiator<Screen3>) { self.service = service; self.screen0Builder = screen0Builder; self.screen1Builder = screen1Builder; self.screen2Builder = screen2Builder; self.screen3Builder = screen3Builder; _ = screen0Builder.instantiate(0 * 4 + 1); _ = screen1Builder.instantiate(0 * 4 + 2); _ = screen2Builder.instantiate(0 * 4 + 3); _ = screen3Builder.instantiate(0 * 4 + 4) }
    @Instantiated let service: Service
    @Instantiated let screen0Builder: Instantiator<Screen0>
    @Instantiated let screen1Builder: Instantiator<Screen1>
    @Instantiated let screen2Builder: Instantiator<Screen2>
    @Instantiated let screen3Builder: Instantiator<Screen3>
}
