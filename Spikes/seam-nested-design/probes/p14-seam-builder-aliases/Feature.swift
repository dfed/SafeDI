// The seam side, as SafeDIToolSeamBuiltWrapperTests expects it generated. Types conform by hand, as a type held in an
// Instantiator must, and forward one function. Excluded from formatting so that it stays the generated spelling.
// swiftformat:disable all
import Lower
import SafeDI

public final class Analytics: Sendable { public init() {} }

open class ActionPanel: Instantiable, @unchecked Sendable {
	public typealias ForwardedProperties = () -> Void
	public init(action: @escaping () -> Void) { self.action = action }
	public let action: () -> Void
}

open class SendableActionPanel: Instantiable, @unchecked Sendable {
	public typealias ForwardedProperties = @Sendable () -> Void
	public init(action: @escaping @Sendable () -> Void) { self.action = action }
	public let action: @Sendable () -> Void
}

public struct Host {
	public let analytics: Analytics
	public let part: Instantiator<ActionPanel>
	init(analytics: Analytics, part: Instantiator<ActionPanel>) { self.analytics = analytics; self.part = part }
}

extension Host {
	public struct SafeDIScope_Host_part {
		public let analytics: Analytics
	}

	// SeamBuilder as an escaping initializer parameter.
	public init(partBuilder: @escaping Instantiator<ActionPanel>.SeamBuilder<SafeDIScope_Host_part>) {
		let __safeDI_partBuilder = partBuilder
		let analytics = Analytics()
		let part = Instantiator<ActionPanel> {
			__safeDI_partBuilder(SafeDIScope_Host_part(analytics: analytics), $0)
		}
		self.init(analytics: analytics, part: part)
	}
}

public struct SendableHost {
	public let analytics: Analytics
	public let part: SendableInstantiator<SendableActionPanel>
	init(analytics: Analytics, part: SendableInstantiator<SendableActionPanel>) { self.analytics = analytics; self.part = part }
}

extension SendableHost {
	public enum SafeDIScope_SendableHost_part {
		public struct Outer {
			public let analytics: Analytics
		}

		public struct Inner {
			public init() {}
		}
	}

	// SendableSeamBuilder returned by the escaping parameter, as generated.
	public init(partBuilder: @escaping (SafeDIScope_SendableHost_part.Outer) -> Instantiator<SendableActionPanel>.SendableSeamBuilder<SafeDIScope_SendableHost_part.Inner>) {
		let __safeDI_partBuilder = partBuilder
		let analytics = Analytics()
		let __safeDI_partBuilder_Inner = __safeDI_partBuilder(SafeDIScope_SendableHost_part.Outer(analytics: analytics))
		let part = SendableInstantiator<SendableActionPanel> {
			__safeDI_partBuilder_Inner(SafeDIScope_SendableHost_part.Inner(), $0)
		}
		self.init(analytics: analytics, part: part)
	}

	// SendableSeamBuilder as the escaping parameter itself.
	public init(analytics: Analytics, sendablePartBuilder: @escaping Instantiator<SendableActionPanel>.SendableSeamBuilder<SafeDIScope_SendableHost_part.Inner>) {
		let part = SendableInstantiator<SendableActionPanel> {
			sendablePartBuilder(SafeDIScope_SendableHost_part.Inner(), $0)
		}
		self.init(analytics: analytics, part: part)
	}
}

public final class Owner: Instantiable, @unchecked Sendable {
	public let held: Instantiator<ActionPanel>
	init(held: Instantiator<ActionPanel>) { self.held = held }
}

public struct OwnerHost {
	public let analytics: Analytics
	public let ownerBuilder: SendableInstantiator<Owner>
	init(analytics: Analytics, ownerBuilder: SendableInstantiator<Owner>) { self.analytics = analytics; self.ownerBuilder = ownerBuilder }
}

extension OwnerHost {
	public enum SafeDIScope_Owner_held {
		public struct Outer {
			public let analytics: Analytics
		}

		public struct Inner {}
	}

	// A @Sendable function that captures the SendableSeamBuilder value.
	public init(heldBuilder: @escaping (SafeDIScope_Owner_held.Outer) -> Instantiator<ActionPanel>.SendableSeamBuilder<SafeDIScope_Owner_held.Inner>) {
		let __safeDI_heldBuilder = heldBuilder
		let analytics = Analytics()
		let __safeDI_heldBuilder_Inner = __safeDI_heldBuilder(SafeDIScope_Owner_held.Outer(analytics: analytics))
		@Sendable func __safeDI_ownerBuilder() -> Owner {
			let held = Instantiator<ActionPanel> {
				__safeDI_heldBuilder_Inner(SafeDIScope_Owner_held.Inner(), $0)
			}
			return Owner(held: held)
		}
		let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		self.init(analytics: analytics, ownerBuilder: ownerBuilder)
	}
}
