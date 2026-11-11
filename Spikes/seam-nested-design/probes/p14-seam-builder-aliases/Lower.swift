// The two public aliases of Sources/SafeDI/DelayedInstantiation/Instantiator.swift on branch
// dfed--claude/seam-builds-wrappers, copied word for word because the runtime this script builds predates them.
import SafeDI

extension Instantiator {
	public typealias SeamBuilder<Scope> = (Scope, T.ForwardedProperties) -> T
	public typealias SendableSeamBuilder<Scope> = @Sendable (Scope, T.ForwardedProperties) -> T
}
