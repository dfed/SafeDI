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

/// The order a scope builds its children in where each child on a cycle is a call place, beside today's order
/// (`CallPlaceOrderObservation`).
struct SafeDIToolCallPlaceOrderTests: ~Copyable {
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
	mutating func generate_buildsLoggerAfterBuilderItReceivesOnlyIfAvailable_whenBuilderIsCallPlace() async throws {
		// `Logger` receives `screenBuilder` only if available, so `Root` builds `logger`, declared first, after
		// `screenBuilder`. As a call place `screenBuilder` receives what `Screen`'s tree receives, `logger` only if
		// available, which waits on nothing that waits on it: the order is today's.
		let orders = try await orders(of:
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

		#expect(orders == [Orders(scope: "Root", todaysOrder: [1, 0], callPlaceOrder: [1, 0])])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ordersChildrenOfTypeInsideCycleAsToday_whenItsChildrenOnCycleAreCallPlaces() async throws {
		// `T0`, built inside `T3`'s cycle, builds its own `logger` after its `t3Builder`, as `Root` does: every place of
		// each scope is compared with the scope's order where `t3Builder`, `t0Builder` and `t4Builder` are call places.
		let orders = try await orders(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let session: Session
		    @Instantiated let logger: Logger
		    @Instantiated let t3Builder: Instantiator<T3>
		    public init(session: Session, logger: Logger, t3Builder: Instantiator<T3>) { self.session = session; self.logger = logger; self.t3Builder = t3Builder }
		}

		@Instantiable public final class T3: Instantiable {
		    @Received(onlyIfAvailable: true) let session: Session?
		    @Received(onlyIfAvailable: true) let logger: Logger?
		    @Instantiated let t0Builder: Instantiator<T0>
		    @Instantiated let t4Builder: Instantiator<T4>
		    public init(session: Session?, logger: Logger?, t0Builder: Instantiator<T0>, t4Builder: Instantiator<T4>) { self.session = session; self.logger = logger; self.t0Builder = t0Builder; self.t4Builder = t4Builder }
		}

		@Instantiable public final class T0: Instantiable {
		    @Instantiated let session: Session
		    @Instantiated let logger: Logger
		    @Instantiated let t3Builder: Instantiator<T3>
		    public init(session: Session, logger: Logger, t3Builder: Instantiator<T3>) { self.session = session; self.logger = logger; self.t3Builder = t3Builder }
		}

		@Instantiable public final class T4: Instantiable {
		    @Instantiated let t3Builder: Instantiator<T3>
		    public init(t3Builder: Instantiator<T3>) { self.t3Builder = t3Builder }
		}

		@Instantiable public final class Session: Instantiable { public init() {} }

		@Instantiable public final class Logger: Instantiable {
		    @Received(onlyIfAvailable: true) let t3Builder: Instantiator<T3>?
		    public init(t3Builder: Instantiator<T3>?) { self.t3Builder = t3Builder }
		}
		""")

		#expect(orders == [
			Orders(scope: "Root", todaysOrder: [0, 2, 1], callPlaceOrder: [0, 2, 1]),
			Orders(scope: "\"t3Builder: Instantiator<T3>\"", todaysOrder: [0, 1], callPlaceOrder: [0, 1]),
			Orders(scope: "\"t0Builder: Instantiator<T0>\"", todaysOrder: [0, 2, 1], callPlaceOrder: [0, 2, 1]),
		])
	}

	// MARK: Private

	private struct Orders: Equatable {
		let scope: String
		let todaysOrder: [Int]
		let callPlaceOrder: [Int]
	}

	private var filesToDelete: [URL]

	/// Each distinct comparison the tool hands on while it generates from `swiftFileContent`, in the order first handed
	/// on: a run builds a root's tree more than once.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func orders(of swiftFileContent: String) async throws -> [Orders] {
		let (stream, continuation) = AsyncStream.makeStream(of: Orders.self)
		try await CallPlaceOrderObservation.$observer.withValue(TaskLocalFunction { scope, todaysOrder, callPlaceOrder in
			continuation.yield(Orders(scope: scope, todaysOrder: todaysOrder, callPlaceOrder: callPlaceOrder))
		}) {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		continuation.finish()
		var orders = [Orders]()
		for await order in stream where !orders.contains(order) {
			orders.append(order)
		}
		return orders
	}
}
