// Hand-written. The nested cycle with no `indirect` at all.
public final class SeamA {}
public final class SeamB {}

extension SeamA {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)
		case bBuilder(SeamB.SafeDIScope_Service)

		public struct service_Values {}
	}
}

extension SeamB {
	@frozen public enum SafeDIScope_Service {
		case service(service_Values)
		case a(SeamA.SafeDIScope_Service)

		public struct service_Values {}
	}
}
