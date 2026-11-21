import SafeDI

@Instantiable(generateMock: true)
public final class Screen8 {
	public init(id: String, service: Service, context: Context?, screen2Builder: Instantiator<Screen2>, screen3Builder: Instantiator<Screen3>, screen10Builder: Instantiator<Screen10>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen2Builder = screen2Builder
		self.screen3Builder = screen3Builder
		self.screen10Builder = screen10Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received(onlyIfAvailable: true) let context: Context?
	@Instantiated let screen2Builder: Instantiator<Screen2>
	@Instantiated let screen3Builder: Instantiator<Screen3>
	@Instantiated let screen10Builder: Instantiator<Screen10>
}
