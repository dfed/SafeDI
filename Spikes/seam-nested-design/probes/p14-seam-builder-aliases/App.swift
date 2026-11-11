// The caller side, as SafeDIToolSeamBuiltWrapperTests expects it generated: each fill writes @escaping on the forwarded
// value, spelled through the type's ForwardedProperties. Excluded from formatting so that it stays the generated spelling.
// swiftformat:disable all
import Feature
import Lower
import SafeDI

final class DefaultActionPanel: ActionPanel, @unchecked Sendable {
	init(forwardedAction: @escaping () -> Void, analytics: Analytics) {
		self.forwardedAction = forwardedAction
		self.analytics = analytics
		super.init(action: forwardedAction)
	}

	let forwardedAction: () -> Void
	let analytics: Analytics
}

final class DefaultSendableActionPanel: SendableActionPanel, @unchecked Sendable {
	init(forwardedAction: @escaping @Sendable () -> Void, analytics: Analytics) {
		self.forwardedAction = forwardedAction
		self.analytics = analytics
		super.init(action: forwardedAction)
	}

	let forwardedAction: @Sendable () -> Void
	let analytics: Analytics
}

final class Counter: @unchecked Sendable {
	var count = 0
	func increment() { count += 1 }
}

func makeHost() -> Host {
	func __safeDI_partBuilder(_ scope: Host.SafeDIScope_Host_part, _ __safeDI_forwarded: @escaping ActionPanel.ForwardedProperties) -> ActionPanel {
		let analytics = scope.analytics
		func __safeDI_part(forwardedAction: @escaping () -> Void) -> DefaultActionPanel {
			DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
		}
		return __safeDI_part(forwardedAction: __safeDI_forwarded)
	}
	return Host(partBuilder: __safeDI_partBuilder)
}

func makeSendableHost() -> SendableHost {
	func __safeDI_partBuilder(_ scope: SendableHost.SafeDIScope_SendableHost_part.Outer) -> Instantiator<SendableActionPanel>.SendableSeamBuilder<SendableHost.SafeDIScope_SendableHost_part.Inner> {
		let analytics = scope.analytics
		@Sendable func __safeDI_partBuilder_Inner(_ scope: SendableHost.SafeDIScope_SendableHost_part.Inner, _ __safeDI_forwarded: @escaping SendableActionPanel.ForwardedProperties) -> SendableActionPanel {
			@Sendable func __safeDI_part(forwardedAction: @escaping @Sendable () -> Void) -> DefaultSendableActionPanel {
				DefaultSendableActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			}
			return __safeDI_part(forwardedAction: __safeDI_forwarded)
		}
		return __safeDI_partBuilder_Inner
	}
	return SendableHost(partBuilder: __safeDI_partBuilder)
}

func makeOwnerHost() -> OwnerHost {
	func __safeDI_heldBuilder(_ scope: OwnerHost.SafeDIScope_Owner_held.Outer) -> Instantiator<ActionPanel>.SendableSeamBuilder<OwnerHost.SafeDIScope_Owner_held.Inner> {
		let analytics = scope.analytics
		@Sendable func __safeDI_heldBuilder_Inner(_ scope: OwnerHost.SafeDIScope_Owner_held.Inner, _ __safeDI_forwarded: @escaping ActionPanel.ForwardedProperties) -> ActionPanel {
			func __safeDI_held(forwardedAction: @escaping () -> Void) -> DefaultActionPanel {
				DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			}
			return __safeDI_held(forwardedAction: __safeDI_forwarded)
		}
		return __safeDI_heldBuilder_Inner
	}
	return OwnerHost(heldBuilder: __safeDI_heldBuilder)
}

/// Calls each stored function after the initializer that received it has returned.
func expectCalledTwice(_ label: String, _ counter: Counter, _ first: () -> Void, _ second: () -> Void) {
	first()
	second()
	guard counter.count == 2 else {
		fatalError("\(label): expected 2 calls, got \(counter.count)")
	}
	print(label, "calls:", counter.count)
}

@main struct App {
	static func main() {
		let hostCounter = Counter()
		let hostPanel = makeHost().part.instantiate { hostCounter.increment() }
		guard let hostDefault = hostPanel as? DefaultActionPanel else { fatalError("Host built another panel") }
		expectCalledTwice("Host", hostCounter, hostPanel.action, hostDefault.forwardedAction)

		let sendableCounter = Counter()
		let sendablePanel = makeSendableHost().part.instantiate { @Sendable in sendableCounter.increment() }
		guard let sendableDefault = sendablePanel as? DefaultSendableActionPanel else { fatalError("SendableHost built another panel") }
		expectCalledTwice("SendableHost", sendableCounter, sendablePanel.action, sendableDefault.forwardedAction)

		let directCounter = Counter()
		let direct = SendableHost(analytics: Analytics(), sendablePartBuilder: { _, action in
			SendableActionPanel(action: action)
		})
		let directPanel = direct.part.instantiate { @Sendable in directCounter.increment() }
		expectCalledTwice("Direct SendableSeamBuilder", directCounter, directPanel.action, directPanel.action)

		let ownerCounter = Counter()
		let ownerPanel = makeOwnerHost().ownerBuilder.instantiate().held.instantiate { ownerCounter.increment() }
		guard let ownerDefault = ownerPanel as? DefaultActionPanel else { fatalError("OwnerHost built another panel") }
		expectCalledTwice("OwnerHost", ownerCounter, ownerPanel.action, ownerDefault.forwardedAction)
	}
}
