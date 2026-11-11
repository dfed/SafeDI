// The caller side: a hand-written closure, and a fill as generated code would spell one. Excluded from formatting so that
// it stays the generated spelling.
// swiftformat:disable all
import Feature
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

func makeSendableHost() -> SendableHost {
	func __safeDI_fill(_ scope: SendableHost.SafeDIStagedScope_SendableActionPanel_part.Stage1) -> SendableHost.SafeDIStagedScope_SendableActionPanel_part.LastStage<SendableActionPanel.ForwardedProperties> {
		let analytics = scope.analytics
		@Sendable func __safeDI_fill_Stage2(_ scope: SendableHost.SafeDIStagedScope_SendableActionPanel_part.Stage2, _ __safeDI_forwarded: @escaping SendableActionPanel.ForwardedProperties) -> SendableActionPanel {
			@Sendable func __safeDI_part(forwardedAction: @escaping @Sendable () -> Void) -> DefaultSendableActionPanel {
				DefaultSendableActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			}
			return __safeDI_part(forwardedAction: __safeDI_forwarded)
		}
		return __safeDI_fill_Stage2
	}
	return SendableHost(sendableActionPanelBuilder_part: __safeDI_fill)
}

func makeOwnerHost() -> OwnerHost {
	func __safeDI_fill(_ scope: OwnerHost.SafeDIStagedScope_ActionPanel_ownerBuilder_held.Stage1) -> OwnerHost.SafeDIStagedScope_ActionPanel_ownerBuilder_held.LastStage<ActionPanel.ForwardedProperties> {
		let analytics = scope.analytics
		@Sendable func __safeDI_fill_Stage2(_ scope: OwnerHost.SafeDIStagedScope_ActionPanel_ownerBuilder_held.Stage2, _ __safeDI_forwarded: @escaping ActionPanel.ForwardedProperties) -> ActionPanel {
			func __safeDI_held(forwardedAction: @escaping () -> Void) -> DefaultActionPanel {
				DefaultActionPanel(forwardedAction: forwardedAction, analytics: analytics)
			}
			return __safeDI_held(forwardedAction: __safeDI_forwarded)
		}
		return __safeDI_fill_Stage2
	}
	return OwnerHost(actionPanelBuilder_ownerBuilder_held: __safeDI_fill)
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
		let sendableCounter = Counter()
		let sendablePanel = makeSendableHost().part.instantiate { @Sendable in sendableCounter.increment() }
		guard let sendableDefault = sendablePanel as? DefaultSendableActionPanel else { fatalError("SendableHost built another panel") }
		expectCalledTwice("SendableHost", sendableCounter, sendablePanel.action, sendableDefault.forwardedAction)

		let handWrittenCounter = Counter()
		let handWritten = SendableHost(sendableActionPanelBuilder_part: { _ in
			{ @Sendable _, action in SendableActionPanel(action: action) }
		})
		let handWrittenPanel = handWritten.part.instantiate { @Sendable in handWrittenCounter.increment() }
		expectCalledTwice("Hand-written", handWrittenCounter, handWrittenPanel.action, handWrittenPanel.action)

		let ownerCounter = Counter()
		let ownerPanel = makeOwnerHost().ownerBuilder.instantiate().held.instantiate { ownerCounter.increment() }
		guard let ownerDefault = ownerPanel as? DefaultActionPanel else { fatalError("OwnerHost built another panel") }
		expectCalledTwice("OwnerHost", ownerCounter, ownerPanel.action, ownerDefault.forwardedAction)
	}
}
