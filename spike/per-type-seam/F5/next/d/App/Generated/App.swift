import Feature
import Harness
import SafeDI

extension Root {
    public convenience init() {
        func __safeDI_home() -> Home {
            func __safeDI_live(id: Int) -> any Api {
                Live(id: id)
            }
            func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
                .init(screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
            }
            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
                .init(
                    api: { values in __safeDI_live(id: values.id) },
                    next: { _ in __safeDI_apiBuilder_Home_Screen_Scope() }
                )
            }
            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
        }
        let home: Home = __safeDI_home()
        self.init(home: home)
    }
}
