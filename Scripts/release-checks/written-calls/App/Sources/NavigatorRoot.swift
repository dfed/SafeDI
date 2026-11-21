// From the manual’s “Delayed instantiation”, “Instantiator”, “ErasedInstantiator” and “LazilyInstantiated”: a root
// whose hand-written methods call the wrappers SafeDI builds, through the `ForwardedProperties` each type forwards.
// It also reaches `Feed`’s seam, so its generated code calls that seam and fills its hole.
import Core
import Feed
import SafeDI

@Instantiable
public struct NameEntry: Instantiable {
	public init() {}
}

/// Forwards two properties, so `Instantiator<Compose>.instantiate(_:)` takes them as one tuple, ordered by label.
@Instantiable
public struct Compose: Instantiable {
	public init(name: String, count: Int) {
		self.name = name
		self.count = count
	}

	@Forwarded private let name: String
	@Forwarded private let count: Int
}

@Instantiable
public struct ChildView: Instantiable {
	public init() {}
}

/// A concrete existential that `ChildView` is erased to.
public struct AnyChild {
	public init(_ child: ChildView) {
		self.child = child
	}

	private let child: ChildView
}

@Instantiable(isRoot: true)
public final class NavigatorRoot: Instantiable {
	public init(
		stringStorage: StringStorage,
		userService: UserService,
		session: Session,
		feedScreen: FeedScreen,
		loggedInViewBuilder: Instantiator<LoggedInView>,
		nameEntryBuilder: Instantiator<NameEntry>,
		composeBuilder: Instantiator<Compose>,
		childViewBuilder: ErasedInstantiator<(), AnyChild>,
		reportService: LazilyInstantiated<ReportService>,
	) {
		self.stringStorage = stringStorage
		self.userService = userService
		self.session = session
		self.feedScreen = feedScreen
		self.loggedInViewBuilder = loggedInViewBuilder
		self.nameEntryBuilder = nameEntryBuilder
		self.composeBuilder = composeBuilder
		self.childViewBuilder = childViewBuilder
		self.reportService = reportService
	}

	func open(user: User) {
		let _: LoggedInView = loggedInViewBuilder.instantiate(user)
		let _: NameEntry = nameEntryBuilder.instantiate()
		let _: Compose = composeBuilder.instantiate((count: 1, name: "Draft"))
		let _: AnyChild = childViewBuilder.instantiate()
		let _: ReportService = reportService.instance
	}

	@Instantiated private let stringStorage: StringStorage
	@Instantiated private let userService: UserService
	@Instantiated private let session: Session
	@Instantiated private let feedScreen: FeedScreen
	@Instantiated private let loggedInViewBuilder: Instantiator<LoggedInView>
	@Instantiated private let nameEntryBuilder: Instantiator<NameEntry>
	@Instantiated private let composeBuilder: Instantiator<Compose>
	@Instantiated(fulfilledByType: "ChildView", erasedToConcreteExistential: true) private let childViewBuilder: ErasedInstantiator<(), AnyChild>
	@Instantiated private let reportService: LazilyInstantiated<ReportService>
}
