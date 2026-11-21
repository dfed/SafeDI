// From the manual’s “Generating a dependency tree per module”: a seam that instantiates a `Profile`, which
// instantiates a protocol only module `App` implements. (The manual names the seam `Service` and the protocol
// `UserService`.)
import Core
import SafeDI

public protocol ProfileStore {}

@Instantiable(generateDependencyTree: true)
public final class AccountService: Instantiable {
	public init(analytics: Analytics, profile: Profile) {
		self.analytics = analytics
		self.profile = profile
	}

	@Instantiated private let analytics: Analytics
	@Instantiated private let profile: Profile
}

@Instantiable
public final class Profile: Instantiable {
	public init(profileStore: any ProfileStore, analytics: Analytics) {
		self.profileStore = profileStore
		self.analytics = analytics
	}

	@Instantiated private let profileStore: any ProfileStore
	@Received private let analytics: Analytics
}

/// A seam that calls another seam whose hole it cannot fill, and has a place of that hole of its own.
@Instantiable(generateDependencyTree: true)
public final class AccountHub: Instantiable {
	public init(account: AccountService, settings: AccountSettings) {
		self.account = account
		self.settings = settings
	}

	@Instantiated private let account: AccountService
	@Instantiated private let settings: AccountSettings
}

@Instantiable
public final class AccountSettings: Instantiable {
	public init(profileStore: any ProfileStore) {
		self.profileStore = profileStore
	}

	@Instantiated private let profileStore: any ProfileStore
}
