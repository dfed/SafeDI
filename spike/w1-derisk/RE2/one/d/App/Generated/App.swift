import Feature
import Harness
import SafeDI

extension Root {
	public convenience init() {
		let logger = Logger()
		// The dispatcher fixed point: the root level function takes the value its fill reads; the root passes its own
		// (logger), the re-entry from X's level passes X's.
		func __safeDI_gadgetBuilder_Service(logger: Logger) -> Service.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
			.init(
				gadget: { _ in LiveGadget(logger: logger) },
				xBuilder: { _ in __safeDI_gadgetBuilder_Service_X() },
			)
		}
		func __safeDI_gadgetBuilder_Service_X() -> Service.SafeDIScope_Gadget.X_Scope.__safeDI_Builder<any Gadget> {
			.init(serviceBuilder: { values in __safeDI_gadgetBuilder_Service(logger: values.logger) })
		}
		let service = Service(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Service(logger: logger))
		self.init(logger: logger, service: service)
	}
}
