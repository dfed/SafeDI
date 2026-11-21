import SafeDI

@Instantiable(generateMock: true)
public final class Screen10 {
	public init(id: String, service: Service, context: Context?, screen2Builder: Instantiator<Screen2>, screen3Builder: Instantiator<Screen3>, screen6Builder: Instantiator<Screen6>) {
		self.id = id
		self.service = service
		self.context = context
		self.screen2Builder = screen2Builder
		self.screen3Builder = screen3Builder
		self.screen6Builder = screen6Builder
	}

	@Forwarded let id: String
	@Received let service: Service
	@Received(onlyIfAvailable: true) let context: Context?
	@Instantiated let screen2Builder: Instantiator<Screen2>
	@Instantiated let screen3Builder: Instantiator<Screen3>
	@Instantiated let screen6Builder: Instantiator<Screen6>
}
