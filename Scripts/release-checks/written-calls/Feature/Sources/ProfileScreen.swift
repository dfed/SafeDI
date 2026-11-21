// From the manual’s “Dependency kinds in the generated mock”, under “One parameter, several types”: two types
// instantiate a dependency from a type this module cannot see, so the mock takes one value for both, and an override
// of one type is handed the value the mock would use. (The manual names the types `Screen`, `Profile` and `Settings`.)
import SafeDI

/// A concrete existential that a `ProfileStore` is erased to.
public struct AnyProfileStore {
	public init(_ store: some ProfileStore) {
		self.store = store
	}

	private let store: any ProfileStore
}

@Instantiable(generateMock: true)
public struct ProfileScreen: Instantiable {
	public init(profile: ProfilePanel, settings: SettingsPanel) {
		self.profile = profile
		self.settings = settings
	}

	@Instantiated private let profile: ProfilePanel
	@Instantiated private let settings: SettingsPanel
}

@Instantiable
public struct ProfilePanel: Instantiable {
	public init(profileStore: AnyProfileStore) {
		self.profileStore = profileStore
	}

	/// `AppProfileStore` is declared in module `App`, which this module does not depend on.
	@Instantiated(fulfilledByType: "AppProfileStore", erasedToConcreteExistential: true) private let profileStore: AnyProfileStore
}

@Instantiable
public struct SettingsPanel: Instantiable {
	public init(profileStore: AnyProfileStore) {
		self.profileStore = profileStore
	}

	@Instantiated(fulfilledByType: "AppProfileStore", erasedToConcreteExistential: true) private let profileStore: AnyProfileStore
}
