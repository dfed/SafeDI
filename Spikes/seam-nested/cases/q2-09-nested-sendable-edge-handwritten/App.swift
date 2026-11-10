import Feature
import SafeDI

struct Impl: Service { let tag: String }
final class Ctx { let name = "ctx" }

@Sendable func openA(_ scope: SeamA.SafeDIScope_Service, depth: Int) -> any Service {
	switch scope {
	case .service: Impl(tag: "A\(depth)")
	}
}

@Sendable func openB(_ scope: SeamB.SafeDIScope_Service, depth: Int) -> any Service {
	switch scope {
	case .service: Impl(tag: "B\(depth)")
	case let .a(scope): openA(scope, depth: depth + 1)
	}
}

@Sendable func openASendable(_ scope: SeamA.SafeDIScope_Service_Sendable, depth: Int) -> any Service {
	switch scope {
	case let .bBuilder(scope): openB(scope, depth: depth + 1)
	case let .bBuilder_Sendable(scope): openBSendable(scope, depth: depth + 1)
	}
}

@Sendable func openBSendable(_ scope: SeamB.SafeDIScope_Service_Sendable, depth: Int) -> any Service {
	switch scope {
	case let .a(scope): openASendable(scope, depth: depth + 1)
	}
}

@main struct Main {
	static func main() {
		let ctx = Ctx()
		let seam = SeamA(
			serviceBuilder: { _ in Impl(tag: "top:\(ctx.name)") },
			serviceSendableBuilder: { scope in openASendable(scope, depth: 0) },
		)
		print(seam.walk(4))
	}
}
