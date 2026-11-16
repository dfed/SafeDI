import Harness
import SafeDI

extension Service {
	nonisolated public enum SafeDIScope_Gadget {
		nonisolated public struct gadget_Values {}

		nonisolated public struct xBuilder_Values {}

		nonisolated public struct __safeDI_Builder<Built> {
			public let gadget: (gadget_Values) -> Built
			public let xBuilder: (xBuilder_Values) -> X_Scope.__safeDI_Builder<Built>

			public init(gadget: @escaping (gadget_Values) -> Built, xBuilder: @escaping (xBuilder_Values) -> X_Scope.__safeDI_Builder<Built>) {
				self.gadget = gadget
				self.xBuilder = xBuilder
			}

			public init(__safeDI_noScope builder: @escaping () -> Built) {
				gadget = { _ in builder() }
				xBuilder = { _ in .init(__safeDI_noScope: builder) }
			}
		}

		nonisolated public enum X_Scope {
			nonisolated public struct serviceBuilder_Values {
				public let logger: Logger
			}

			nonisolated public struct __safeDI_Builder<Built> {
				public let serviceBuilder: (serviceBuilder_Values) -> SafeDIScope_Gadget.__safeDI_Builder<Built>

				public init(serviceBuilder: @escaping (serviceBuilder_Values) -> SafeDIScope_Gadget.__safeDI_Builder<Built>) {
					self.serviceBuilder = serviceBuilder
				}

				public init(__safeDI_noScope builder: @escaping () -> Built) {
					serviceBuilder = { _ in .init(__safeDI_noScope: builder) }
				}
			}
		}
	}

	/// For code you write.
	public convenience init(gadgetBuilder: @escaping () -> any Gadget) {
		self.init(__safeDI_gadgetBuilder: .init(__safeDI_noScope: gadgetBuilder))
	}

	/// Only code SafeDI generates calls this initializer.
	public convenience init(__safeDI_gadgetBuilder: SafeDIScope_Gadget.__safeDI_Builder<any Gadget>) {
		// Per-type: X's function takes X's level struct; the re-entering call hands Service the struct X's member
		// returns (candidate B), which carries X's logger.
		func __safeDI_x(_ __safeDI_gadgetBuilder: SafeDIScope_Gadget.X_Scope.__safeDI_Builder<any Gadget>) -> X {
			let logger = Logger()
			func __safeDI_serviceBuilder() -> Service {
				Service(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder.serviceBuilder(.init(logger: logger)))
			}
			let serviceBuilder = Instantiator<Service>(__safeDI_serviceBuilder)
			return X(logger: logger, serviceBuilder: serviceBuilder)
		}
		let gadget: any Gadget = __safeDI_gadgetBuilder.gadget(.init())
		func __safeDI_xBuilder() -> X {
			__safeDI_x(__safeDI_gadgetBuilder.xBuilder(.init()))
		}
		let xBuilder = Instantiator<X>(__safeDI_xBuilder)
		self.init(gadget: gadget, xBuilder: xBuilder)
	}
}
