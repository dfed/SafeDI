// Hand-written calls of the declarations SafeDI generates, in the forms the manual documents.
import Core
import Feature
import Feed
import Payments
import SafeDI

// MARK: Roots

// “Creating the root of your dependency tree”: a root’s generated `init()`, of this module’s roots and of a root in a
// module this one depends on.
func makeRoots() {
	let _: NavigatorRoot = NavigatorRoot()
	let _: NotesApp = NotesApp()
	let _: FeatureRoot = FeatureRoot()
}

// “Attributes for generated declarations”: a root’s `init()` bound to the main actor by `generatedInitializerAttributes`.
@MainActor
func makeMainRoot() -> MainRoot {
	MainRoot()
}

// MARK: Seams

func callSeams(user: User, database: Database, logger: Logger, analytics: Analytics, session: Session, exportService: ExportService) {
	// “Generating a dependency tree per module”: `Screen(user:database:logger:)`, with a value or `nil` for the
	// parameter received only if available.
	let _: Screen = Screen(user: user, database: database, logger: logger)
	let _: Screen = Screen(user: user, database: database, logger: nil)

	// “Generating a dependency tree per module”: the `public` tier, and the `package` tier that also takes `theme`.
	let _: BadgeService = BadgeService(analytics: analytics)
	let _: BadgeService = BadgeService(analytics: analytics, theme: Theme())

	// “Generating a dependency tree per module”: a hand-written call fills a builder that takes nothing, verbatim.
	let _: ExportFeature = ExportFeature(exportService: exportService, uploaderBuilder: {
		DefaultUploader(jobBuilder: Instantiator { UploadJob(exportService: exportService) })
	})

	// “Adopting SafeDI in a large codebase”: a hand-written call of `FeedScreen`, whose hole’s builder takes nothing.
	let _: FeedScreen = FeedScreen(session: session, feedServiceBuilder: { AppFeedService(session: session) })

	// “Generating a dependency tree per module”: a builder that takes nothing, as a closure and as an `init` reference.
	let _: AccountService = AccountService(profileStoreBuilder: { DefaultProfileStore() })
	let _: AccountService = AccountService(profileStoreBuilder: DefaultProfileStore.init)

	// “Generating a dependency tree per module”: a seam that calls another seam whose holes it cannot fill takes
	// builders for them too, of the same forms, so a caller never writes anything else.
	let _: AccountHub = AccountHub(profileStoreBuilder: { DefaultProfileStore() })
	let _: AccountHub = AccountHub(profileStoreBuilder: DefaultProfileStore.init)

	// “Generating a dependency tree per module”: the builder of places held in instantiators is the wrapper’s
	// `Builder`, which is handed the forwarded value; a place in a `Sendable` wrapper has a `Sendable` builder; and a
	// builder of a place `fulfilledByType:` fills is labeled `<fulfilling type>_<type>Builder`.
	let _: Workshop = Workshop(
		appMaker_MakerBuilder: { name in AppMaker(name: name) },
		appReporter_ReporterSendableBuilder: { AppReporter() },
		gadgetBuilder: { name in Gadget(name: name) },
	)

	// “Adopting SafeDI in a large codebase”: an app target calls a seam that takes a `@Forwarded` property.
	let _: AppEntry = AppEntry(configuration: LaunchConfiguration(environment: "production"))
}

// MARK: Mocks

