import Feature
import Harness
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_home() -> Home {
			func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
				.init(screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() })
			}
			func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
				.init(stepBuilder: { values in __safeDI_apiBuilder_Home_Step_Scope(cache: values.cache) })
			}
			func __safeDI_apiBuilder_Home_Step_Scope(cache: Cache) -> Home.SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api> {
				func __safeDI_live() -> any Api {
					Live(cache: cache)
				}
				return .init(
					api: { _ in __safeDI_live() },
					screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope() },
				)
			}
			return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		}
		let home: Home = __safeDI_home()
		self.init(home: home)
	}
}
