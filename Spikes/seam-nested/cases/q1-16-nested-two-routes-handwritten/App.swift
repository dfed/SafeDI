import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

@main
struct Main {
	static func main() {
		let ctx = Ctx()
		let region = "eu"
		let top = Top(
			serviceBuilder: { scope in
				switch scope {
				case .own: Impl(tag: "own:\(ctx.name)")
				case .mid(.m_service): Impl(tag: "m:\(ctx.name)")
				}
			},
			serviceSendableBuilder: { scope in
				switch scope {
				case .mid(.deepBuilder(.d_service)): Impl(tag: "d-via-mid:\(region)")
				case .midBuilder(.m_service): Impl(tag: "m-via-builder:\(region)")
				case .midBuilder_Sendable(.deepBuilder(.d_service)): Impl(tag: "d-via-builder:\(region)")
				}
			},
		)
		print(top.tags())
	}
}
