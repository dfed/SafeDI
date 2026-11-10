import Feature
import SafeDI

struct Impl: Service { let tag: String }
/// Not Sendable.
final class Ctx { let name = "ctx" }
nonisolated(unsafe) var builds = [String]()

func tags(_ feature: Feature) -> [String] {
	[feature.a.service.tag, feature.lazy.instance.tag, feature.lazy.instance.tag, feature.maker.instantiate("m1").tag, feature.maker.instantiate("m2").tag, feature.job.instance.tag, feature.job.instance.tag, feature.jobMaker.instantiate("j1").tag]
}

/// A person's call: every plain place and plain wrapper in one closure, two staged closures.
func handWritten(ctx: Ctx) -> Feature {
	Feature(
		analytics: Analytics(name: "an"),
		config: Config(name: "cfg"),
		serviceBuilder: { _ in Impl(tag: "hand:\(ctx.name)") },
		serviceBuilder_job: { _ in { _ in Impl(tag: "hand-job") } },
		serviceBuilder_jobMaker: { outer in
			let analytics = outer.analytics
			return { _, name in Impl(tag: "hand-\(name):\(analytics.name)") }
		},
	)
}

/// The generated caller: one fill per place, one dispatcher per enum, staged fills as today.
func generated(ctx: Ctx) -> Feature {
	let analytics = Analytics(name: "an")
	func __safeDI_config() -> Config { Config(name: "cfg") }
	let config = LazilyInstantiated<Config>(__safeDI_config)
	func __safeDI_feature() -> Feature {
		func __safeDI_serviceBuilder_Feature_a_service(_ scope: Feature.SafeDIScope_Service.a_service_Values) -> any Service {
			let analytics = scope.analytics
			builds.append("a")
			return Impl(tag: "a:\(ctx.name):\(analytics.name):\(config.instance.name)")
		}
		func __safeDI_serviceBuilder_Feature_lazy(_ scope: Feature.SafeDIScope_Service.lazy_Values) -> any Service {
			builds.append("lazy")
			return Impl(tag: "lazy:\(ctx.name)")
		}
		func __safeDI_serviceBuilder_Feature_maker(_ scope: Feature.SafeDIScope_Service.maker_Values, _ __safeDI_forwarded: String) -> any Service {
			let name = __safeDI_forwarded
			return Impl(tag: "made-\(name):\(ctx.name)")
		}
		func __safeDI_serviceBuilder_Feature(_ scope: Feature.SafeDIScope_Service) -> any Service {
			switch scope {
			case let .a_service(scope): __safeDI_serviceBuilder_Feature_a_service(scope)
			case let .lazy(scope): __safeDI_serviceBuilder_Feature_lazy(scope)
			case let .maker(scope, __safeDI_forwarded): __safeDI_serviceBuilder_Feature_maker(scope, __safeDI_forwarded)
			}
		}
		func __safeDI_serviceBuilder_Feature_job(_ scope: Feature.SafeDIScope_Service_job.Outer) -> @Sendable (Feature.SafeDIScope_Service_job.Inner) -> any Service {
			let analytics = scope.analytics
			@Sendable func __safeDI_serviceBuilder_Feature_job_Inner(_ scope: Feature.SafeDIScope_Service_job.Inner) -> any Service {
				builds.append("job")
				return Impl(tag: "job:\(analytics.name)")
			}
			return __safeDI_serviceBuilder_Feature_job_Inner
		}
		func __safeDI_serviceBuilder_Feature_jobMaker(_ scope: Feature.SafeDIScope_Service_jobMaker.Outer) -> @Sendable (Feature.SafeDIScope_Service_jobMaker.Inner, String) -> any Service {
			let analytics = scope.analytics
			@Sendable func __safeDI_serviceBuilder_Feature_jobMaker_Inner(_ scope: Feature.SafeDIScope_Service_jobMaker.Inner, _ __safeDI_forwarded: String) -> any Service {
				let name = __safeDI_forwarded
				return Impl(tag: "jobmade-\(name):\(analytics.name)")
			}
			return __safeDI_serviceBuilder_Feature_jobMaker_Inner
		}
		return Feature(__safeDI_analytics: analytics, __safeDI_config: config.instance, __safeDI_serviceBuilder: __safeDI_serviceBuilder_Feature, __safeDI_serviceBuilder_job: __safeDI_serviceBuilder_Feature_job, __safeDI_serviceBuilder_jobMaker: __safeDI_serviceBuilder_Feature_jobMaker)
	}
	return __safeDI_feature()
}

@main struct Main {
	static func main() {
		let ctx = Ctx()
		print(tags(handWritten(ctx: ctx)))
		let before = Config.created
		let feature = generated(ctx: ctx)
		print("config created at the call: \(Config.created - before), builds before any read: \(builds)")
		print(tags(feature))
		print("builds: \(builds), config created: \(Config.created - before)")
	}
}
