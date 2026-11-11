import SafeDI

public final class Inner: Sendable { public init() {} }
public final class Outer: Sendable { public init() {} }
public final class Stage1: Sendable { public init() {} }
public final class a_service_Values: Sendable { public init() {} }
public protocol Service: Sendable {}
public protocol Service_Sendable: Sendable {}
public protocol ServiceSendable: Sendable {}
public final class Impl: Sendable {}
public struct AnyService: Sendable {}
public final class Lower {}
extension Lower {
	@frozen
	public enum SafeDIScope_Service { case service(service_Values); public struct service_Values {} }
	@frozen
	public enum SafeDISendableScope_Service { case job(Lower.SafeDIScope_Service) }
}

public final class Feature { init() {} }
extension Feature {
	// Hole type (Service, any Service), both families.
	@frozen
	public enum SafeDIScope_Service_Service {
		case a_service(a_service_Values_)
		case Sendable(Sendable_Values)
		case lower(Lower.SafeDIScope_Service)
		// Named apart from the type its field names.
		public struct a_service_Values_ { public let values: a_service_Values; public let inner: Inner }
		public struct Sendable_Values {}
	}

	@frozen
	public enum SafeDISendableScope_Service_Service {
		case lower(Lower.SafeDIScope_Service)
		case lower_Sendable(Lower.SafeDISendableScope_Service)
	}

	// A staged place labeled `Sendable`, and one whose stage holds user types named Inner, Outer and Stage1.
	public enum SafeDIStagedScope_Service_Service_Sendable {
		public struct Stage1_ { public let inner: Inner; public let outer: Outer; public let stage: Stage1 }
		public struct Stage2 {}
	}

	// Hole types (Service_Sendable, any Service_Sendable) and (ServiceSendable, any ServiceSendable): the second's plain label equals
	// Service's @Sendable label, so both of those hole types are named by the ladder.
	@frozen
	public enum SafeDIScope_Service_Sendable { case x(x_Values); public struct x_Values {} }
	@frozen
	public enum SafeDIScope_ServiceSendable_ServiceSendable { case y(y_Values); public struct y_Values {} }
	// Two hole types of one instantiated type: (Impl, Impl) and (Impl, AnyService), both by the ladder.
	@frozen
	public enum SafeDIScope_Impl_Impl { case impl(impl_Values); public struct impl_Values {} }
	@frozen
	public enum SafeDIScope_Impl_AnyService { case erased(erased_Values); public struct erased_Values {} }

	public convenience init(
		impl_AnyServiceBuilder _: @escaping (SafeDIScope_Impl_AnyService) -> AnyService,
		impl_ImplBuilder _: @escaping (SafeDIScope_Impl_Impl) -> Impl,
		service_ServiceBuilder: @escaping (SafeDIScope_Service_Service) -> any Service,
		service_ServiceSendableBuilder _: @escaping @Sendable (SafeDISendableScope_Service_Service) -> any Service,
		service_ServiceBuilder_Sendable: @escaping (SafeDIStagedScope_Service_Service_Sendable.Stage1_) -> @Sendable (SafeDIStagedScope_Service_Service_Sendable.Stage2) -> any Service,
		serviceSendable_ServiceSendableBuilder _: @escaping (SafeDIScope_ServiceSendable_ServiceSendable) -> any ServiceSendable,
		service_SendableBuilder _: @escaping (SafeDIScope_Service_Sendable) -> any Service_Sendable,
	) {
		_ = service_ServiceBuilder(.a_service(SafeDIScope_Service_Service.a_service_Values_(values: a_service_Values(), inner: Inner())))
		_ = service_ServiceBuilder(.Sendable(SafeDIScope_Service_Service.Sendable_Values()))
		_ = service_ServiceBuilder_Sendable(SafeDIStagedScope_Service_Service_Sendable.Stage1_(inner: Inner(), outer: Outer(), stage: Stage1()))
		self.init()
	}
}
