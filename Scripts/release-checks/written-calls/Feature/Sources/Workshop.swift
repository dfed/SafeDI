// From the manual’s “Generating a dependency tree per module”: holes held in instantiators, whose builders are the
// wrapper’s `Builder` type, and a hole held in a `Sendable` wrapper, filled by a `Sendable` builder.
import SafeDI

/// Conforms to `Instantiable` by hand, so no `@Instantiable` declaration fulfills it: a hole that forwards a `String`.
public final class Gadget: Instantiable {
	public typealias ForwardedProperties = String

	public init(name: String) {
		self.name = name
	}

	public let name: String
}

public protocol Maker {}

public protocol Reporter: Sendable {}

@Instantiable(generateDependencyTree: true)
public final class Workshop: Instantiable {
	public init(
		gadgetBuilder: Instantiator<Gadget>,
		makerBuilder: ErasedInstantiator<String, any Maker>,
		reporterBuilder: SendableErasedInstantiator<(), any Reporter>,
	) {
		self.gadgetBuilder = gadgetBuilder
		self.makerBuilder = makerBuilder
		self.reporterBuilder = reporterBuilder
	}

	@Instantiated private let gadgetBuilder: Instantiator<Gadget>
	@Instantiated(fulfilledByType: "AppMaker") private let makerBuilder: ErasedInstantiator<String, any Maker>
	@Instantiated(fulfilledByType: "AppReporter") private let reporterBuilder: SendableErasedInstantiator<(), any Reporter>
}
