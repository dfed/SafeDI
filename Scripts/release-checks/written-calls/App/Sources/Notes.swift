// The types of the manual’s running example (“@Instantiable”, “Making protocols `@Instantiable`”, “Overriding
// dependencies”, “Receiving a type-erased dependency”), without SwiftUI, so that the check compiles on Linux.
import Core
import SafeDI

public protocol UserService: AnyObject {
	var user: User? { get set }
}

@Instantiable(fulfillingAdditionalTypes: [UserService.self], generateMock: true)
public final class DefaultUserService: UserService, Instantiable {
	public init(stringStorage: StringStorage) {
		self.stringStorage = stringStorage
	}

	public var user: User?

	@Received private let stringStorage: StringStorage
}

/// A concrete existential wrapper around `UserService`.
public final class AnyUserService: UserService {
	public init(_ userService: some UserService) {
		self.userService = userService
	}

	public var user: User? {
		get { userService.user }
		set { userService.user = newValue }
	}

	private let userService: any UserService
}

/// A second type erased to `AnyUserService`, so that a mock that receives `AnyUserService` cannot build it.
@Instantiable
public final class OfflineUserService: UserService, Instantiable {
	public init() {}

	public var user: User?
}

@Instantiable(isRoot: true, generateMock: true)
public final class NotesApp: Instantiable {
	public init(stringStorage: StringStorage, userService: AnyUserService) {
		self.stringStorage = stringStorage
		self.userService = userService
	}

	@Instantiated private let stringStorage: StringStorage
	@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) private let userService: AnyUserService
}

@Instantiable
public final class OfflineView: Instantiable {
	public init(userService: AnyUserService) {
		self.userService = userService
	}

	@Instantiated(fulfilledByType: "OfflineUserService", erasedToConcreteExistential: true) private let userService: AnyUserService
}

@Instantiable(generateMock: true)
public final class SettingsView: Instantiable {
	public init(userService: AnyUserService) {
		self.userService = userService
	}

	@Received private let userService: AnyUserService
}

@Instantiable(generateMock: true)
public struct LoggedInView: Instantiable {
	public init(user: User, userService: UserService, noteStorage: NoteStorage) {
		self.user = user
		self.userService = userService
		self.noteStorage = noteStorage
	}

	@Forwarded private let user: User
	@Received private let userService: UserService
	@Instantiated private let noteStorage: NoteStorage
}

@Instantiable
public class NoteStorage: Instantiable {
	public init(user: User, stringStorage: StringStorage, defaultNote: String = "") {
		self.user = user
		self.stringStorage = stringStorage
		self.defaultNote = defaultNote
	}

	@Received private let user: User
	@Received private let stringStorage: StringStorage

	private let defaultNote: String
}

/// “Receiving a type-erased dependency”: a type beneath the mocked type instantiates the erased dependency, so its
/// entry is on that type’s `SafeDIMockConfiguration`.
@Instantiable(generateMock: true)
public struct ArchiveView: Instantiable {
	public init(user: User, archive: ArchiveStorage) {
		self.user = user
		self.archive = archive
	}

	@Forwarded private let user: User
	@Instantiated private let archive: ArchiveStorage
}

@Instantiable
public final class ArchiveStorage: Instantiable {
	public init(stringStorage: StringStorage, userService: AnyUserService) {
		self.stringStorage = stringStorage
		self.userService = userService
	}

	@Received private let stringStorage: StringStorage
	@Instantiated(fulfilledByType: "DefaultUserService", erasedToConcreteExistential: true) private let userService: AnyUserService
}

// Test doubles a test writes.

final class StubUserService: UserService {
	init(stringStorage: StringStorage) {
		self.stringStorage = stringStorage
	}

	var user: User?

	private let stringStorage: StringStorage
}

final class InMemoryStorage: StringStorage {
	func string(forKey _: String) -> String? {
		nil
	}
}

/// “Overriding dependencies”: a subclass of `NoteStorage` whose `init` matches `NoteStorage.init`.
final class StubNoteStorage: NoteStorage {
	override init(user: User, stringStorage: StringStorage, defaultNote: String = "") {
		super.init(user: user, stringStorage: stringStorage, defaultNote: defaultNote)
	}
}
