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

/// The walk that finds a seam's receivers and the reads of its parameters (`DependencyTreeGenerator.receivers(in:of:instantiables:)`)
/// does not visit a generator again in a frame that agrees, on the labels the generator's subtree reads, with a frame it
/// was visited in (`ReceiversVisit`). Each test here holds a generator two places of a seam's tree share, reached in
/// frames that differ in one part of that key: with the part left out, the second visit is skipped, and what only it
/// finds is lost. Which visit comes second follows the order the seam declares its properties in, so each graph is
/// written in both orders; the part is needed in one of them.
struct SafeDIToolSeamReceiversWalkTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Whether the place is built inside a `@Sendable` function

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableAutoclosure_whenSharedReceiverIsBuiltOutsideSendableFunctionFirst() async throws {
		// `Plain` and `Holder` each build `Detail`, which receives `user`, so their places share one generator. The walk visits
		// `Detail` beneath `Plain` first, in plain code, and then beneath `Holder`, inside the `@Sendable` function that builds
		// it: only that second visit reads `user` inside a `@Sendable` function, which makes the parameter `@Sendable`. With
		// whether the place is built inside a `@Sendable` function left out of the key, the second visit is skipped and the
		// parameter is a plain autoclosure, which the `@Sendable` function cannot capture.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.sendableFixture(plainFirst: true), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User) {
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        func __safeDI_plain() -> Plain {
		            let detail = Detail(user: user.instance)
		            return Plain(detail: detail)
		        }
		        let plain: Plain = __safeDI_plain()
		        @Sendable nonisolated func __safeDI_holderBuilder() -> Holder {
		            let detail = Detail(user: user.instance)
		            return Holder(detail: detail)
		        }
		        let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
		        self.init(plain: plain, holderBuilder: holderBuilder)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_8EFCFC03F02E0CB8 {}
		}
		""")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_takesSendableAutoclosure_whenSharedReceiverIsBuiltInsideSendableFunctionFirst() async throws {
		// The graph above with `Holder` declared first: the first visit of `Detail` reads `user` inside the `@Sendable`
		// function, and the second, in plain code, finds nothing new.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.sendableFixture(plainFirst: false), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_user: @autoclosure @escaping @Sendable () -> User) {
		        let user = SendableLazilyInstantiated<User>(__safeDI_user)
		        @Sendable nonisolated func __safeDI_holderBuilder() -> Holder {
		            let detail = Detail(user: user.instance)
		            return Holder(detail: detail)
		        }
		        let holderBuilder = SendableInstantiator<Holder>(__safeDI_holderBuilder)
		        func __safeDI_plain() -> Plain {
		            let detail = Detail(user: user.instance)
		            return Plain(detail: detail)
		        }
		        let plain: Plain = __safeDI_plain()
		        self.init(holderBuilder: holderBuilder, plain: plain)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_8EFCFC03F02E0CB8 {}
		}
		""")
	}

	// MARK: Tests – The declarations above the place

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingReceiver_whenSharedReceiverIsReachedBeneathDeclarationOfItsLabelFirst() async {
		// `First` and `Second` each build `Detail`, which receives `service`; `First` declares `service` itself, so the two
		// places read declarations the construction memo answers alike and share one generator. The walk visits `Detail`
		// beneath `First` first, where `First` provides `service`, and then beneath `Second`, where only the seam's
		// parameter does: only the second visit finds that `Detail` receives the parameter, whose `internal` type no
		// `public` tier can take. With the declarations above the place left out of the key, the second visit is skipped,
		// the parameter has no receiver, and no error is reported. Either half of that part alone tells the visits apart:
		// outside a fill, the labels declared above a place are those of the properties provided above it, and a fill is
		// reached along one path, since neither it nor any scope above it is shared; two places whose declarations above
		// share labels but differ in what they provide read declarations the memo answers apart, so they share no generator.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`’s `public` access requires, cannot take `service: Instantiator<Service>`, which `Detail` receives, and cannot pass `nil` for it, since it is required. `Service`’s own `@Instantiable` declaration is `internal`. Declare `Service` `public`; declare `Screen` `internal`; build `service` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `service: Instantiator<Service>` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.declarationFixture(firstDeclaredFirst: true), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsErrorNamingReceiver_whenSharedReceiverIsReachedBeneathNoDeclarationOfItsLabelFirst() async {
		// The graph above with `Second` declared first: the first visit of `Detail` finds the receive.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["Screen.swift"]):1:1: error: SafeDI cannot generate the dependency tree of `Screen`: its generated `public` initializer, which `Screen`’s `public` access requires, cannot take `service: Instantiator<Service>`, which `Detail` receives, and cannot pass `nil` for it, since it is required. `Service`’s own `@Instantiable` declaration is `internal`. Declare `Service` `public`; declare `Screen` `internal`; build `service` inside the tree or receive it with `onlyIfAvailable: true` and an optional type; or declare the dependency tree on an `internal` type that instantiates `Screen`.
			\(fixtures["Detail.swift"]):7:5: note: `Detail` receives `service: Instantiator<Service>` here.
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: Self.declarationFixture(firstDeclaredFirst: false), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `Screen`, a seam, builds `Plain` and, behind a `SendableInstantiator`, `Holder`, in the order `plainFirst` says; each
	/// builds `Detail`, which receives `user`, a parameter of the seam.
	private static func sendableFixture(plainFirst: Bool) -> [String] {
		let screenDeclarations = ["@Instantiated let plain: Plain", "@Instantiated let holderBuilder: SendableInstantiator<Holder>"]
		return [
			seamFixtureType(named: "Screen", isSeam: true, declarations: plainFirst ? screenDeclarations : screenDeclarations.reversed()),
			seamFixtureType(named: "Plain", declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Holder", declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let user: User"]),
			"""
			@Instantiable
			public final class User: Instantiable, Sendable {
			    public init() {}
			}
			""",
		]
	}

	/// `Screen`, a `public` seam, builds `First` and `Second`, in the order `firstDeclaredFirst` says; each builds `Detail`,
	/// which receives `service`, and `First` declares `service` too. `Service` is `internal`.
	private static func declarationFixture(firstDeclaredFirst: Bool) -> [String] {
		let screenDeclarations = ["@Instantiated let first: First", "@Instantiated let second: Second"]
		return [
			seamFixtureType(named: "Screen", isSeam: true, declarations: firstDeclaredFirst ? screenDeclarations : screenDeclarations.reversed()),
			seamFixtureType(named: "First", declarations: ["@Instantiated let service: Instantiator<Service>", "@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Second", declarations: ["@Instantiated let detail: Detail"]),
			seamFixtureType(named: "Detail", declarations: ["@Received let service: Instantiator<Service>"]),
			"""
			@Instantiable
			final class Service: Instantiable {
			    init() {}
			}
			""",
		]
	}
}
