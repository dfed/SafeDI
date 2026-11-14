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

/// A root that calls one seam twice fills its holes twice with the same types, so each fill finding is found once per
/// call, at the same locations and on the same path: it is reported once.
struct SafeDIToolSeamRepeatedFillFindingTests: ~Copyable {
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
	mutating func generate_throwsEachFillFindingOnce_whenRootCallsSeamTwice() async {
		// `Root` calls `Home` as `home` and as `otherHome`, and fills `Home`'s `apiSendableBuilder` with `LiveApi` in each:
		// each call's fills give the same two findings, at the same locations, on the same path in `Home`'s tree. They tie
		// on every location, so the comparison of their diagnostics keeps one of each.
		await assertThrowsMultiModuleError(inModule: "App", diagnostics: { fixtures in
			"""
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `P` builds only after `Home`’s tree calls the builder for `P`’s `api: any Api` (case `P_Scope.api` of `apiSendableBuilder`), so that builder’s scope does not carry it. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` declares `rBuilder: Instantiator<R>` here.
			\(fixtures["App"]!["LiveApi.swift"]):9:5: error: `LiveApi` receives `rBuilder: Instantiator<R>?`, which `Home`’s tree is building where it calls the builder for `R`’s `api: any Api` (case `R_Scope.api` of `apiSendableBuilder`). Inline, `LiveApi` can get an instantiator of its own, made from the function `Home`’s initializer declares for `rBuilder`, which code generated outside module `Feature` cannot refer to. Instantiate `rBuilder` on a type above `Home`, and receive it on `P` in place of its @Instantiated declaration, so that the caller’s tree builds it, or declare an @Instantiable type that fulfills `Api` in module `Feature` or a module it lists among its SafeDI dependencies.
			\(fixtures["Feature"]!["P.swift"]):9:5: note: `P` instantiates `rBuilder: Instantiator<R>` here.
			"""
		}) {
			try await executeSafeDIToolMultiModuleTest(
				modules: SafeDIToolSeamBuilderParameterTests.modules(
					feature: [
						"public protocol Api {}",
						seamFixtureType(named: "R", declarations: ["@Instantiated let api: any Api"]),
						seamFixtureType(named: "P", declarations: ["@Instantiated let api: any Api", "@Instantiated let rBuilder: Instantiator<R>"]),
						seamFixtureType(named: "Home", isSeam: true, declarations: ["@Instantiated let pBuilder: SendableInstantiator<P>"]),
					],
					app: [
						SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveApi", fulfilling: "Api", declarations: ["@Received(onlyIfAvailable: true) let rBuilder: Instantiator<R>?"]),
						seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated let home: Home", "@Instantiated let otherHome: Home"]),
					],
				),
				integration: .moduleInfo,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
