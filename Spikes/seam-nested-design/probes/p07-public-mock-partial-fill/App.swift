// A test module calling `M`'s public mock.
import Feature
import Lower

struct Stub: Service { let tag: String }
/// Not Sendable.
final class Ctx { let name = "ctx" }

@main struct Main {
	static func main() {
		let ctx = Ctx()
		// A test that ignores the scope.
		print(M.mock(serviceBuilder: { _ in Stub(tag: "stub:\(ctx.name)") }, serviceSendableBuilder: { _ in Stub(tag: "stub-s") }).p.tags())
		// A test that opens it: the cases `M`'s module fills never arrive, and still have to be listed, or covered by `.p`.
		nonisolated(unsafe) var unexpected = 0
		let mock = M.mock(
			serviceBuilder: { scope in
				switch scope {
				case .p(.b): return Stub(tag: "b:\(ctx.name)")
				case .p(.q(.y)): return Stub(tag: "q.y:\(ctx.name)")
				case .p(.a), .p(.q(.x)):
					unexpected += 1
					return Stub(tag: "never")
				}
			},
			serviceSendableBuilder: { scope in
				switch scope {
				case .p_Sendable(.qBuilder(.y)): Stub(tag: "built q.y")
				case .p_Sendable: Stub(tag: "never")
				}
			},
		)
		print(mock.p.tags(), "filled places reached the test's builder: \(unexpected)")
	}
}
