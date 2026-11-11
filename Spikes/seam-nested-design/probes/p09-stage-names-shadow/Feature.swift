// Today's stage struct names shadow user types named `Inner` and `Outer` inside the scope type.
import SafeDI

public final class Inner: Sendable { public init() {} }
public final class Outer: Sendable { public init() {} }
public protocol H: Sendable {}
public final class Feature { init() {} }
extension Feature {
	public enum SafeDIScope_H_job {
		public struct Outer { public let inner: Inner; public let outer: Outer }
		public struct Inner {}
	}

	public convenience init(inner: Inner, outer: Outer, hBuilder_job: @escaping (SafeDIScope_H_job.Outer) -> @Sendable (SafeDIScope_H_job.Inner) -> any H) {
		_ = hBuilder_job(SafeDIScope_H_job.Outer(inner: inner, outer: outer))
		self.init()
	}
}
