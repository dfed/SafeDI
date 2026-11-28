// Distributed under the MIT License
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import SafeDICore
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// An internal mock root whose types declare renames (`@Received(fulfilledByDependencyNamed:ofType:)`), laid out from
/// the node records of its world (`NodeRecords+MockRename.swift`): each rename is bound where its type is built, from
/// the nearest declaration of its fulfilling label, or to `nil` where a rename only if available finds none, as the
/// mock's walk binds it, with the values the walk builds, with an override at every place.
struct SafeDIToolNodeRecordsMockRenameTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutRenamesAsTheWalkWritesThem_whenRootAndTypeBeneathItDeclareRenames() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(user: User, owner: User, profile: Profile) {
			        self.user = user
			        self.owner = owner
			        self.profile = profile
			    }

			    @Instantiated let user: User
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let owner: User
			    @Instantiated let profile: Profile
			}
			""",
			"""
			@Instantiable
			public final class User: Instantiable, Person {
			    public init() {}
			}

			public protocol Person {}

			public struct AnyPerson: Person {
			    public init(_ person: any Person) {
			        self.person = person
			    }

			    public let person: any Person
			}
			""",
			"""
			@Instantiable
			public final class Profile: Instantiable {
			    public init(account: User, person: AnyPerson, maybeUser: User?, maybePerson: AnyPerson?) {
			        self.account = account
			        self.person = person
			        self.maybeUser = maybeUser
			        self.maybePerson = maybePerson
			    }

			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let account: User
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self, erasedToConcreteExistential: true) let person: AnyPerson
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self, onlyIfAvailable: true) let maybeUser: User?
			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let maybePerson: AnyPerson?
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            profile: ((User, AnyPerson, User?, AnyPerson?) -> Profile)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                profile: profile
		            )
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var profile: ((User, AnyPerson, User?, AnyPerson?) -> Profile)? { __safeDI_storage.profile }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                profile: ((User, AnyPerson, User?, AnyPerson?) -> Profile)?
		            ) {
		                self.user = user
		                self.profile = profile
		            }

		            let user: (() -> User)?
		            let profile: ((User, AnyPerson, User?, AnyPerson?) -> Profile)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        #sourceLocation(file: "\(output.fixtures["Root.swift"])", line: 10)
		        let owner: User = user
		        #sourceLocation()
		        func __safeDI_profile() -> Profile {
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 10)
		            let account: User = user
		            #sourceLocation()
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 11)
		            let person: AnyPerson = AnyPerson(user)
		            #sourceLocation()
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 12)
		            let maybeUser: User? = user
		            #sourceLocation()
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 13)
		            let maybePerson: AnyPerson? = (user as User?).map { AnyPerson($0) }
		            #sourceLocation()
		            return if let safeDIBuilder = safeDIOverrides.profile { safeDIBuilder(account, person, maybeUser, maybePerson) } else { Profile(account: account, person: person, maybeUser: maybeUser, maybePerson: maybePerson) }
		        }
		        let profile: Profile = __safeDI_profile()
		        return Root(user: user, owner: owner, profile: profile)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == Self.mockFile(of: "Root", in: walkOutput, withFixturePathsOf: output, fixtureNames: ["Root.swift", "Profile.swift"]))
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsRootsRenameOnlyIfAvailableFromDependencyMockPromotes_whenTypeBeneathRootRequiresIt() async throws {
		// `Root` does not create `service`, which its rename only if available reads, but `Consumer` requires it, so the
		// mock promotes it to a child of the root, built before the rename, which reads it as the walk binds it.
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.promotedDependencyFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.promotedDependencyFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: (() -> Service)? = nil,
		            consumer: ((Service) -> Consumer)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                service: service,
		                consumer: consumer
		            )
		        }

		        var service: (() -> Service)? { __safeDI_storage.service }
		        var consumer: ((Service) -> Consumer)? { __safeDI_storage.consumer }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                service: (() -> Service)?,
		                consumer: ((Service) -> Consumer)?
		            ) {
		                self.service = service
		                self.consumer = consumer
		            }

		            let service: (() -> Service)?
		            let consumer: ((Service) -> Consumer)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
		        #sourceLocation(file: "\(output.fixtures["Root.swift"])", line: 8)
		        let maybeService: Service? = service
		        #sourceLocation()
		        let consumer = if let safeDIBuilder = safeDIOverrides.consumer { safeDIBuilder(service) } else { Consumer(service: service) }
		        return Root(maybeService: maybeService, consumer: consumer)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == Self.mockFile(of: "Root", in: walkOutput, withFixturePathsOf: output, fixtureNames: ["Root.swift"]))
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenRootsRenameOnlyIfAvailableReadsDependencyMockPromotes() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.promotedDependencyFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.promotedDependencyFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// The rename reads the `service` the mock promotes, built before it, so it is that instance, never `nil`.
		func reads(of root: String) -> String {
			"""
			{ let root = \(root); \
			return [root.maybeService == nil ? "no service" : "a service", \
			root.maybeService === root.consumer.service ? "one service" : "two services"] }()
			"""
		}
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: Self.promotedDependencyFixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: Self.promotedDependencyFixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe(name: "built root", expression: reads(of: "Root.mock()")),
				DifferentialValueProbe(name: "overridden root", expression: reads(of: "Root.mock(safeDIOverrides: .init(service: { Service() }))")),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		#expect(comparison.featureDescription.contains("one service"), "\(comparison.featureDescription)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_takesErasedNodesOverrideAsItsPropertysType_whenItsOnlyChildIsRename() async throws {
		// `thing` is erased to `AnyThing`, and `Thing`'s only dependency is a rename, which reads no override, so `thing`
		// has no configuration: its override is a closure that returns the property's type, which the node's function
		// returns as it is.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(user: User, thing: AnyThing) {
			        self.user = user
			        self.thing = thing
			    }

			    @Instantiated let user: User
			    @Instantiated(fulfilledByType: "Thing", erasedToConcreteExistential: true) let thing: AnyThing
			}
			""",
			"""
			@Instantiable
			public final class User: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Thing: Instantiable, Gadget {
			    public init(owner: User) {
			        self.owner = owner
			    }

			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let owner: User
			}

			public protocol Gadget {}

			public struct AnyThing: Gadget {
			    public init(_ gadget: any Gadget) {
			        self.gadget = gadget
			    }

			    public let gadget: any Gadget
			}
			""",
		]
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            user: (() -> User)? = nil,
		            thing: ((User) -> AnyThing)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                user: user,
		                thing: thing
		            )
		        }

		        var user: (() -> User)? { __safeDI_storage.user }
		        var thing: ((User) -> AnyThing)? { __safeDI_storage.thing }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                user: (() -> User)?,
		                thing: ((User) -> AnyThing)?
		            ) {
		                self.user = user
		                self.thing = thing
		            }

		            let user: (() -> User)?
		            let thing: ((User) -> AnyThing)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder() } else { User() }
		        func __safeDI_thing() -> AnyThing {
		            #sourceLocation(file: "\(output.fixtures["Thing.swift"])", line: 7)
		            let owner: User = user
		            #sourceLocation()
		            return if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder(owner) } else { AnyThing(Thing(owner: owner)) }
		        }
		        let thing: AnyThing = __safeDI_thing()
		        return Root(user: user, thing: thing)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsErasedRenameWithoutAnnotatingPromotedValue_whenMockBuildsValueForRootsOptionalReceive() async throws {
		// The mock promotes `token`, which production forwards as `Secret?`, and binds the `Secret` it builds as the walk
		// binds it, with no annotation: the erased rename maps over it as over an optional value.
		let fixture = [
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(sessionBuilder: Instantiator<Session>) {
			        self.sessionBuilder = sessionBuilder
			    }

			    @Instantiated let sessionBuilder: Instantiator<Session>
			}
			""",
			"""
			@Instantiable
			public final class Session: Instantiable {
			    public init(token: Secret?, feature: Feature) {
			        self.token = token
			        self.feature = feature
			    }

			    @Forwarded let token: Secret?
			    @Instantiated let feature: Feature
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class Feature: Instantiable {
			    public init(auth: AnyAuth?) {
			        self.auth = auth
			    }

			    @Received(fulfilledByDependencyNamed: "token", ofType: Secret?.self, erasedToConcreteExistential: true) let auth: AnyAuth?
			}
			""",
			"""
			@Instantiable
			public final class Secret: Instantiable, Auth {
			    public init() {}
			}

			public protocol Auth {}

			public struct AnyAuth: Auth {
			    public init(_ auth: any Auth) {
			        self.auth = auth
			    }

			    public let auth: any Auth
			}
			""",
		]
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(output.mockFiles["Feature+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Feature {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            token: (() -> Secret)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                token: token
		            )
		        }

		        var token: (() -> Secret)? { __safeDI_storage.token }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                token: (() -> Secret)?
		            ) {
		                self.token = token
		            }

		            let token: (() -> Secret)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Feature {
		        let token = if let safeDIBuilder = safeDIOverrides.token { safeDIBuilder() } else { Secret() }
		        #sourceLocation(file: "\(output.fixtures["Feature.swift"])", line: 7)
		        let auth: AnyAuth? = (token as Secret?).map { AnyAuth($0) }
		        #sourceLocation()
		        return Feature(auth: auth)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Feature+SafeDIMock.swift"] ?? "")")
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryPlaceOfTreeWithRenamesIsOverridden() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.valueFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.valueFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let overridden = """
		Root.mock(safeDIOverrides: .init(\
		user: { marked(User(), "user") }, \
		profile: .init(badge: { marked(Badge(account: $0, ownerIfBuilt: $1), "profile.badge") }, { marked(Profile(account: $0, person: $1, maybeUser: $2, badge: $3), "profile") }), \
		otherProfile: .init(badge: { marked(Badge(account: $0, ownerIfBuilt: $1), "otherProfile.badge") }, { marked(Profile(account: $0, person: $1, maybeUser: $2, badge: $3), "otherProfile") }), \
		panelBuilder: .init(badge: { marked(Badge(account: $0, ownerIfBuilt: $1), "panelBuilder.badge") }, { marked(Panel(viewer: $0, account: $1, badge: $2), "panelBuilder") })\
		))
		"""
		// Each probe reads every value, each rename's among them, and whether a rename and what it renames are one
		// instance.
		func reads(of root: String) -> String {
			"""
			{ let root = \(root); let panel = root.panelBuilder.instantiate(); \
			return [root.user.marker, root.owner.marker, root.profile.marker, root.profile.account.marker, root.profile.maybeUser?.marker ?? "nil", \
			root.profile.badge.marker, root.profile.badge.account.marker, root.profile.badge.ownerIfBuilt?.marker ?? "nil", \
			root.otherProfile.marker, root.otherProfile.badge.marker, panel.marker, panel.viewer.marker, panel.badge.marker, panel.badge.ownerIfBuilt?.marker ?? "nil", \
			root.owner === root.user ? "one owner" : "two owners", \
			root.profile.account === root.user ? "one account" : "two accounts", \
			(root.profile.person.person as? User) === root.user ? "one person" : "two persons", \
			root.profile.maybeUser === root.user ? "one maybe user" : "two maybe users", \
			root.otherProfile.account === root.profile.account ? "one other account" : "two other accounts", \
			panel.viewer === root.user ? "one viewer" : "two viewers", \
			root.profile.badge === root.otherProfile.badge ? "one badge" : "two badges"] }()
			"""
		}
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: Self.valueFixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: Self.valueFixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe(name: "built root", expression: reads(of: "Root.mock()")),
				DifferentialValueProbe(name: "overridden root", expression: reads(of: overridden)),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks the value its closure built.
		for marker in ["user", "profile.badge", "profile", "otherProfile.badge", "otherProfile", "panelBuilder.badge", "panelBuilder"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutTheWalksStatements_whenTypeDeclaringRenameTakesDependencyMockCannotBuild() async throws {
		// `Profile` declares a rename and instantiates a `Clock` the mock cannot build, which `mock()` takes as a parameter:
		// `Profile`'s record reads the parameter, and its rename is a node of its own, so the root is laid out from the
		// records, with the walk's statements.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(user: User, profile: Profile) {
			        self.user = user
			        self.profile = profile
			    }

			    @Instantiated let user: User
			    @Instantiated let profile: Profile
			}
			""",
			"""
			@Instantiable
			public final class User: Instantiable {
			    public init() {}
			}
			""",
			"""
			public final class Clock {}
			""",
			"""
			@Instantiable
			public final class Profile: Instantiable {
			    public init(account: User, clock: Clock) {
			        self.account = account
			        self.clock = clock
			    }

			    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let account: User
			    @Instantiated let clock: Clock
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.refusal) == [nil])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == Self.mockFile(of: "Root", in: walkOutput, withFixturePathsOf: output, fixtureNames: ["Profile.swift"]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutTheWalksStatements_whenRenameIsFulfilledByWrapperOfValueMockTakes() async throws {
		// `mock()` takes `session` by value and builds the `Garage` the root receives, binding a `LazilyInstantiated` around
		// `session` that the walk passes to each receiver by name. `Garage`'s rename reads that wrapper by its name, as the walk does.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(session: Session, garage: Garage) {
			        self.session = session
			        self.garage = garage
			    }

			    @Instantiated let session: Session
			    @Received let garage: Garage
			}
			""",
			"""
			public final class Session {}
			""",
			"""
			@Instantiable
			public final class Garage: Instantiable {
			    public init(session: LazilyInstantiated<Session>, lazySession: LazilyInstantiated<Session>) {
			        self.session = session
			        self.lazySession = lazySession
			    }

			    @Received let session: LazilyInstantiated<Session>
			    @Received(fulfilledByDependencyNamed: "session", ofType: LazilyInstantiated<Session>.self) let lazySession: LazilyInstantiated<Session>
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.refusal) == [nil])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == Self.mockFile(of: "Root", in: walkOutput, withFixturePathsOf: output, fixtureNames: ["Garage.swift"]))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root whose rename only if available reads `service`, which it does not create, beside a child that requires
	/// it, so the mock promotes `service` to a child of the root.
	private static let promotedDependencyFixture: [String: String] = [
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(maybeService: Service?, consumer: Consumer) {
		        self.maybeService = maybeService
		        self.consumer = consumer
		    }

		    @Received(fulfilledByDependencyNamed: "service", ofType: Service.self, onlyIfAvailable: true) let maybeService: Service?
		    @Instantiated let consumer: Consumer
		}
		""",
		"Service.swift": """
		@Instantiable
		public final class Service: Instantiable {
		    public init() {}
		}
		""",
		"Consumer.swift": """
		@Instantiable
		public final class Consumer: Instantiable {
		    public init(service: Service) {
		        self.service = service
		    }

		    @Received let service: Service
		}
		""",
	]

	/// A root whose mock binds a rename of its own child, a type that declares a required rename, an erased one and one
	/// only if available, that type built under two labels, a rename only if available bound to `nil` inside the tree
	/// of the property it renames, and renames beneath an `Instantiator`. Each type carries a marker an override's
	/// closure sets.
	private static let valueFixture: [String: String] = [
		"Marked.swift": """
		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable {
		    public init(user: User, owner: User, profile: Profile, otherProfile: Profile, panelBuilder: Instantiator<Panel>) {
		        self.user = user
		        self.owner = owner
		        self.profile = profile
		        self.otherProfile = otherProfile
		        self.panelBuilder = panelBuilder
		    }

		    @Instantiated public let user: User
		    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) public let owner: User
		    @Instantiated public let profile: Profile
		    @Instantiated public let otherProfile: Profile
		    @Instantiated public let panelBuilder: Instantiator<Panel>
		}
		""",
		"User.swift": """
		@Instantiable
		public final class User: Instantiable, Marked, Person {
		    public init() {}

		    public var marker = "built"
		}

		public protocol Person {}

		public struct AnyPerson: Person {
		    public init(_ person: any Person) {
		        self.person = person
		    }

		    public let person: any Person
		}
		""",
		"Profile.swift": """
		@Instantiable
		public final class Profile: Instantiable, Marked {
		    public init(account: User, person: AnyPerson, maybeUser: User?, badge: Badge) {
		        self.account = account
		        self.person = person
		        self.maybeUser = maybeUser
		        self.badge = badge
		    }

		    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) public let account: User
		    @Received(fulfilledByDependencyNamed: "user", ofType: User.self, erasedToConcreteExistential: true) public let person: AnyPerson
		    @Received(fulfilledByDependencyNamed: "user", ofType: User.self, onlyIfAvailable: true) public let maybeUser: User?
		    @Instantiated public let badge: Badge
		    public var marker = "built"
		}
		""",
		"Badge.swift": """
		@Instantiable
		public final class Badge: Instantiable, Marked {
		    public init(account: User, ownerIfBuilt: Badge?) {
		        self.account = account
		        self.ownerIfBuilt = ownerIfBuilt
		    }

		    @Received public let account: User
		    @Received(fulfilledByDependencyNamed: "badge", ofType: Badge.self, onlyIfAvailable: true) public let ownerIfBuilt: Badge?
		    public var marker = "built"
		}
		""",
		"Panel.swift": """
		@Instantiable
		public final class Panel: Instantiable, Marked {
		    public init(viewer: User, account: User, badge: Badge) {
		        self.viewer = viewer
		        self.account = account
		        self.badge = badge
		    }

		    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) public let viewer: User
		    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) public let account: User
		    @Instantiated public let badge: Badge
		    public var marker = "built"
		}
		""",
	]

	/// The mock file of `typeName` that `walkOutput` generated, with the path of each fixture of `fixtureNames` its
	/// renames' `#sourceLocation` directives name spelled as `output` wrote that fixture: each run writes its fixtures to
	/// a directory of its own.
	private static func mockFile(of typeName: String, in walkOutput: TestOutput, withFixturePathsOf output: TestOutput, fixtureNames: [String]) -> String? {
		fixtureNames.reduce(walkOutput.mockFiles["\(typeName)+SafeDIMock.swift"]) { file, fixtureName in
			file?.replacingOccurrences(of: walkOutput.fixtures[fixtureName], with: output.fixtures[fixtureName])
		}
	}

	/// What `body` returns with every internal mock root node records accept laid out from them, and the report of each
	/// root of the run.
	private static func layingOutMockRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports)
	}
}
