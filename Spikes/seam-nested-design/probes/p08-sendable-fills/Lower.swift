import SafeDI
public protocol KP: Sendable { var tag: String { get } }
public protocol H: Sendable { var tag: String { get } }

// J: one plain place of KP.
public final class J: Instantiable { public let k: any KP; init(k: any KP) { self.k = k } }
extension J {
	@frozen public enum SafeDIScope_KP { case k(k_Values); public struct k_Values { public let level: Int } }
	public convenience init(level: Int, kpBuilder: @escaping (SafeDIScope_KP) -> any KP) {
		self.init(k: kpBuilder(.k(SafeDIScope_KP.k_Values(level: level))))
	}
}
// I: calls J inside a @Sendable function; has an own staged place `job` (a Sendable wrapper the seam builds); and a staged place
// `workerMaker_job` inside a @Sendable function of its own tree, so that place has three stages.
public final class Worker: Instantiable, Sendable { public let job: SendableLazilyInstantiated<any KP>; init(job: SendableLazilyInstantiated<any KP>) { self.job = job } }
public final class I {
	public let jMaker: SendableInstantiator<J>
	public let job: SendableLazilyInstantiated<any KP>
	public let workerMaker: SendableInstantiator<Worker>
	init(jMaker: SendableInstantiator<J>, job: SendableLazilyInstantiated<any KP>, workerMaker: SendableInstantiator<Worker>) { self.jMaker = jMaker; self.job = job; self.workerMaker = workerMaker }
}
extension I {
	@frozen public enum SafeDISendableScope_KP { case jMaker(J.SafeDIScope_KP) }
	public enum SafeDIStagedScope_KP_job {
		public struct Stage1 { public let name: String }
		public struct Stage2 {}
	}
	public enum SafeDIStagedScope_KP_workerMaker_job {
		public struct Stage1 { public let name: String }
		public struct Stage2 {}
		public struct Stage3 {}
	}
	public convenience init(
		name: String,
		kpSendableBuilder: @escaping @Sendable (SafeDISendableScope_KP) -> any KP,
		kpBuilder_job: @escaping (SafeDIStagedScope_KP_job.Stage1) -> @Sendable (SafeDIStagedScope_KP_job.Stage2) -> any KP,
		kpBuilder_workerMaker_job: @escaping (SafeDIStagedScope_KP_workerMaker_job.Stage1) -> @Sendable (SafeDIStagedScope_KP_workerMaker_job.Stage2) -> @Sendable (SafeDIStagedScope_KP_workerMaker_job.Stage3) -> any KP
	) {
		@Sendable func __safeDI_jMaker() -> J { J(level: 1, kpBuilder: { kpSendableBuilder(.jMaker($0)) }) }
		let jMaker = SendableInstantiator<J>(__safeDI_jMaker)
		let __safeDI_kpBuilder_job_Stage2 = kpBuilder_job(SafeDIStagedScope_KP_job.Stage1(name: name))
		@Sendable func __safeDI_job() -> any KP { __safeDI_kpBuilder_job_Stage2(SafeDIStagedScope_KP_job.Stage2()) }
		let job = SendableLazilyInstantiated<any KP>(__safeDI_job)
		let __safeDI_kpBuilder_workerMaker_job_Stage2 = kpBuilder_workerMaker_job(SafeDIStagedScope_KP_workerMaker_job.Stage1(name: name))
		@Sendable func __safeDI_workerMaker() -> Worker {
			let __safeDI_kpBuilder_workerMaker_job_Stage3 = __safeDI_kpBuilder_workerMaker_job_Stage2(SafeDIStagedScope_KP_workerMaker_job.Stage2())
			@Sendable func __safeDI_job() -> any KP { __safeDI_kpBuilder_workerMaker_job_Stage3(SafeDIStagedScope_KP_workerMaker_job.Stage3()) }
			return Worker(job: SendableLazilyInstantiated<any KP>(__safeDI_job))
		}
		self.init(jMaker: jMaker, job: job, workerMaker: SendableInstantiator<Worker>(__safeDI_workerMaker))
	}
}
// L: one plain place of H.
public final class L: Sendable { public let h: any H; init(h: any H) { self.h = h } }
extension L {
	@frozen public enum SafeDIScope_H { case h(h_Values); public struct h_Values {} }
	public convenience init(hBuilder: @escaping (SafeDIScope_H) -> any H) { self.init(h: hBuilder(.h(SafeDIScope_H.h_Values()))) }
}
