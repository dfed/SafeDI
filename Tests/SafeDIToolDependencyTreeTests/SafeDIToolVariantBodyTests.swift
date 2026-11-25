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

/// What each place of a production root's tree passes `nil`, beside what a body passes `nil` that is built from the
/// scope's copy with call places beneath the answers the place's path gives (`VariantBodyObservation`).
struct SafeDIToolVariantBodyTests: ~Copyable {
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
	mutating func generate_buildsBodyThatPassesNilWhereTodaysPlaceDoes_whenReceiveIsOfBuilderStillBeingBuilt() async throws {
		// `Detail` receives `detail` only if available while it is the `detail` being built, so today's place and
		// the body built from its answers both pass it `nil`; no other place is passed `nil` in either build. The places
		// of `screenBuilder`'s function are compared again with what the call in `nextBuilder` gives them.
		let bodies = try await bodies(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let logger: Logger
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(logger: Logger, screenBuilder: Instantiator<Screen>) { self.logger = logger; self.screenBuilder = screenBuilder }
			}

			@Instantiable public final class Logger: Instantiable {
			    public init() {}
			}

			@Instantiable public final class Screen: Instantiable {
			    @Received(onlyIfAvailable: true) let logger: Logger?
			    @Instantiated let detail: Detail
			    @Instantiated let nextBuilder: Instantiator<Next>
			    public init(logger: Logger?, detail: Detail, nextBuilder: Instantiator<Next>) { self.logger = logger; self.detail = detail; self.nextBuilder = nextBuilder }
			}

			@Instantiable public final class Detail: Instantiable {
			    @Received(onlyIfAvailable: true) let detail: Detail?
			    public init(detail: Detail?) { self.detail = detail }
			}

			@Instantiable public final class Next: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(bodies == [
			Bodies(place: "\"logger: Logger\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\"", todaysUnavailableProperties: ["detail: Detail?"], bodysUnavailableProperties: ["detail: Detail?"]),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"screenBuilder: Instantiator<Screen>\" called by \"screenBuilder: Instantiator<Screen>\" in \"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
			Bodies(place: "\"detail: Detail\" called by \"screenBuilder: Instantiator<Screen>\" in \"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: ["detail: Detail?"], bodysUnavailableProperties: ["detail: Detail?"]),
			Bodies(place: "\"nextBuilder: Instantiator<Next>\" called by \"screenBuilder: Instantiator<Screen>\" in \"nextBuilder: Instantiator<Next>\"", todaysUnavailableProperties: [], bodysUnavailableProperties: []),
		])
	}

	// MARK: Private

	private struct Bodies: Equatable {
		let place: String
		let todaysUnavailableProperties: [String]
		let bodysUnavailableProperties: [String]
	}

	private var filesToDelete: [URL]

	/// Each distinct comparison the tool hands on while it generates from `swiftFileContent`, in the order first handed on.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func bodies(of swiftFileContent: String) async throws -> [Bodies] {
		let (stream, continuation) = AsyncStream.makeStream(of: Bodies.self)
		try await VariantBodyObservation.$observer.withValue({ place, todaysUnavailableProperties, bodysUnavailableProperties in
			continuation.yield(Bodies(place: place, todaysUnavailableProperties: todaysUnavailableProperties, bodysUnavailableProperties: bodysUnavailableProperties))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var bodies = [Bodies]()
		for await body in stream where !bodies.contains(body) {
			bodies.append(body)
		}
		return bodies
	}
}
