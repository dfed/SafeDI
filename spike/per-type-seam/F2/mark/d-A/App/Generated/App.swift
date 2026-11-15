import Feature
import Harness
import SafeDI

extension Root {
	public convenience init() {
		func __safeDI_home() -> Home {
			func __safeDI_live(cache: Cache, mark: Mark?) -> any Api {
				Live(cache: cache, mark: mark)
			}
			func __safeDI_apiBuilder_Home() -> Home.SafeDIScope_Api.__safeDI_Builder<any Api> {
				.init(screenBuilder: { _ in __safeDI_apiBuilder_Home_Screen_Scope(mark: nil) })
			}
			func __safeDI_apiBuilder_Home_Screen_Scope(mark: Mark?) -> Home.SafeDIScope_Api.Screen_Scope.__safeDI_Builder<any Api> {
				.init(
					monitor: { values in __safeDI_live(cache: values.cache, mark: mark) },
					stepBuilder: { values in __safeDI_apiBuilder_Home_Step_Scope(cache: values.cache) },
				)
			}
			func __safeDI_apiBuilder_Home_Step_Scope(cache: Cache) -> Home.SafeDIScope_Api.Step_Scope.__safeDI_Builder<any Api> {
				.init(
					api: { values in __safeDI_live(cache: cache, mark: values.mark) },
				)
			}
			return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home())
		}
		let home: Home = __safeDI_home()
		self.init(home: home)
	}
}
