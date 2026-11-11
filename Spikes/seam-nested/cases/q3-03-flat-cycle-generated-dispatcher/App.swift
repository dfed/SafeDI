// Hand-written. Stands in for the caller SafeDI would generate.
import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

struct Root {
	let seam: SeamA

	init() {
		let ctx = Ctx()
		func __safeDI_seam() -> SeamA {
			func __safeDI_serviceBuilder_service(_ scope: SeamA.SafeDIScope_Service.service_Values) -> any Service {
				Impl(tag: "fill-A:\(ctx.name):\(scope.marker.name)")
			}
			func __safeDI_serviceBuilder_SeamB_service(_ scope: SeamB.SafeDIScope_Service.service_Values) -> any Service {
				Impl(tag: "fill-B:\(ctx.name):\(scope.marker.name)")
			}
			func __safeDI_serviceBuilder(_ scope: SeamA.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .service(scope): __safeDI_serviceBuilder_service(scope)
				case let .SeamB_service(scope): __safeDI_serviceBuilder_SeamB_service(scope)
				}
			}
			return SeamA(serviceBuilder: __safeDI_serviceBuilder)
		}
		seam = __safeDI_seam()
	}
}

@main
struct Main {
	static func main() {
		print(Root().seam.walk(4))
	}
}
