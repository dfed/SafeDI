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
			serviceBuilder: { _ in Impl(tag: "own:\(ctx.name)") },
			serviceSendableBuilder: { scope in
				switch scope {
				case .Mid_m_service: Impl(tag: "m:\(region)")
				case .Mid_Deep_d_service: Impl(tag: "d:\(region)")
				}
			},
		)
		print(top.tags())
	}
}
