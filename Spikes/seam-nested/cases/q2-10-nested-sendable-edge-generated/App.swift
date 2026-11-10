// Hand-written. Stands in for the caller SafeDI would generate.
import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

struct Root {
	let seam: SeamA

	init() {
		let ctx = Ctx()
		let region = "eu"
		func __safeDI_seam() -> SeamA {
			func __safeDI_serviceBuilder_service(_ scope: SeamA.SafeDIScope_Service.service_Values) -> any Service {
				Impl(tag: "top:\(ctx.name):\(scope.marker.name)")
			}
			func __safeDI_serviceBuilder(_ scope: SeamA.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .service(scope): __safeDI_serviceBuilder_service(scope)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_SeamA_service(_ scope: SeamA.SafeDIScope_Service.service_Values) -> any Service {
				Impl(tag: "fill-A:\(region):\(scope.marker.name)")
			}
			@Sendable func __safeDI_serviceSendableBuilder_SeamB_service(_ scope: SeamB.SafeDIScope_Service.service_Values) -> any Service {
				Impl(tag: "fill-B:\(region):\(scope.marker.name)")
			}
			@Sendable func __safeDI_serviceSendableBuilder_SeamA(_ scope: SeamA.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .service(scope): __safeDI_serviceSendableBuilder_SeamA_service(scope)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_SeamB(_ scope: SeamB.SafeDIScope_Service) -> any Service {
				switch scope {
				case let .service(scope): __safeDI_serviceSendableBuilder_SeamB_service(scope)
				case let .a(scope): __safeDI_serviceSendableBuilder_SeamA(scope)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_SeamA_Sendable(_ scope: SeamA.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .bBuilder(scope): __safeDI_serviceSendableBuilder_SeamB(scope)
				case let .bBuilder_Sendable(scope): __safeDI_serviceSendableBuilder_SeamB_Sendable(scope)
				}
			}
			@Sendable func __safeDI_serviceSendableBuilder_SeamB_Sendable(_ scope: SeamB.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .a(scope): __safeDI_serviceSendableBuilder_SeamA_Sendable(scope)
				}
			}
			return SeamA(serviceBuilder: __safeDI_serviceBuilder, serviceSendableBuilder: __safeDI_serviceSendableBuilder_SeamA_Sendable)
		}
		seam = __safeDI_seam()
	}
}

@main struct Main {
	static func main() {
		print(Root().seam.walk(4))
	}
}
