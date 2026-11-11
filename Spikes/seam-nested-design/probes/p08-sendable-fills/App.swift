import Feature
import Lower
import SafeDI

struct HImpl: H { let tag: String }
/// Not Sendable.
final class Ctx { let name = "ctx" }
@main
struct App {
	static func main() {
		let ctx = Ctx()
		let s = S(
			config: Config(name: "cfg"),
			hSendableBuilder: { scope in
				switch scope {
				case .i_jMaker_k_l: HImpl(tag: "l-in-k")
				case .i_job_l: HImpl(tag: "l-in-job")
				case .i_workerMaker_job_l(.h): HImpl(tag: "l-in-worker")
				}
			},
			hBuilder_i_jMaker_k_h: { stage1 in let name = stage1.config.name + ctx.name; return { stage2 in HImpl(tag: "k:\(name):\(stage2.level)") } },
			hBuilder_i_job_h: { stage1 in let name = stage1.config.name + stage1.name; return { _ in HImpl(tag: "job:\(name)") } },
			hBuilder_i_workerMaker_job_h: { stage1 in let name = stage1.config.name + stage1.name; return { _ in { _ in HImpl(tag: "worker:\(name)") } } },
		)
		print(s.i.jMaker.instantiate().k.tag, s.i.job.instance.tag, s.i.workerMaker.instantiate().job.instance.tag)
	}
}
