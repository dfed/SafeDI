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

/// What each place of today's tree read of the declarations above it, beside the labels the plan by declaration keys
/// its body by (`PlaceReadsObservation`).
struct SafeDIToolPlaceReadsTests: ~Copyable {
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
	mutating func generate_readsOnlyLabelsThePlanKeysBodyBy_whenTypeInsideCycleReceivesLabelFromAbove() async throws {
		// `Screen` receives `logger` only if available and `Detail` opens `Screen` again, so each place on the cycle reads
		// `logger` from above it, and the plan keys each of their bodies by that label. `Logger` reads `screenBuilder`,
		// which `Root` builds after it.
		let reads = try await reads(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let logger: Logger
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(logger: Logger, screenBuilder: Instantiator<Screen>) { self.logger = logger; self.screenBuilder = screenBuilder }
			}

			@Instantiable public final class Logger: Instantiable {
			    @Received(onlyIfAvailable: true) let screenBuilder: Instantiator<Screen>?
			    public init(screenBuilder: Instantiator<Screen>?) { self.screenBuilder = screenBuilder }
			}

			@Instantiable public final class Screen: Instantiable {
			    @Received(onlyIfAvailable: true) let logger: Logger?
			    @Instantiated let detailBuilder: Instantiator<Detail>
			    public init(logger: Logger?, detailBuilder: Instantiator<Detail>) { self.logger = logger; self.detailBuilder = detailBuilder }
			}

			@Instantiable public final class Detail: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}
			""")

		#expect(reads == [
			Reads(type: "Logger", property: "logger: Logger", labelsRead: ["screenBuilder"], labelsPlanned: ["screenBuilder"]),
			Reads(type: "Screen", property: "screenBuilder: Instantiator<Screen>", labelsRead: ["logger"], labelsPlanned: ["logger"]),
			Reads(type: "Detail", property: "detailBuilder: Instantiator<Detail>", labelsRead: ["logger"], labelsPlanned: ["logger"]),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsOnlyLabelsThePlanKeysBodyBy_whenCycleParameterIsHiddenByNearerDeclarationOfAnotherForm() async throws {
		// `Detail` receives `mark: Stamp?` only if available beneath `Flow`, which forwards `mark: Mark?`: the nearest
		// declaration of the label provides no form `Detail` reads, so `Detail` is passed `nil` on every path. Today's
		// tree still gives the function `Detail` closes the cycle on a parameter `mark: Stamp?`, which nothing in the
		// function reads, and `Screen`'s place asks the declarations above it for the argument. That read is of what a
		// cycle passes, so it is none of the reads the plan's labels are compared with: the plan keys `Screen`'s body by
		// no label, and `Detail`'s by `mark`, which `Flow` answers.
		let reads = try await reads(of:
			"""
			@Instantiable(isRoot: true) public final class Root: Instantiable {
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
			}

			@Instantiable public final class Screen: Instantiable {
			    @Instantiated let flowBuilder: Instantiator<Flow>
			    public init(flowBuilder: Instantiator<Flow>) { self.flowBuilder = flowBuilder }
			}

			@Instantiable public final class Flow: Instantiable {
			    @Forwarded let mark: Mark?
			    @Instantiated let detailBuilder: Instantiator<Detail>
			    public init(mark: Mark?, detailBuilder: Instantiator<Detail>) { self.mark = mark; self.detailBuilder = detailBuilder }
			}

			@Instantiable public final class Detail: Instantiable {
			    @Received(onlyIfAvailable: true) let mark: Stamp?
			    @Instantiated let screenBuilder: Instantiator<Screen>
			    public init(mark: Stamp?, screenBuilder: Instantiator<Screen>) { self.mark = mark; self.screenBuilder = screenBuilder }
			}

			public final class Mark {}

			public final class Stamp {}
			""")

		#expect(reads == [
			Reads(type: "Screen", property: "screenBuilder: Instantiator<Screen>", labelsRead: [], labelsPlanned: []),
			Reads(type: "Detail", property: "detailBuilder: Instantiator<Detail>", labelsRead: ["mark"], labelsPlanned: ["mark"]),
			Reads(type: "Flow", property: "flowBuilder: Instantiator<Flow>", labelsRead: [], labelsPlanned: []),
		])
	}

	// MARK: Private

	private struct Reads: Equatable {
		let type: String
		let property: String
		let labelsRead: [String]
		let labelsPlanned: [String]
	}

	private var filesToDelete: [URL]

	/// Each distinct comparison the tool hands on while it generates from `swiftFileContent`, in the order first handed
	/// on: a run builds a root's tree more than once.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func reads(of swiftFileContent: String) async throws -> [Reads] {
		let (stream, continuation) = AsyncStream.makeStream(of: Reads.self)
		try await PlaceReadsObservation.$observer.withValue(TaskLocalFunction { type, property, labelsRead, labelsPlanned in
			continuation.yield(Reads(type: type, property: property, labelsRead: labelsRead, labelsPlanned: labelsPlanned))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var reads = [Reads]()
		for await read in stream where !reads.contains(read) {
			reads.append(read)
		}
		return reads
	}
}
