// Hand-written. Stands in for the caller SafeDI would generate.
import Feature
import SafeDI

struct Impl: Service { let tag: String }

struct Root {
	let seam: SeamA

	init() {
		let region = "eu"
		func __safeDI_seam() -> SeamA {
			@Sendable
			func __safeDI_serviceSendableBuilder_service(_ scope: SeamA.SafeDIScope_Service_Sendable.service_Values) -> any Service {
				Impl(tag: "fill-A:\(region):\(scope.marker.name)")
			}
			@Sendable
			func __safeDI_serviceSendableBuilder_SeamB_service(_ scope: SeamB.SafeDIScope_Service_Sendable.service_Values) -> any Service {
				Impl(tag: "fill-B:\(region):\(scope.marker.name)")
			}
			@Sendable
			func __safeDI_serviceSendableBuilder(_ scope: SeamA.SafeDIScope_Service_Sendable) -> any Service {
				switch scope {
				case let .service(scope): __safeDI_serviceSendableBuilder_service(scope)
				case let .SeamB_service(scope): __safeDI_serviceSendableBuilder_SeamB_service(scope)
				}
			}
			return SeamA(serviceSendableBuilder: __safeDI_serviceSendableBuilder)
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
