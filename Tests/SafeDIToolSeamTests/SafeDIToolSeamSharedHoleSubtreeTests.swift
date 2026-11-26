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

/// A type of a seam's tree that holds a place and is reached on two paths, whose places differ only in what the path above
/// the type decides: whether a `@Sendable` function encloses the type, and the level of the path a lazy cycle beneath it
/// closes on. What a place's fill may read is a fact of its path, so a generator two paths share hands each path its own
/// answer. Each graph builds in one module, and these tests hold the values the seam's fills build to that build's.
struct SafeDIToolSeamSharedHoleSubtreeTests: ~Copyable {
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

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_carriesValueBoundInsideSendableFunction_whenTypeHoldingPlaceIsAlsoReachedOutsideOne(sendableBuilderFirst: Bool) async throws {
		// `Mid` binds `service` before its place `tracker`, and `Home` reaches `Mid` in plain code through `plain` and inside
		// `sendableBuilder`'s `@Sendable` function through `Wrap`. Both places carry `service`, which `LiveTracker` reads: on
		// the second path it is bound inside the function that builds the place.
		let homeDeclarations = ["@Instantiated public let plain: Plain", "@Instantiated public let sendableBuilder: SendableInstantiator<Wrap>"]
		try await expectSeam(
			feature: [
				"public protocol Tracker {}",
				seamFixtureType(named: "Service", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Mid", declarations: ["@Instantiated public let service: Service", "@Instantiated public let tracker: any Tracker"]),
				seamFixtureType(named: "Plain", declarations: ["@Instantiated public let mid: Mid"]),
				seamFixtureType(named: "Wrap", declarations: ["@Instantiated public let mid: Mid"]),
				seamFixtureType(named: "Home", isSeam: true, declarations: sendableBuilderFirst ? homeDeclarations.reversed() : homeDeclarations),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveTracker", fulfilling: "Tracker", declarations: ["@Received public let service: Service"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("Root().home.sendableBuilder.instantiate()"),
			],
			expectedFeature: sendableBuilderFirst ? """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier<__safeDI_Built> {
			        public let plain: (SendableInstantiator<Wrap>) -> __safeDI_TrackerCarrier_Plain<__safeDI_Built>

			        public init(plain: @escaping (SendableInstantiator<Wrap>) -> __safeDI_TrackerCarrier_Plain<__safeDI_Built>) {
			            self.plain = plain
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(plain: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Plain<__safeDI_Built> {
			        public let mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>

			        public init(mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>) {
			            self.mid = mid
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(mid: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Wrap<__safeDI_Built> {
			        public let mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>

			        public init(mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>) {
			            self.mid = mid
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(mid: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Mid<__safeDI_Built> {
			        public let tracker: (Service) -> __safeDI_Built

			        public init(tracker: @escaping (Service) -> __safeDI_Built) {
			            self.tracker = tracker
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(tracker: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerSendableCarrier<__safeDI_Built>: Sendable {
			        public let sendableBuilder: @Sendable () -> __safeDI_TrackerCarrier_Wrap<__safeDI_Built>

			        public init(sendableBuilder: @escaping @Sendable () -> __safeDI_TrackerCarrier_Wrap<__safeDI_Built>) {
			            self.sendableBuilder = sendableBuilder
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(sendableBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_trackerBuilder: __safeDI_TrackerCarrier<any Tracker>, __safeDI_trackerSendableBuilder: __safeDI_TrackerSendableCarrier<any Tracker>) {
			        @Sendable nonisolated func __safeDI_mid(__safeDI_trackerSendableBuilder_mid: __safeDI_TrackerCarrier_Mid<any Tracker>) -> Mid {
			            let service = Service()
			            let tracker: any Tracker = __safeDI_trackerSendableBuilder_mid.tracker(service)
			            return Mid(service: service, tracker: tracker)
			        }
			        @Sendable nonisolated func __safeDI_sendableBuilder() -> Wrap {
			            let __safeDI_trackerSendableBuilder_sendableBuilder = __safeDI_trackerSendableBuilder.sendableBuilder()
			            let __safeDI_trackerSendableBuilder_mid = __safeDI_trackerSendableBuilder_sendableBuilder.mid
			            let mid: Mid = __safeDI_mid(__safeDI_trackerSendableBuilder_mid: __safeDI_trackerSendableBuilder_mid)
			            return Wrap(mid: mid)
			        }
			        let sendableBuilder = SendableInstantiator<Wrap>(__safeDI_sendableBuilder)
			        let __safeDI_trackerBuilder_plain = __safeDI_trackerBuilder.plain(sendableBuilder)
			        func __safeDI_mid_(__safeDI_trackerBuilder_mid: __safeDI_TrackerCarrier_Mid<any Tracker>) -> Mid {
			            let service = Service()
			            let tracker: any Tracker = __safeDI_trackerBuilder_mid.tracker(service)
			            return Mid(service: service, tracker: tracker)
			        }
			        func __safeDI_plain() -> Plain {
			            let __safeDI_trackerBuilder_mid = __safeDI_trackerBuilder_plain.mid
			            let mid: Mid = __safeDI_mid_(__safeDI_trackerBuilder_mid: __safeDI_trackerBuilder_mid)
			            return Plain(mid: mid)
			        }
			        let plain: Plain = __safeDI_plain()
			        self.init(sendableBuilder: sendableBuilder, plain: plain)
			    }
			}

			extension Home {
			    public enum __safeDI_Home_774D4801034D1491 {}
			}
			""" : """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier<__safeDI_Built> {
			        public let plain: __safeDI_TrackerCarrier_Plain<__safeDI_Built>

			        public init(plain: __safeDI_TrackerCarrier_Plain<__safeDI_Built>) {
			            self.plain = plain
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(plain: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Plain<__safeDI_Built> {
			        public let mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>

			        public init(mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>) {
			            self.mid = mid
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(mid: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Wrap<__safeDI_Built> {
			        public let mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>

			        public init(mid: __safeDI_TrackerCarrier_Mid<__safeDI_Built>) {
			            self.mid = mid
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(mid: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Mid<__safeDI_Built> {
			        public let tracker: (Service) -> __safeDI_Built

			        public init(tracker: @escaping (Service) -> __safeDI_Built) {
			            self.tracker = tracker
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(tracker: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerSendableCarrier<__safeDI_Built>: Sendable {
			        public let sendableBuilder: @Sendable () -> __safeDI_TrackerCarrier_Wrap<__safeDI_Built>

			        public init(sendableBuilder: @escaping @Sendable () -> __safeDI_TrackerCarrier_Wrap<__safeDI_Built>) {
			            self.sendableBuilder = sendableBuilder
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping @Sendable () -> __safeDI_Built) {
			            self.init(sendableBuilder: { .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_trackerBuilder: __safeDI_TrackerCarrier<any Tracker>, __safeDI_trackerSendableBuilder: __safeDI_TrackerSendableCarrier<any Tracker>) {
			        let __safeDI_trackerBuilder_plain = __safeDI_trackerBuilder.plain
			        func __safeDI_mid(__safeDI_trackerBuilder_mid: __safeDI_TrackerCarrier_Mid<any Tracker>) -> Mid {
			            let service = Service()
			            let tracker: any Tracker = __safeDI_trackerBuilder_mid.tracker(service)
			            return Mid(service: service, tracker: tracker)
			        }
			        func __safeDI_plain() -> Plain {
			            let __safeDI_trackerBuilder_mid = __safeDI_trackerBuilder_plain.mid
			            let mid: Mid = __safeDI_mid(__safeDI_trackerBuilder_mid: __safeDI_trackerBuilder_mid)
			            return Plain(mid: mid)
			        }
			        let plain: Plain = __safeDI_plain()
			        @Sendable nonisolated func __safeDI_mid_(__safeDI_trackerSendableBuilder_mid: __safeDI_TrackerCarrier_Mid<any Tracker>) -> Mid {
			            let service = Service()
			            let tracker: any Tracker = __safeDI_trackerSendableBuilder_mid.tracker(service)
			            return Mid(service: service, tracker: tracker)
			        }
			        @Sendable nonisolated func __safeDI_sendableBuilder() -> Wrap {
			            let __safeDI_trackerSendableBuilder_sendableBuilder = __safeDI_trackerSendableBuilder.sendableBuilder()
			            let __safeDI_trackerSendableBuilder_mid = __safeDI_trackerSendableBuilder_sendableBuilder.mid
			            let mid: Mid = __safeDI_mid_(__safeDI_trackerSendableBuilder_mid: __safeDI_trackerSendableBuilder_mid)
			            return Wrap(mid: mid)
			        }
			        let sendableBuilder = SendableInstantiator<Wrap>(__safeDI_sendableBuilder)
			        self.init(plain: plain, sendableBuilder: sendableBuilder)
			    }
			}

			extension Home {
			    public enum __safeDI_Home_26C71CB45A76194D {}
			}
			""",
			expectedApp: sendableBuilderFirst ? """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_trackerBuilder_Home() -> Home.__safeDI_TrackerCarrier<any Tracker> {
			            .init(plain: { values_sendableBuilder in __safeDI_trackerBuilder_Home_Plain_Scope() })
			        }
			        func __safeDI_trackerBuilder_Home_Plain_Scope() -> Home.__safeDI_TrackerCarrier_Plain<any Tracker> {
			            .init(mid: __safeDI_trackerBuilder_Home_Mid_Scope())
			        }
			        @Sendable nonisolated func __safeDI_trackerBuilder_Home_Mid_Scope() -> Home.__safeDI_TrackerCarrier_Mid<any Tracker> {
			            .init(tracker: { scope_service in
			                let service = scope_service
			                let tracker: any Tracker = LiveTracker(service: service)
			                return tracker
			            })
			        }
			        @Sendable nonisolated func __safeDI_trackerSendableBuilder_Home() -> Home.__safeDI_TrackerSendableCarrier<any Tracker> {
			            .init(sendableBuilder: { __safeDI_trackerBuilder_Home_Wrap_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_trackerBuilder_Home_Wrap_Scope() -> Home.__safeDI_TrackerCarrier_Wrap<any Tracker> {
			            .init(mid: __safeDI_trackerBuilder_Home_Mid_Scope())
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_774D4801034D1491.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Home(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Home(), __safeDI_trackerSendableBuilder: __safeDI_trackerSendableBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""" : """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_trackerBuilder_Home() -> Home.__safeDI_TrackerCarrier<any Tracker> {
			            .init(plain: __safeDI_trackerBuilder_Home_Plain_Scope())
			        }
			        func __safeDI_trackerBuilder_Home_Plain_Scope() -> Home.__safeDI_TrackerCarrier_Plain<any Tracker> {
			            .init(mid: __safeDI_trackerBuilder_Home_Mid_Scope())
			        }
			        @Sendable nonisolated func __safeDI_trackerBuilder_Home_Mid_Scope() -> Home.__safeDI_TrackerCarrier_Mid<any Tracker> {
			            .init(tracker: { scope_service in
			                let service = scope_service
			                let tracker: any Tracker = LiveTracker(service: service)
			                return tracker
			            })
			        }
			        @Sendable nonisolated func __safeDI_trackerSendableBuilder_Home() -> Home.__safeDI_TrackerSendableCarrier<any Tracker> {
			            .init(sendableBuilder: { __safeDI_trackerBuilder_Home_Wrap_Scope() })
			        }
			        @Sendable nonisolated func __safeDI_trackerBuilder_Home_Wrap_Scope() -> Home.__safeDI_TrackerCarrier_Wrap<any Tracker> {
			            .init(mid: __safeDI_trackerBuilder_Home_Mid_Scope())
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_26C71CB45A76194D.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Home(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Home(), __safeDI_trackerSendableBuilder: __safeDI_trackerSendableBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		)
	}

	@Test(arguments: [false, true])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsValueBoundBeneathCycle_whenTypeHoldingPlaceIsReachedAtTwoDepthsOfCycle(leftFirst: Bool) async throws {
		// `Home` builds `X` behind `xBuilder` at the first level of its path and behind `Inner`'s `xBuilder` at the third.
		// Inside each, `Y` receives the `xBuilder` its function was built for, closing a lazy cycle on a scope at another level
		// of each path; `Mid` binds `token` before its place `tracker`, whose fill reads it.
		let homeDeclarations = ["@Instantiated public let xBuilder: Instantiator<X>", "@Instantiated public let left: Left"]
		try await expectSeam(
			feature: [
				"public protocol Tracker {}",
				seamFixtureType(named: "Token", isFinalClass: true, declarations: []),
				seamFixtureType(named: "Mid", declarations: ["@Instantiated public let token: Token", "@Instantiated public let tracker: any Tracker"]),
				seamFixtureType(named: "Y", declarations: ["@Instantiated public let token: Token", "@Received public let xBuilder: Instantiator<X>"]),
				seamFixtureType(named: "X", declarations: ["@Instantiated public let mid: Mid", "@Instantiated public let y: Y"]),
				seamFixtureType(named: "Inner", declarations: ["@Instantiated public let xBuilder: Instantiator<X>"]),
				seamFixtureType(named: "Left", declarations: ["@Instantiated public let inner: Inner"]),
				seamFixtureType(named: "Home", isSeam: true, declarations: leftFirst ? homeDeclarations.reversed() : homeDeclarations),
			],
			fulfillers: [
				SafeDIToolSeamBuilderParameterTests.fulfillingType(named: "LiveTracker", fulfilling: "Tracker", declarations: ["@Received public let token: Token"]),
			],
			root: seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated public let home: Home"]),
			probes: [
				DifferentialValueProbe("Root()"),
				DifferentialValueProbe("Root().home.xBuilder.instantiate().y.xBuilder.instantiate()"),
				DifferentialValueProbe("Root().home.left.inner.xBuilder.instantiate().y.xBuilder.instantiate()"),
			],
			expectedFeature: leftFirst ? """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier<__safeDI_Built> {
			        public let left: __safeDI_TrackerCarrier_Left<__safeDI_Built>
			        public let xBuilder: (Left) -> __safeDI_TrackerCarrier_X<__safeDI_Built>

			        public init(left: __safeDI_TrackerCarrier_Left<__safeDI_Built>, xBuilder: @escaping (Left) -> __safeDI_TrackerCarrier_X<__safeDI_Built>) {
			            self.left = left
			            self.xBuilder = xBuilder
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(left: .init(__safeDI_noScope: __safeDI_builder), xBuilder: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Left<__safeDI_Built> {
			        public let inner: __safeDI_TrackerCarrier_Inner<__safeDI_Built>

			        public init(inner: __safeDI_TrackerCarrier_Inner<__safeDI_Built>) {
			            self.inner = inner
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_X<__safeDI_Built> {
			        public let mid: (Instantiator<X>, Y) -> __safeDI_TrackerCarrier_Mid<__safeDI_Built>

			        public init(mid: @escaping (Instantiator<X>, Y) -> __safeDI_TrackerCarrier_Mid<__safeDI_Built>) {
			            self.mid = mid
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(mid: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Inner<__safeDI_Built> {
			        public let xBuilder: __safeDI_TrackerCarrier_X<__safeDI_Built>

			        public init(xBuilder: __safeDI_TrackerCarrier_X<__safeDI_Built>) {
			            self.xBuilder = xBuilder
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(xBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Mid<__safeDI_Built> {
			        public let tracker: (Token) -> __safeDI_Built

			        public init(tracker: @escaping (Token) -> __safeDI_Built) {
			            self.tracker = tracker
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(tracker: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_trackerBuilder: __safeDI_TrackerCarrier<any Tracker>) {
			        let __safeDI_trackerBuilder_left = __safeDI_trackerBuilder.left
			        func __safeDI_left() -> Left {
			            let __safeDI_trackerBuilder_inner = __safeDI_trackerBuilder_left.inner
			            func __safeDI_inner() -> Inner {
			                let __safeDI_trackerBuilder_xBuilder = __safeDI_trackerBuilder_inner.xBuilder
			                func __safeDI_xBuilder() -> X {
			                    let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			                    func __safeDI_y() -> Y {
			                        let token = Token()
			                        return Y(token: token, xBuilder: xBuilder)
			                    }
			                    let y: Y = __safeDI_y()
			                    let __safeDI_trackerBuilder_mid = __safeDI_trackerBuilder_xBuilder.mid(xBuilder, y)
			                    func __safeDI_mid() -> Mid {
			                        let token = Token()
			                        let tracker: any Tracker = __safeDI_trackerBuilder_mid.tracker(token)
			                        return Mid(token: token, tracker: tracker)
			                    }
			                    let mid: Mid = __safeDI_mid()
			                    return X(mid: mid, y: y)
			                }
			                let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			                return Inner(xBuilder: xBuilder)
			            }
			            let inner: Inner = __safeDI_inner()
			            return Left(inner: inner)
			        }
			        let left: Left = __safeDI_left()
			        let __safeDI_trackerBuilder_xBuilder = __safeDI_trackerBuilder.xBuilder(left)
			        func __safeDI_xBuilder() -> X {
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            func __safeDI_y() -> Y {
			                let token = Token()
			                return Y(token: token, xBuilder: xBuilder)
			            }
			            let y: Y = __safeDI_y()
			            let __safeDI_trackerBuilder_mid = __safeDI_trackerBuilder_xBuilder.mid(xBuilder, y)
			            func __safeDI_mid() -> Mid {
			                let token = Token()
			                let tracker: any Tracker = __safeDI_trackerBuilder_mid.tracker(token)
			                return Mid(token: token, tracker: tracker)
			            }
			            let mid: Mid = __safeDI_mid()
			            return X(mid: mid, y: y)
			        }
			        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			        self.init(left: left, xBuilder: xBuilder)
			    }
			}

			extension Home {
			    public enum __safeDI_Home_022812DCA73A6E98 {}
			}
			""" : """
			extension Home {
			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier<__safeDI_Built> {
			        public let xBuilder: __safeDI_TrackerCarrier_X<__safeDI_Built>
			        public let left: (Instantiator<X>) -> __safeDI_TrackerCarrier_Left<__safeDI_Built>

			        public init(xBuilder: __safeDI_TrackerCarrier_X<__safeDI_Built>, left: @escaping (Instantiator<X>) -> __safeDI_TrackerCarrier_Left<__safeDI_Built>) {
			            self.xBuilder = xBuilder
			            self.left = left
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(xBuilder: .init(__safeDI_noScope: __safeDI_builder), left: { _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_X<__safeDI_Built> {
			        public let mid: (Instantiator<X>, Y) -> __safeDI_TrackerCarrier_Mid<__safeDI_Built>

			        public init(mid: @escaping (Instantiator<X>, Y) -> __safeDI_TrackerCarrier_Mid<__safeDI_Built>) {
			            self.mid = mid
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(mid: { _, _ in .init(__safeDI_noScope: __safeDI_builder) })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Left<__safeDI_Built> {
			        public let inner: __safeDI_TrackerCarrier_Inner<__safeDI_Built>

			        public init(inner: __safeDI_TrackerCarrier_Inner<__safeDI_Built>) {
			            self.inner = inner
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(inner: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Mid<__safeDI_Built> {
			        public let tracker: (Token) -> __safeDI_Built

			        public init(tracker: @escaping (Token) -> __safeDI_Built) {
			            self.tracker = tracker
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(tracker: { _ in __safeDI_builder() })
			        }
			    }

			    /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
			    nonisolated public final class __safeDI_TrackerCarrier_Inner<__safeDI_Built> {
			        public let xBuilder: __safeDI_TrackerCarrier_X<__safeDI_Built>

			        public init(xBuilder: __safeDI_TrackerCarrier_X<__safeDI_Built>) {
			            self.xBuilder = xBuilder
			        }

			        @_alwaysEmitIntoClient
			        public convenience init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
			            self.init(xBuilder: .init(__safeDI_noScope: __safeDI_builder))
			        }
			    }

			    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
			    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
			    public init(__safeDI_trackerBuilder: __safeDI_TrackerCarrier<any Tracker>) {
			        let __safeDI_trackerBuilder_xBuilder = __safeDI_trackerBuilder.xBuilder
			        func __safeDI_xBuilder() -> X {
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            func __safeDI_y() -> Y {
			                let token = Token()
			                return Y(token: token, xBuilder: xBuilder)
			            }
			            let y: Y = __safeDI_y()
			            let __safeDI_trackerBuilder_mid = __safeDI_trackerBuilder_xBuilder.mid(xBuilder, y)
			            func __safeDI_mid() -> Mid {
			                let token = Token()
			                let tracker: any Tracker = __safeDI_trackerBuilder_mid.tracker(token)
			                return Mid(token: token, tracker: tracker)
			            }
			            let mid: Mid = __safeDI_mid()
			            return X(mid: mid, y: y)
			        }
			        let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			        let __safeDI_trackerBuilder_left = __safeDI_trackerBuilder.left(xBuilder)
			        func __safeDI_left() -> Left {
			            let __safeDI_trackerBuilder_inner = __safeDI_trackerBuilder_left.inner
			            func __safeDI_inner() -> Inner {
			                let __safeDI_trackerBuilder_xBuilder = __safeDI_trackerBuilder_inner.xBuilder
			                func __safeDI_xBuilder() -> X {
			                    let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			                    func __safeDI_y() -> Y {
			                        let token = Token()
			                        return Y(token: token, xBuilder: xBuilder)
			                    }
			                    let y: Y = __safeDI_y()
			                    let __safeDI_trackerBuilder_mid = __safeDI_trackerBuilder_xBuilder.mid(xBuilder, y)
			                    func __safeDI_mid() -> Mid {
			                        let token = Token()
			                        let tracker: any Tracker = __safeDI_trackerBuilder_mid.tracker(token)
			                        return Mid(token: token, tracker: tracker)
			                    }
			                    let mid: Mid = __safeDI_mid()
			                    return X(mid: mid, y: y)
			                }
			                let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			                return Inner(xBuilder: xBuilder)
			            }
			            let inner: Inner = __safeDI_inner()
			            return Left(inner: inner)
			        }
			        let left: Left = __safeDI_left()
			        self.init(xBuilder: xBuilder, left: left)
			    }
			}

			extension Home {
			    public enum __safeDI_Home_A55D67F57F47A0AD {}
			}
			""",
			expectedApp: leftFirst ? """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_trackerBuilder_Home() -> Home.__safeDI_TrackerCarrier<any Tracker> {
			            .init(left: __safeDI_trackerBuilder_Home_Left_Scope(), xBuilder: { values_left in __safeDI_trackerBuilder_Home_X_Scope() })
			        }
			        func __safeDI_trackerBuilder_Home_Left_Scope() -> Home.__safeDI_TrackerCarrier_Left<any Tracker> {
			            .init(inner: __safeDI_trackerBuilder_Home_Inner_Scope())
			        }
			        func __safeDI_trackerBuilder_Home_Inner_Scope() -> Home.__safeDI_TrackerCarrier_Inner<any Tracker> {
			            .init(xBuilder: __safeDI_trackerBuilder_Home_X_Scope())
			        }
			        func __safeDI_trackerBuilder_Home_X_Scope() -> Home.__safeDI_TrackerCarrier_X<any Tracker> {
			            .init(mid: { values_xBuilder, values_y in __safeDI_trackerBuilder_Home_Mid_Scope() })
			        }
			        func __safeDI_trackerBuilder_Home_Mid_Scope() -> Home.__safeDI_TrackerCarrier_Mid<any Tracker> {
			            .init(tracker: { scope_token in
			                let token = scope_token
			                let tracker: any Tracker = LiveTracker(token: token)
			                return tracker
			            })
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_022812DCA73A6E98.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Home(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""" : """
			#if canImport(Feature)
			import Feature
			#endif

			extension Root {
			    public init() {
			        func __safeDI_trackerBuilder_Home() -> Home.__safeDI_TrackerCarrier<any Tracker> {
			            .init(xBuilder: __safeDI_trackerBuilder_Home_X_Scope(), left: { values_xBuilder in __safeDI_trackerBuilder_Home_Left_Scope() })
			        }
			        func __safeDI_trackerBuilder_Home_X_Scope() -> Home.__safeDI_TrackerCarrier_X<any Tracker> {
			            .init(mid: { values_xBuilder, values_y in __safeDI_trackerBuilder_Home_Mid_Scope() })
			        }
			        func __safeDI_trackerBuilder_Home_Mid_Scope() -> Home.__safeDI_TrackerCarrier_Mid<any Tracker> {
			            .init(tracker: { scope_token in
			                let token = scope_token
			                let tracker: any Tracker = LiveTracker(token: token)
			                return tracker
			            })
			        }
			        func __safeDI_trackerBuilder_Home_Left_Scope() -> Home.__safeDI_TrackerCarrier_Left<any Tracker> {
			            .init(inner: __safeDI_trackerBuilder_Home_Inner_Scope())
			        }
			        func __safeDI_trackerBuilder_Home_Inner_Scope() -> Home.__safeDI_TrackerCarrier_Inner<any Tracker> {
			            .init(xBuilder: __safeDI_trackerBuilder_Home_X_Scope())
			        }
			        func __safeDI_home() -> Home {
			            _ = Home.__safeDI_Home_A55D67F57F47A0AD.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
			            return Home(__safeDI_trackerBuilder: __safeDI_trackerBuilder_Home())
			        }
			        let home: Home = __safeDI_home()
			        self.init(home: home)
			    }
			}
			""",
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_bindsNilToUnfulfilledDependency_whenTypeInstantiatingItOnlyIfAvailableIsReachedOnTwoPathsOfRootCallingSeam() async throws {
		// `AppRoot` calls the seam `Feature`, so its tree is built over the seam map, where `S`'s `extra`, instantiated only if
		// available and fulfilled by nothing, is a hole generator that holds no place: both `S`s bind it to `nil`. A
		// production root's tree has no `SeamHoles`, so the second `S` reuses the first's generator.
		let modules = SafeDIToolSeamBuilderParameterTests.modules(
			feature: [
				seamFixtureType(named: "Part", declarations: []),
				seamFixtureType(named: "Feature", isSeam: true, declarations: ["@Instantiated public let part: Part"]),
			],
			app: [
				"public protocol Extra {}",
				seamFixtureType(named: "S", declarations: ["@Instantiated(onlyIfAvailable: true) public let extra: (any Extra)?"]),
				seamFixtureType(named: "A", declarations: ["@Instantiated public let s: S"]),
				seamFixtureType(named: "B", declarations: ["@Instantiated public let s: S"]),
				seamFixtureType(named: "AppRoot", isRoot: true, declarations: ["@Instantiated public let a: A", "@Instantiated public let b: B", "@Instantiated public let feature: Feature"]),
			],
		)
		let (reuses, continuation) = AsyncStream.makeStream(of: String.self)
		let output = try await ConstructionMemoOracle.$reusedPlaceObserver.withValue({ concreteType, _ in continuation.yield(concreteType) }) { [modules] in
			try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		}
		continuation.finish()
		var reusesOfS = 0
		for await reusedType in reuses where reusedType == "S" {
			reusesOfS += 1
		}
		#expect(reusesOfS == 1)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension AppRoot {
		    public init() {
		        func __safeDI_a() -> A {
		            func __safeDI_s() -> S {
		                let extra: (any Extra)? = nil
		                return S(extra: extra)
		            }
		            let s: S = __safeDI_s()
		            return A(s: s)
		        }
		        let a: A = __safeDI_a()
		        func __safeDI_b() -> B {
		            func __safeDI_s() -> S {
		                let extra: (any Extra)? = nil
		                return S(extra: extra)
		            }
		            let s: S = __safeDI_s()
		            return B(s: s)
		        }
		        let b: B = __safeDI_b()
		        func __safeDI_feature() -> Feature {
		            _ = Feature.__safeDI_Feature_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Feature()
		        }
		        let feature: Feature = __safeDI_feature()
		        self.init(a: a, b: b, feature: feature)
		    }
		}
		""")
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectSeam(
		feature: [String],
		fulfillers: [String],
		root: String,
		probes: [DifferentialValueProbe],
		expectedFeature: String,
		expectedApp: String,
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature, app: fulfillers + [root])
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles["Feature.swift"] == generatedFileHeader + expectedFeature, sourceLocation: sourceLocation)
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + expectedApp, sourceLocation: sourceLocation)
		guard compileVerificationIsEnabled else { return }
		let visibleModules = SafeDIToolSeamBuilderParameterTests.modules(feature: feature + fulfillers, app: [root])
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: probes,
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
