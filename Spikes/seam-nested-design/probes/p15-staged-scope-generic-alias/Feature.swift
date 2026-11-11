// The seam side, as the nested builders' generated code would spell a staged place that forwards a function: the last stage
// is a generic typealias inside the staged scope type, so the forwarded value's parameter is spelled by a generic parameter,
// never by a function type. Excluded from formatting so that it stays the generated spelling.
// swiftformat:disable all
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

public struct SendableHost {
	public let analytics: Analytics
	public let part: SendableInstantiator<SendableActionPanel>
	init(analytics: Analytics, part: SendableInstantiator<SendableActionPanel>) { self.analytics = analytics; self.part = part }
}

extension SendableHost {
	public enum SafeDIStagedScope_SendableActionPanel_part {
		public struct Stage1 {
			public let analytics: Analytics
		}

		public struct Stage2 {}

		public typealias LastStage<Forwarded> = @Sendable (Stage2, Forwarded) -> SendableActionPanel
	}

	public init(sendableActionPanelBuilder_part: @escaping (SafeDIStagedScope_SendableActionPanel_part.Stage1) -> SafeDIStagedScope_SendableActionPanel_part.LastStage<SendableActionPanel.ForwardedProperties>) {
		let __safeDI_sendableActionPanelBuilder_part = sendableActionPanelBuilder_part
		let analytics = Analytics()
		let __safeDI_sendableActionPanelBuilder_part_Stage2 = __safeDI_sendableActionPanelBuilder_part(SafeDIStagedScope_SendableActionPanel_part.Stage1(analytics: analytics))
		let part = SendableInstantiator<SendableActionPanel> {
			__safeDI_sendableActionPanelBuilder_part_Stage2(SafeDIStagedScope_SendableActionPanel_part.Stage2(), $0)
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
	public enum SafeDIStagedScope_ActionPanel_ownerBuilder_held {
		public struct Stage1 {
			public let analytics: Analytics
		}

		public struct Stage2 {}

		public typealias LastStage<Forwarded> = @Sendable (Stage2, Forwarded) -> ActionPanel
	}

	// A @Sendable function captures the alias's value; a non-Sendable T's forwarded function still escapes.
	public init(actionPanelBuilder_ownerBuilder_held: @escaping (SafeDIStagedScope_ActionPanel_ownerBuilder_held.Stage1) -> SafeDIStagedScope_ActionPanel_ownerBuilder_held.LastStage<ActionPanel.ForwardedProperties>) {
		let __safeDI_builder = actionPanelBuilder_ownerBuilder_held
		let analytics = Analytics()
		let __safeDI_builder_Stage2 = __safeDI_builder(SafeDIStagedScope_ActionPanel_ownerBuilder_held.Stage1(analytics: analytics))
		@Sendable func __safeDI_ownerBuilder() -> Owner {
			let held = Instantiator<ActionPanel> {
				__safeDI_builder_Stage2(SafeDIStagedScope_ActionPanel_ownerBuilder_held.Stage2(), $0)
			}
			return Owner(held: held)
		}
		let ownerBuilder = SendableInstantiator<Owner>(__safeDI_ownerBuilder)
		self.init(analytics: analytics, ownerBuilder: ownerBuilder)
	}
}
