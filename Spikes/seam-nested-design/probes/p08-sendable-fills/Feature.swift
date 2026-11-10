// S can build KP (KImpl), cannot build H. KImpl instantiates `h: any H` and seam `l: L`.
import Lower
import SafeDI
public final class KImpl: KP, Sendable {
	public let h: any H; public let l: L
	init(h: any H, l: L) { self.h = h; self.l = l }
	public var tag: String { "KImpl(\(h.tag),\(l.h.tag))" }
}
/// Not Sendable.
public final class Config { public let name: String; public init(name: String) { self.name = name } }
public final class S { public let i: I; init(i: I) { self.i = i } }
extension S {
	// Calls of L inside @Sendable fills.
	@frozen public enum SafeDISendableScope_H {
		case i_jMaker_k_l(L.SafeDIScope_H)
		case i_job_l(L.SafeDIScope_H)
		case i_workerMaker_job_l(L.SafeDIScope_H)
	}
	// Own places inside @Sendable fills: staged, one boundary per @Sendable function of the fill on the path.
	public enum SafeDIStagedScope_H_i_jMaker_k_h {
		public struct Stage1 { public let config: Config }
		public struct Stage2 { public let level: Int }
	}
	public enum SafeDIStagedScope_H_i_job_h {
		public struct Stage1 { public let config: Config; public let name: String }
		public struct Stage2 {}
	}
	public enum SafeDIStagedScope_H_i_workerMaker_job_h {
		public struct Stage1 { public let config: Config; public let name: String }
		public struct Stage2 {}
		public struct Stage3 {}
	}
	public convenience init(
		config: Config,
		hSendableBuilder: @escaping @Sendable (SafeDISendableScope_H) -> any H,
		hBuilder_i_jMaker_k_h: @escaping (SafeDIStagedScope_H_i_jMaker_k_h.Stage1) -> @Sendable (SafeDIStagedScope_H_i_jMaker_k_h.Stage2) -> any H,
		hBuilder_i_job_h: @escaping (SafeDIStagedScope_H_i_job_h.Stage1) -> @Sendable (SafeDIStagedScope_H_i_job_h.Stage2) -> any H,
		hBuilder_i_workerMaker_job_h: @escaping (SafeDIStagedScope_H_i_workerMaker_job_h.Stage1) -> @Sendable (SafeDIStagedScope_H_i_workerMaker_job_h.Stage2) -> @Sendable (SafeDIStagedScope_H_i_workerMaker_job_h.Stage3) -> any H
	) {
		func __safeDI_i() -> I {
			// Fill of J's place k, @Sendable because I's @Sendable enum reaches it. The stage call of the place inside it is made
			// just before the fill is declared.
			let __safeDI_hBuilder_i_jMaker_k_h_Stage2 = hBuilder_i_jMaker_k_h(SafeDIStagedScope_H_i_jMaker_k_h.Stage1(config: config))
			@Sendable func __safeDI_kpBuilder_J_k(_ scope: J.SafeDIScope_KP.k_Values) -> any KP {
				let level = scope.level
				let h: any H = __safeDI_hBuilder_i_jMaker_k_h_Stage2(SafeDIStagedScope_H_i_jMaker_k_h.Stage2(level: level))
				let l = L(hBuilder: { hSendableBuilder(.i_jMaker_k_l($0)) })
				return KImpl(h: h, l: l)
			}
			@Sendable func __safeDI_kpBuilder_J(_ scope: J.SafeDIScope_KP) -> any KP {
				switch scope {
				case let .k(scope): __safeDI_kpBuilder_J_k(scope)
				}
			}
			@Sendable func __safeDI_kpSendableBuilder_I(_ scope: I.SafeDISendableScope_KP) -> any KP {
				switch scope {
				case let .jMaker(scope): __safeDI_kpBuilder_J(scope)
				}
			}
			// Staged fill, first stage plain: the place's first stage is called in the fill's first stage.
			func __safeDI_kpBuilder_I_job(_ scope: I.SafeDIStagedScope_KP_job.Stage1) -> @Sendable (I.SafeDIStagedScope_KP_job.Stage2) -> any KP {
				let name = scope.name
				let __safeDI_hBuilder_i_job_h_Stage2 = hBuilder_i_job_h(SafeDIStagedScope_H_i_job_h.Stage1(config: config, name: name))
				@Sendable func __safeDI_kpBuilder_I_job_Stage2(_ scope: I.SafeDIStagedScope_KP_job.Stage2) -> any KP {
					let h: any H = __safeDI_hBuilder_i_job_h_Stage2(SafeDIStagedScope_H_i_job_h.Stage2())
					let l = L(hBuilder: { hSendableBuilder(.i_job_l($0)) })
					return KImpl(h: h, l: l)
				}
				return __safeDI_kpBuilder_I_job_Stage2
			}
			// Three-stage fill, first stage plain: one boundary per later stage.
			func __safeDI_kpBuilder_I_workerMaker_job(_ scope: I.SafeDIStagedScope_KP_workerMaker_job.Stage1) -> @Sendable (I.SafeDIStagedScope_KP_workerMaker_job.Stage2) -> @Sendable (I.SafeDIStagedScope_KP_workerMaker_job.Stage3) -> any KP {
				let name = scope.name
				let __safeDI_hBuilder_i_workerMaker_job_h_Stage2 = hBuilder_i_workerMaker_job_h(SafeDIStagedScope_H_i_workerMaker_job_h.Stage1(config: config, name: name))
				@Sendable func __safeDI_kpBuilder_I_workerMaker_job_Stage2(_ scope: I.SafeDIStagedScope_KP_workerMaker_job.Stage2) -> @Sendable (I.SafeDIStagedScope_KP_workerMaker_job.Stage3) -> any KP {
					let __safeDI_hBuilder_i_workerMaker_job_h_Stage3 = __safeDI_hBuilder_i_workerMaker_job_h_Stage2(SafeDIStagedScope_H_i_workerMaker_job_h.Stage2())
					@Sendable func __safeDI_kpBuilder_I_workerMaker_job_Stage3(_ scope: I.SafeDIStagedScope_KP_workerMaker_job.Stage3) -> any KP {
						let h: any H = __safeDI_hBuilder_i_workerMaker_job_h_Stage3(SafeDIStagedScope_H_i_workerMaker_job_h.Stage3())
						let l = L(hBuilder: { hSendableBuilder(.i_workerMaker_job_l($0)) })
						return KImpl(h: h, l: l)
					}
					return __safeDI_kpBuilder_I_workerMaker_job_Stage3
				}
				return __safeDI_kpBuilder_I_workerMaker_job_Stage2
			}
			return I(name: "n", kpSendableBuilder: __safeDI_kpSendableBuilder_I, kpBuilder_job: __safeDI_kpBuilder_I_job, kpBuilder_workerMaker_job: __safeDI_kpBuilder_I_workerMaker_job)
		}
		self.init(i: __safeDI_i())
	}
}