#if DEBUG
func callMocks() {
	// “Using generated mocks”: a mock that can build every dependency, called without arguments.
	let _: DefaultUserService = DefaultUserService.mock()

	// “Overriding dependencies”: all three buckets in one call, verbatim.
	let _: LoggedInView = LoggedInView.mock(
		user: User(name: "dfed"),
		safeDIOverrides: .init(
			noteStorage: .init(defaultNote: "dfed says hello"),
			userService: StubUserService.init,
		),
	)

	// “Overriding dependencies”: a literal closure and an `init` reference, verbatim.
	let _: LoggedInView = LoggedInView.mock(
		user: User(name: "dfed"),
		safeDIOverrides: .init(
			stringStorage: { InMemoryStorage() },
			userService: StubUserService.init,
		),
	)

	// “Overriding dependencies”: a nested `SafeDIMockConfiguration` field, and its builder in parentheses, verbatim.
	let _: LoggedInView = LoggedInView.mock(
		user: User(name: "dfed"),
		safeDIOverrides: .init(noteStorage: .init(defaultNote: "Welcome back")),
	)
	let _: LoggedInView = LoggedInView.mock(
		user: User(name: "dfed"),
		safeDIOverrides: .init(noteStorage: .init(StubNoteStorage.init)),
	)

	// “Overriding dependencies”: a labeled default-valued `@autoclosure` parameter takes a value.
	let _: Retrier = Retrier.mock(retries: 5)
	let _: Retrier = Retrier.mock()

	// “Receiving a type-erased dependency”: the mocked type’s own erased entry, and an entry on a nested configuration.
	let _: NotesApp = NotesApp.mock(safeDIOverrides: .init(userService: { stringStorage in
		AnyUserService(StubUserService(stringStorage: stringStorage))
	}))
	let _: ArchiveView = ArchiveView.mock(
		user: User(name: "dfed"),
		safeDIOverrides: .init(archive: .init(userService: { stringStorage in
			AnyUserService(StubUserService(stringStorage: stringStorage))
		})),
	)

	// “Receiving a type-erased dependency”: a required flat parameter where parents erase different types, verbatim.
	let _: SettingsView = SettingsView.mock(userService: AnyUserService(StubUserService(stringStorage: InMemoryStorage())))

	// “Dependency kinds in the generated mock” and “The `mockOnly` parameter”: a flat parameter that defaults to a
	// hand-written mock, left out and passed.
	let _: ConfiguredView = ConfiguredView.mock()
	let _: ConfiguredView = ConfiguredView.mock(configuration: AppConfiguration(environment: "test"))

	// “Dependency kinds in the generated mock”: an entry received only if available, typed as optional.
	let _: GuestFeedView = GuestFeedView.mock()
	let _: GuestFeedView = GuestFeedView.mock(safeDIOverrides: .init(user: User(name: "guest")))

	// “Dependency kinds in the generated mock”: a lazily instantiated dependency’s entry is a closure that returns
	// the instance.
	let _: ReportScreen = ReportScreen.mock(safeDIOverrides: .init(reportService: { ReportService() }))

	// “Dependency kinds in the generated mock”: a dependency instantiated only if available that a declaration
	// fulfills is built, and an entry named after its label with `IsUnavailable` binds it to `nil`.
	let _: ReportSummaryScreen = ReportSummaryScreen.mock()
	let _: ReportSummaryScreen = ReportSummaryScreen.mock(safeDIOverrides: .init(analyticsIsUnavailable: true))

	// “Dependency kinds in the generated mock”, under “Names”: two flat parameters that share a label.
	let _: ItemsView = ItemsView.mock(items_Set__String: ["b"], items_Array_String: ["a"])

	// “Hand-written mocks”: the generated `mock()` calls through to the method `customMockName` names.
	let _: NetworkClient = NetworkClient.mock()

	// “Overriding dependencies”: beneath a `Sendable` wrapper the caller still writes a value.
	let _: SyncRoot = SyncRoot.mock(remote: RemoteService())

	// “Cross-module mock generation”: a mock `additionalMocksToGenerate` generates in this module.
	let _: Database = Database.mock()

	// “Public mocks”: the `package` tier, from a module of the same package, which also takes `session`.
	let _: PaymentService = PaymentService.mock(session: PaymentSession())
	let _: PaymentService = PaymentService.mock(retries: 5, analytics: LazilyInstantiated { Analytics() }, session: PaymentSession(), safeDIOverrides: .init(tokenCache: .init(capacity: 5)))
}

// “Overriding dependencies”: the fields of `SafeDIOverrides` and `SafeDIMockConfiguration` are read-only, so an
// initializer written in an extension of one calls `self.init(…)`.
extension LoggedInView.SafeDIOverrides {
	init(welcome: String) {
		self.init(noteStorage: NoteStorage.SafeDIMockConfiguration(welcome: welcome))
	}
}

extension NoteStorage.SafeDIMockConfiguration {
	init(welcome: String) {
		self.init(defaultNote: welcome)
	}
}

func callMockWithOverridesValue() {
	let overrides: LoggedInView.SafeDIOverrides = .init(welcome: "Welcome back")
	let _: LoggedInView = LoggedInView.mock(user: User(name: "dfed"), safeDIOverrides: overrides)
}

// “Attributes for generated declarations”: a mock bound to the main actor by `mockAttributes`.
@MainActor
func makePresenterMock() -> MyPresenter {
	MyPresenter.mock()
}

// “Dependencies instantiated only if available”: a mock whose module sees a type that fulfills a dependency a public mock
// it calls takes a builder for builds that type, and takes an optional builder that replaces it.
func callOptionalBuilderFillingMocks() {
	let _: AppTrackerScreen = AppTrackerScreen.mock()
	let _: AppTrackerScreen = AppTrackerScreen.mock(feedAnalyticsOptionalBuilder: { AppFeedAnalytics() })
	let _: AppTrackerScreen = AppTrackerScreen.mock(feedAnalyticsOptionalBuilder: { nil })
}
#endif
