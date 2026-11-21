import SafeDI

@Instantiable(generateMock: true)
public final class Screen4 {
	public init(id: String, service: Service, context: Context?, screen0Builder: Instantiator<Screen0>, screen3Builder: Instantiator<Screen3>, screen7Builder: Instantiator<Screen7>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen0Builder = screen0Builder
		self.screen3Builder = screen3Builder
		self.screen7Builder = screen7Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received(onlyIfAvailable: true) let context: Context?
	@Instantiated let screen0Builder: Instantiator<Screen0>
	@Instantiated let screen3Builder: Instantiator<Screen3>
	@Instantiated let screen7Builder: Instantiator<Screen7>
}
