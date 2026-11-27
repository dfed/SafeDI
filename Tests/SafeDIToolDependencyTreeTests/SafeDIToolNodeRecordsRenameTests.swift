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

/// Node records of a rename (`NodeRecords.renameClaim(of:in:)`): each place declares the rename as the tree's place does,
/// bound from its fulfilling property, or, only if available, to `nil` where nothing it reads is available.
struct SafeDIToolNodeRecordsRenameTests: ~Copyable {
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
	mutating func generate_laysOutRootFromNodeRecords_whenTypeRenamesRequiredProperty() async throws {
		// `Profile` receives `user` as `account`, which its sibling `user` provides.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
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
				public final class Profile: Instantiable {
				    public init(account: User) {
				        self.account = account
				    }
				    @Received(fulfilledByDependencyNamed: "user", ofType: User.self) let account: User
				}
				""",
				"""
				@Instantiable
				public final class User: Instantiable {
				    public init() {}
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		extension Root {
		    public init() {
		        let user = User()
		        func __safeDI_profile() -> Profile {
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 6)
		            let account: User = user
		            #sourceLocation()
		            return Profile(account: account)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(user: user, profile: profile)
		    }
		}
		"""])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootFromNodeRecords_whenRenameOnlyIfAvailableFindsNothing() async throws {
		// Nothing above `Profile` declares `theme`, so its rename `style` is `nil`.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(profile: Profile) {
				        self.profile = profile
				    }
				    @Instantiated let profile: Profile
				}
				""",
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(style: Theme?) {
				        self.style = style
				    }
				    @Received(fulfilledByDependencyNamed: "theme", ofType: Theme.self, onlyIfAvailable: true) let style: Theme?
				}
				""",
				"""
				public struct Theme {}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_profile() -> Profile {
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 6)
		            let style: Theme? = nil
		            #sourceLocation()
		            return Profile(style: style)
		        }
		        let profile: Profile = __safeDI_profile()
		        self.init(profile: profile)
		    }
		}
		"""])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootFromNodeRecords_whenRenameOnlyIfAvailableReadsForwardedOptional() async throws {
		// `Profile` renames `theme` only if available, which `Screen` forwards optional, so the rename reads an optional.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public struct Root: Instantiable {
				    public init(screenBuilder: Instantiator<Screen>) {
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let screenBuilder: Instantiator<Screen>
				}
				""",
				"""
				@Instantiable
				public final class Screen: Instantiable {
				    public init(theme: Theme?, profile: Profile) {
				        self.theme = theme
				        self.profile = profile
				    }
				    @Forwarded let theme: Theme?
				    @Instantiated let profile: Profile
				}
				""",
				"""
				@Instantiable
				public final class Profile: Instantiable {
				    public init(style: Theme?) {
				        self.style = style
				    }
				    @Received(fulfilledByDependencyNamed: "theme", ofType: Theme.self, onlyIfAvailable: true) let style: Theme?
				}
				""",
				"""
				public struct Theme {}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + """
		extension Root {
		    public init() {
		        func __safeDI_profile(theme: Theme?) -> Profile {
		            #sourceLocation(file: "\(output.fixtures["Profile.swift"])", line: 6)
		            let style: Theme? = theme
		            #sourceLocation()
		            return Profile(style: style)
		        }
		        func __safeDI_screenBuilder(theme: Theme?) -> Screen {
		            let profile: Profile = __safeDI_profile(theme: theme)
		            return Screen(theme: theme, profile: profile)
		        }
		        let screenBuilder = Instantiator<Screen> {
		            __safeDI_screenBuilder(theme: $0)
		        }
		        self.init(screenBuilder: screenBuilder)
		    }
		}
		"""])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_refusesSeamsOwnRootAsCallsAnsweringAVariantApart_whenTwoPathsHandARenamesLabelOneAsAWrappersInstance() async throws {
		// `Reader` keeps `authToken`'s label under a rename and is built under `Screen` directly, where `authToken` is the
		// instance of the wrapper of the seam's parameter, and beneath `Detail`'s rename, whose value is no wrapper's: the
		// tree binds `Reader`'s rename two ways, and one record cannot. The calls into `Reader`'s variant answer its label
		// apart, which refuses the world before the rename's own check.
		let (_, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [
				seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let authToken: Secret", "@Instantiated let screen: Screen"]),
				seamFixtureType(named: "Screen", isSeam: true, isFinalClass: true, declarations: ["@Instantiated let reader: Reader", "@Instantiated let left: Left"]),
				seamFixtureType(named: "Left", isFinalClass: true, declarations: ["@Instantiated let detail: Detail"]),
				seamFixtureType(named: "Detail", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "token", ofType: Secret.self, onlyIfAvailable: true) let authToken: Secret?"#, "@Instantiated let reader: Reader"]),
				seamFixtureType(named: "Reader", isFinalClass: true, declarations: [#"@Received(fulfilledByDependencyNamed: "authToken", ofType: Secret?.self, onlyIfAvailable: true) let authToken: (any Auth)?"#]),
				seamFixtureType(named: "Secret", isFinalClass: true, declarations: [], conformances: ", Auth"),
				"public protocol Auth {}",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		let screenReports = reports.filter { $0.root == "Screen" }
		// A seam's root's keys are not yet seeded from its parameters, so the read of a deferred parameter's instance refuses
		// the world as `lazy` first.
		#expect(screenReports.map(\.refusal) == ["lazy"])
		#expect(screenReports.map(\.isLaidOutFromNodeRecords) == [false])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
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
