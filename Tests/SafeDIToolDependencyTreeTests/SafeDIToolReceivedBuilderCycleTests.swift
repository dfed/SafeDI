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

/// A type can receive an instantiator declared above it even when that instantiator builds the receiver or a type
/// above it: builders of one scope whose trees receive one another form a loop, which is accepted when every property
/// on it is an instantiator. Each builder function on a loop starts by wrapping again the functions of the members its
/// tree receives, so each receiver gets an instantiator of its own and a tree released by its owner is freed. A loop
/// with a property on it that is not an instantiator stays an error.
struct SafeDIToolReceivedBuilderCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Builders that receive each other

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsEachOtherBuilderInsideEachFunction_whenTwoRootBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsTheNextBuilderInsideEachFunction_whenThreeRootBuildersReceiveOneAnotherInARing() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let cBuilder: Instantiator<C>"),
			Self.type("C", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return B(cBuilder: cBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        func __safeDI_cBuilder() -> C {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return C(aBuilder: aBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenTypeReceivesBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let nodeBuilder: Instantiator<Node>"),
			Self.type("Node", "@Received let nodeBuilder: Instantiator<Node>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_nodeBuilder() -> Node {
			            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			            return Node(nodeBuilder: nodeBuilder)
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        self.init(nodeBuilder: nodeBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuildersInTheOrderTheBodyFirstReceivesThem_whenTwoChildrenBuildOneTypeThatReceivesALaterMember() async throws {
		// `A`'s body first receives `cBuilder`, in the `Shared` its first child builds, then `bBuilder`, in its second child,
		// which builds `Shared` again: the function rebinds them in that order, which neither their labels nor the root's
		// declaration order give.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", "@Instantiated let left: Left", "@Instantiated let right: Right"),
			Self.type("Left", "@Instantiated let shared: Shared"),
			Self.type("Right", "@Received let bBuilder: Instantiator<B>", "@Instantiated let shared: Shared"),
			Self.type("Shared", "@Received let cBuilder: Instantiator<C>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
			Self.type("C", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            func __safeDI_left() -> Left {
			                let shared = Shared(cBuilder: cBuilder)
			                return Left(shared: shared)
			            }
			            let left: Left = __safeDI_left()
			            func __safeDI_right() -> Right {
			                let shared = Shared(cBuilder: cBuilder)
			                return Right(bBuilder: bBuilder, shared: shared)
			            }
			            let right: Right = __safeDI_right()
			            return A(left: left, right: right)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        func __safeDI_cBuilder() -> C {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return C(aBuilder: aBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenConstantInsideItsTreeReceivesIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let b = B(aBuilder: aBuilder)
			            return A(b: b)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenLazilyInstantiatedValueInsideItsTreeReceivesIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("A", "@Instantiated let b: LazilyInstantiated<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_b() -> B {
			                B(aBuilder: aBuilder)
			            }
			            let b = LazilyInstantiated<B>(__safeDI_b)
			            return A(b: b)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsRouterBuilderInsideItsFunction_whenScreensTheRouterInstantiatesReceiveIt() async throws {
		// The adopter's router: the router instantiates the screens' builders, and each screen receives `routerBuilder`, under a nested builder.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			"""
			public protocol Router: AnyObject {
			    func open(_ name: String, id: Int) -> Screen
			}

			open class Screen {
			    public init() {}
			}

			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Home: Screen, Instantiable {
			    public init(id: Int, service: Service, routerBuilder: ErasedInstantiator<(), any Router>) {
			        self.id = id
			        self.service = service
			        self.routerBuilder = routerBuilder
			        super.init()
			    }

			    @Forwarded let id: Int
			    @Received let service: Service
			    @Received let routerBuilder: ErasedInstantiator<(), any Router>
			}
			""",
			"""
			@Instantiable
			public final class Detail: Screen, Instantiable {
			    public init(id: Int, service: Service, routerBuilder: ErasedInstantiator<(), any Router>) {
			        self.id = id
			        self.service = service
			        self.routerBuilder = routerBuilder
			        super.init()
			    }

			    @Forwarded let id: Int
			    @Received let service: Service
			    @Received let routerBuilder: ErasedInstantiator<(), any Router>
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [Router.self])
			public final class OwningRouter: Router, Instantiable {
			    public init(service: Service, homeBuilder: ErasedInstantiator<Int, Screen>, detailBuilder: ErasedInstantiator<Int, Screen>) {
			        self.service = service
			        self.homeBuilder = homeBuilder
			        self.detailBuilder = detailBuilder
			    }

			    public func open(_ name: String, id: Int) -> Screen {
			        name == "home" ? homeBuilder.instantiate(id) : detailBuilder.instantiate(id)
			    }

			    @Received let service: Service
			    @Instantiated(fulfilledByType: "Home") let homeBuilder: ErasedInstantiator<Int, Screen>
			    @Instantiated(fulfilledByType: "Detail") let detailBuilder: ErasedInstantiator<Int, Screen>
			}
			""",
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: Service, routerBuilder: ErasedInstantiator<(), any Router>) {
			        self.service = service
			        self.routerBuilder = routerBuilder
			    }

			    @Instantiated let service: Service
			    @Instantiated(fulfilledByType: "OwningRouter") let routerBuilder: ErasedInstantiator<(), any Router>
			}
			""",
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        func __safeDI_routerBuilder() -> OwningRouter {
			            let routerBuilder = ErasedInstantiator<(), any Router>(__safeDI_routerBuilder)
			            func __safeDI_homeBuilder(id: Int) -> Home {
			                Home(id: id, service: service, routerBuilder: routerBuilder)
			            }
			            let homeBuilder = ErasedInstantiator<Int, Screen> {
			                __safeDI_homeBuilder(id: $0)
			            }
			            func __safeDI_detailBuilder(id: Int) -> Detail {
			                Detail(id: id, service: service, routerBuilder: routerBuilder)
			            }
			            let detailBuilder = ErasedInstantiator<Int, Screen> {
			                __safeDI_detailBuilder(id: $0)
			            }
			            return OwningRouter(service: service, homeBuilder: homeBuilder, detailBuilder: detailBuilder)
			        }
			        let routerBuilder = ErasedInstantiator<(), any Router>(__safeDI_routerBuilder)
			        self.init(service: service, routerBuilder: routerBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsRouterBuilderInsideEachScreenFunction_whenRouterReceivesTheScreensBuilders() async throws {
		// The adopter's router in its other spelling: the root declares the screens' builders and the router's, and the router receives the screens' builders.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			"""
			public protocol Router: AnyObject {
			    func open(_ name: String, id: Int) -> Screen
			}

			open class Screen {
			    public init() {}
			}

			@Instantiable
			public final class Service: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class Home: Screen, Instantiable {
			    public init(id: Int, service: Service, routerBuilder: ErasedInstantiator<(), any Router>) {
			        self.id = id
			        self.service = service
			        self.routerBuilder = routerBuilder
			        super.init()
			    }

			    @Forwarded let id: Int
			    @Received let service: Service
			    @Received let routerBuilder: ErasedInstantiator<(), any Router>
			}
			""",
			"""
			@Instantiable
			public final class Detail: Screen, Instantiable {
			    public init(id: Int, service: Service, routerBuilder: ErasedInstantiator<(), any Router>) {
			        self.id = id
			        self.service = service
			        self.routerBuilder = routerBuilder
			        super.init()
			    }

			    @Forwarded let id: Int
			    @Received let service: Service
			    @Received let routerBuilder: ErasedInstantiator<(), any Router>
			}
			""",
			"""
			@Instantiable(fulfillingAdditionalTypes: [Router.self])
			public final class ReceivingRouter: Router, Instantiable {
			    public init(homeBuilder: ErasedInstantiator<Int, Screen>, detailBuilder: ErasedInstantiator<Int, Screen>) {
			        self.homeBuilder = homeBuilder
			        self.detailBuilder = detailBuilder
			    }

			    public func open(_ name: String, id: Int) -> Screen {
			        name == "home" ? homeBuilder.instantiate(id) : detailBuilder.instantiate(id)
			    }

			    @Received let homeBuilder: ErasedInstantiator<Int, Screen>
			    @Received let detailBuilder: ErasedInstantiator<Int, Screen>
			}
			""",
			"""
			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
			    public init(service: Service, routerBuilder: ErasedInstantiator<(), any Router>, homeBuilder: ErasedInstantiator<Int, Screen>, detailBuilder: ErasedInstantiator<Int, Screen>) {
			        self.service = service
			        self.routerBuilder = routerBuilder
			        self.homeBuilder = homeBuilder
			        self.detailBuilder = detailBuilder
			    }

			    @Instantiated let service: Service
			    @Instantiated(fulfilledByType: "ReceivingRouter") let routerBuilder: ErasedInstantiator<(), any Router>
			    @Instantiated(fulfilledByType: "Home") let homeBuilder: ErasedInstantiator<Int, Screen>
			    @Instantiated(fulfilledByType: "Detail") let detailBuilder: ErasedInstantiator<Int, Screen>
			}
			""",
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        func __safeDI_routerBuilder() -> ReceivingRouter {
			            let homeBuilder = ErasedInstantiator<Int, Screen> {
			                __safeDI_homeBuilder(id: $0)
			            }
			            let detailBuilder = ErasedInstantiator<Int, Screen> {
			                __safeDI_detailBuilder(id: $0)
			            }
			            return ReceivingRouter(homeBuilder: homeBuilder, detailBuilder: detailBuilder)
			        }
			        let routerBuilder = ErasedInstantiator<(), any Router>(__safeDI_routerBuilder)
			        func __safeDI_homeBuilder(id: Int) -> Home {
			            let routerBuilder = ErasedInstantiator<(), any Router>(__safeDI_routerBuilder)
			            return Home(id: id, service: service, routerBuilder: routerBuilder)
			        }
			        let homeBuilder = ErasedInstantiator<Int, Screen> {
			            __safeDI_homeBuilder(id: $0)
			        }
			        func __safeDI_detailBuilder(id: Int) -> Detail {
			            let routerBuilder = ErasedInstantiator<(), any Router>(__safeDI_routerBuilder)
			            return Detail(id: id, service: service, routerBuilder: routerBuilder)
			        }
			        let detailBuilder = ErasedInstantiator<Int, Screen> {
			            __safeDI_detailBuilder(id: $0)
			        }
			        self.init(service: service, routerBuilder: routerBuilder, homeBuilder: homeBuilder, detailBuilder: detailBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsErasingWrapperAsDeclared_whenBuilderErasedToConcreteExistentialIsOnLoop() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated(fulfilledByType: \"A\", erasedToConcreteExistential: true) let aBuilder: ErasedInstantiator<(), AnyScreen>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>", conformances: ", Screen"),
			Self.type("B", "@Received let aBuilder: ErasedInstantiator<(), AnyScreen>"),
			"""
			public protocol Screen {}

			public struct AnyScreen {
			    public init(_ screen: some Screen) {}
			}
			""",
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = ErasedInstantiator<(), AnyScreen> {
			            AnyScreen(__safeDI_aBuilder())
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = ErasedInstantiator<(), AnyScreen> {
			                AnyScreen(__safeDI_aBuilder())
			            }
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsLoopOfNestedScope_whenLoopIsDeclaredBelowRootAndReceivesRootBuilder() async throws {
		// A loop declared below the root: `Flow`, built by an instantiator, forwards `flowID`, instantiates a `session` and declares two builders that receive each other; `ScreenA` also receives the root's `flowBuilder` from inside the tree it builds.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			"""
			@Instantiable
			public final class Session: Instantiable {
			    public init() {}
			}
			""",
			"""
			@Instantiable
			public final class ScreenA: Instantiable {
			    public init(id: Int, flowID: String, session: Session, screenBBuilder: Instantiator<ScreenB>, flowBuilder: Instantiator<Flow>) {
			        self.id = id
			        self.flowID = flowID
			        self.session = session
			        self.screenBBuilder = screenBBuilder
			        self.flowBuilder = flowBuilder
			    }

			    @Forwarded let id: Int
			    @Received let flowID: String
			    @Received let session: Session
			    @Received let screenBBuilder: Instantiator<ScreenB>
			    @Received let flowBuilder: Instantiator<Flow>
			}
			""",
			"""
			@Instantiable
			public final class ScreenB: Instantiable {
			    public init(id: Int, flowID: String, session: Session, screenABuilder: Instantiator<ScreenA>?) {
			        self.id = id
			        self.flowID = flowID
			        self.session = session
			        self.screenABuilder = screenABuilder
			    }

			    @Forwarded let id: Int
			    @Received let flowID: String
			    @Received let session: Session
			    @Received(onlyIfAvailable: true) let screenABuilder: Instantiator<ScreenA>?
			}
			""",
			"""
			@Instantiable
			public final class Flow: Instantiable {
			    public init(flowID: String, session: Session, screenABuilder: Instantiator<ScreenA>, screenBBuilder: Instantiator<ScreenB>) {
			        self.flowID = flowID
			        self.session = session
			        self.screenABuilder = screenABuilder
			        self.screenBBuilder = screenBBuilder
			    }

			    @Forwarded let flowID: String
			    @Instantiated let session: Session
			    @Instantiated let screenABuilder: Instantiator<ScreenA>
			    @Instantiated let screenBBuilder: Instantiator<ScreenB>
			}
			""",
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let flowBuilder: Instantiator<Flow>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flowBuilder(flowID: String) -> Flow {
			            let flowBuilder = Instantiator<Flow> {
			                __safeDI_flowBuilder(flowID: $0)
			            }
			            let session = Session()
			            func __safeDI_screenABuilder(id: Int) -> ScreenA {
			                let screenBBuilder = Instantiator<ScreenB> {
			                    __safeDI_screenBBuilder(id: $0)
			                }
			                return ScreenA(id: id, flowID: flowID, session: session, screenBBuilder: screenBBuilder, flowBuilder: flowBuilder)
			            }
			            let screenABuilder = Instantiator<ScreenA> {
			                __safeDI_screenABuilder(id: $0)
			            }
			            func __safeDI_screenBBuilder(id: Int) -> ScreenB {
			                let screenABuilder = Instantiator<ScreenA> {
			                    __safeDI_screenABuilder(id: $0)
			                }
			                return ScreenB(id: id, flowID: flowID, session: session, screenABuilder: screenABuilder)
			            }
			            let screenBBuilder = Instantiator<ScreenB> {
			                __safeDI_screenBBuilder(id: $0)
			            }
			            return Flow(flowID: flowID, session: session, screenABuilder: screenABuilder, screenBBuilder: screenBBuilder)
			        }
			        let flowBuilder = Instantiator<Flow> {
			            __safeDI_flowBuilder(flowID: $0)
			        }
			        self.init(flowBuilder: flowBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsReceiversRenameSource_whenTypeRenamesBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Screen", "@Received(fulfilledByDependencyNamed: \"screenBuilder\", ofType: Instantiator<Screen>.self) let next: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 7)
			            let next: Instantiator<Screen> = screenBuilder
			            #sourceLocation()
			            return Screen(next: next)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsDeclaringScopesRenameUnderItsOwnLabel_whenTypeReceivesRenameOfBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Received(fulfilledByDependencyNamed: \"screenBuilder\", ofType: Instantiator<Screen>.self) let detailBuilder: Instantiator<Screen>"),
			Self.type("Screen", "@Received let detailBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let detailBuilder: Instantiator<Screen> = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Screen(detailBuilder: detailBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        #sourceLocation(file: "\(output.fixtures["Root.swift"])", line: 9)
			        let detailBuilder: Instantiator<Screen> = screenBuilder
			        #sourceLocation()
			        self.init(screenBuilder: screenBuilder, detailBuilder: detailBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsLoopInsideFunctionItsMemberBuildsAgain_whenTypeBeneathMemberClosesCycleOnLoopsEnclosingFunction() async throws {
		// `F`'s builders `aBuilder` and `bBuilder` receive each other, and `H`, beneath `B`, builds `F` again: `A`'s view
		// rebinds a sibling whose function closes a cycle beneath its own body, so the type key keys it by its declarations.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let fBuilder: Instantiator<F>"),
			Self.type("F", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>", "@Instantiated let h: H"),
			Self.type("H", "@Instantiated let fBuilder: Instantiator<F>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_fBuilder() -> F {
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_bBuilder() -> B {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                func __safeDI_h() -> H {
			                    let fBuilder = Instantiator<F>(__safeDI_fBuilder)
			                    return H(fBuilder: fBuilder)
			                }
			                let h: H = __safeDI_h()
			                return B(aBuilder: aBuilder, h: h)
			            }
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return F(aBuilder: aBuilder, bBuilder: bBuilder)
			        }
			        let fBuilder = Instantiator<F>(__safeDI_fBuilder)
			        self.init(fBuilder: fBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Tests – Sendable builders

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsSendableTwins_whenSendableBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: SendableInstantiator<A>", "@Instantiated(fulfilledByType: \"B\") let bBuilder: SendableErasedInstantiator<(), any Screen>"),
			Self.type("A", "@Received let bBuilder: SendableErasedInstantiator<(), any Screen>", conformances: ", Sendable"),
			Self.type("B", "@Received let aBuilder: SendableInstantiator<A>", conformances: ", Screen"),
			"""
			public protocol Screen: Sendable {}
			""",
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_aBuilder() -> A {
			            let bBuilder = SendableErasedInstantiator<(), any Screen>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			        @Sendable nonisolated func __safeDI_bBuilder() -> B {
			            let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = SendableErasedInstantiator<(), any Screen>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsSendableCaptureError_whenSendableBuilderRequiresBuilderThatIsNotSendableOnItsLoop() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):7:5: error: @Received property `bBuilder: Instantiator<B>` cannot be received inside a `@Sendable` function in chain: Root -> A. SafeDI builds `aBuilder: SendableInstantiator<A>` on `Root` in a `@Sendable` function, which cannot capture `bBuilder: Instantiator<B>` on `Root`, because `Instantiator<B>` is not `Sendable`. Declare `bBuilder` on `Root`, and this property, as `SendableInstantiator<B>` to fix. `SendableInstantiator<B>` builds `B` in a `@Sendable` function, so what the tree of `B` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):9:5: note: `bBuilder: Instantiator<B>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: SendableInstantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("A", "@Received let bBuilder: Instantiator<B>", conformances: ", Sendable"),
				Self.type("B", "@Received let aBuilder: SendableInstantiator<A>"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsSendableCaptureError_whenSendableBuilderDeclaredSecondRequiresBuilderThatIsNotSendableOnItsLoop() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):7:5: error: @Received property `aBuilder: Instantiator<A>` cannot be received inside a `@Sendable` function in chain: Root -> B. SafeDI builds `bBuilder: SendableInstantiator<B>` on `Root` in a `@Sendable` function, which cannot capture `aBuilder: Instantiator<A>` on `Root`, because `Instantiator<A>` is not `Sendable`. Declare `aBuilder` on `Root`, and this property, as `SendableInstantiator<A>` to fix. `SendableInstantiator<A>` builds `A` in a `@Sendable` function, so what the tree of `A` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):8:5: note: `aBuilder: Instantiator<A>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: SendableInstantiator<B>"),
				Self.type("A", "@Received let bBuilder: SendableInstantiator<B>"),
				Self.type("B", "@Received let aBuilder: Instantiator<A>", conformances: ", Sendable"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – Receives only if available

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilder_whenTypeReceivesBuilderThatBuildsItOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let nodeBuilder: Instantiator<Node>"),
			Self.type("Node", "@Received(onlyIfAvailable: true) let nodeBuilder: Instantiator<Node>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_nodeBuilder() -> Node {
			            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			            return Node(nodeBuilder: nodeBuilder)
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        self.init(nodeBuilder: nodeBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilder_whenConstantInsideItsTreeReceivesBuilderOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            let b = B(aBuilder: aBuilder)
			            return A(b: b)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachBuilder_whenTwoBuildersReceiveEachOtherOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilder_whenBuilderReceivesOnlyIfAvailableBuilderThatRequiresIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilder_whenTypeRenamesBuilderThatBuildsItOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Screen", "@Received(fulfilledByDependencyNamed: \"screenBuilder\", ofType: Instantiator<Screen>.self, onlyIfAvailable: true) let next: Instantiator<Screen>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 7)
			            let next: Instantiator<Screen>? = screenBuilder
			            #sourceLocation()
			            return Screen(next: next)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesDeclaringScopesRename_whenTypeReceivesRenameOfBuilderThatBuildsItOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Received(fulfilledByDependencyNamed: \"screenBuilder\", ofType: Instantiator<Screen>.self) let detailBuilder: Instantiator<Screen>"),
			Self.type("Screen", "@Received(onlyIfAvailable: true) let detailBuilder: Instantiator<Screen>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let detailBuilder: Instantiator<Screen> = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Screen(detailBuilder: detailBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        #sourceLocation(file: "\(output.fixtures["Root.swift"])", line: 9)
			        let detailBuilder: Instantiator<Screen> = screenBuilder
			        #sourceLocation()
			        self.init(screenBuilder: screenBuilder, detailBuilder: detailBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsDeclaringScopesOnlyIfAvailableRename_whenTypeReceivesItOnlyIfAvailableInsideTheBuildersTree() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Received(fulfilledByDependencyNamed: \"screenBuilder\", ofType: Instantiator<Screen>.self, onlyIfAvailable: true) let detailBuilder: Instantiator<Screen>?"),
			Self.type("Screen", "@Received(onlyIfAvailable: true) let detailBuilder: Instantiator<Screen>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let detailBuilder: Instantiator<Screen>? = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Screen(detailBuilder: detailBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        #sourceLocation(file: "\(output.fixtures["Root.swift"])", line: 9)
			        let detailBuilder: Instantiator<Screen>? = screenBuilder
			        #sourceLocation()
			        self.init(screenBuilder: screenBuilder, detailBuilder: detailBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsDeclaringScopesOnlyIfAvailableRename_whenTypeRequiresItInsideTheBuildersTree() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Received(fulfilledByDependencyNamed: \"screenBuilder\", ofType: Instantiator<Screen>.self, onlyIfAvailable: true) let detailBuilder: Instantiator<Screen>?"),
			Self.type("Screen", "@Received let detailBuilder: Instantiator<Screen>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let detailBuilder: Instantiator<Screen>? = Instantiator<Screen>(__safeDI_screenBuilder)
			            return Screen(detailBuilder: detailBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        #sourceLocation(file: "\(output.fixtures["Root.swift"])", line: 9)
			        let detailBuilder: Instantiator<Screen>? = screenBuilder
			        #sourceLocation()
			        self.init(screenBuilder: screenBuilder, detailBuilder: detailBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsNilForBuilderAndBuilderForValue_whenValueWaitsInTheCircleTheReceiveWouldClose() async throws {
		// `A` requires `bBuilder` and `v`; `v` receives `bBuilder` only if available, and gets it; `B` receives `aBuilder` only if available, and gets `nil`, since `v`, which is not an instantiator, waits in the circle that receive would close.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let v: V"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>", "@Received let v: V"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
			Self.type("V", "@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_bBuilder() -> B {
			            B(aBuilder: nil)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let v = V(bBuilder: bBuilder)
			        func __safeDI_aBuilder() -> A {
			            A(bBuilder: bBuilder, v: v)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder, v: v)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNeitherContestedBuilder_whenTwoReceivesCanEachBeGivenAloneButNotTogether() async throws {
		// `b` receives `a` and `c` receives `d` only if available. Either alone would close a circle of instantiators, but both together close one through `v`, which is not one, so neither is given.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: Instantiator<A>", "@Instantiated let b: Instantiator<B>", "@Instantiated let c: Instantiator<C>", "@Instantiated let d: Instantiator<D>", "@Instantiated let v: V"),
			Self.type("A", "@Received let b: Instantiator<B>", "@Received let v: V"),
			Self.type("B", "@Received(onlyIfAvailable: true) let a: Instantiator<A>?"),
			Self.type("V", "@Received let c: Instantiator<C>"),
			Self.type("C", "@Received(onlyIfAvailable: true) let d: Instantiator<D>?"),
			Self.type("D", "@Received let c: Instantiator<C>", "@Received let b: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_b() -> B {
			            B(a: nil)
			        }
			        let b = Instantiator<B>(__safeDI_b)
			        func __safeDI_c() -> C {
			            C(d: nil)
			        }
			        let c = Instantiator<C>(__safeDI_c)
			        let v = V(c: c)
			        func __safeDI_a() -> A {
			            A(b: b, v: v)
			        }
			        let a = Instantiator<A>(__safeDI_a)
			        func __safeDI_d() -> D {
			            D(c: c, b: b)
			        }
			        let d = Instantiator<D>(__safeDI_d)
			        self.init(a: a, b: b, c: c, d: d, v: v)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNeitherContestedBuilder_whenContestedSiblingsAreDeclaredInAnotherOrder() async throws {
		// The test above with the root's properties declared in another order: the same receives are `nil`.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let d: Instantiator<D>", "@Instantiated let v: V", "@Instantiated let c: Instantiator<C>", "@Instantiated let b: Instantiator<B>", "@Instantiated let a: Instantiator<A>"),
			Self.type("A", "@Received let b: Instantiator<B>", "@Received let v: V"),
			Self.type("B", "@Received(onlyIfAvailable: true) let a: Instantiator<A>?"),
			Self.type("V", "@Received let c: Instantiator<C>"),
			Self.type("C", "@Received(onlyIfAvailable: true) let d: Instantiator<D>?"),
			Self.type("D", "@Received let c: Instantiator<C>", "@Received let b: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_c() -> C {
			            C(d: nil)
			        }
			        let c = Instantiator<C>(__safeDI_c)
			        func __safeDI_b() -> B {
			            B(a: nil)
			        }
			        let b = Instantiator<B>(__safeDI_b)
			        func __safeDI_d() -> D {
			            D(c: c, b: b)
			        }
			        let d = Instantiator<D>(__safeDI_d)
			        let v = V(c: c)
			        func __safeDI_a() -> A {
			            A(b: b, v: v)
			        }
			        let a = Instantiator<A>(__safeDI_a)
			        self.init(d: d, v: v, c: c, b: b, a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNil_whenConstantOnTheCircleRequiresBuilderThatReceivesItOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let router: Router", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Router", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Screen", "@Received(onlyIfAvailable: true) let router: Router?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            Screen(router: nil)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        let router = Router(screenBuilder: screenBuilder)
			        self.init(router: router, screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsSendableCaptureError_whenSendableBuilderReceivesBuilderThatIsNotSendableOnlyIfAvailableOnItsLoop() async {
		// `B` requires `aBuilder`, so `A`'s receive of `bBuilder` only if available closes a loop of instantiators and is
		// given: the error the same receive is outside a loop.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):7:5: error: @Received property `bBuilder: Instantiator<B>?` cannot be received inside a `@Sendable` function in chain: Root -> A. SafeDI builds `aBuilder: SendableInstantiator<A>` on `Root` in a `@Sendable` function, which cannot capture `bBuilder: Instantiator<B>` on `Root`, because `Instantiator<B>` is not `Sendable`. Declare `bBuilder` on `Root`, and this property, as `SendableInstantiator<B>` to fix. `SendableInstantiator<B>` builds `B` in a `@Sendable` function, so what the tree of `B` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):9:5: note: `bBuilder: Instantiator<B>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: SendableInstantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("A", "@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?", conformances: ", Sendable"),
				Self.type("B", "@Received let aBuilder: SendableInstantiator<A>"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – A builder its own type receives, beside a builder that waits on it through a value

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenItsTypeRenamesItBesideAnOnlyIfAvailableReceiveOfABuilderWaitingOnItThroughAValue() async throws {
		// `t4Builder`'s receive of `t2Builder` is left `nil`, since `t2Builder` waits on `t3`, which waits on `t4Builder`.
		// That receive closes a circle through the value `t3`, so it is not given, and `t4Builder` still receives itself.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Instantiated let t4: T4"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self) let t4BuilderAlias: Instantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: Instantiator<T4> = t4Builder
			            #sourceLocation()
			            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t3() -> T3 {
			            func __safeDI_t4() -> T4 {
			                #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			                let t4BuilderAlias: Instantiator<T4> = t4Builder
			                #sourceLocation()
			                return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			            }
			            let t4: T4 = __safeDI_t4()
			            return T3(t4: t4)
			        }
			        let t3: T3 = __safeDI_t3()
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenItsTypeReceivesItBesideAnOnlyIfAvailableReceiveOfABuilderWaitingOnItThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Instantiated let t4: T4"),
			Self.type("T4", "@Received let t4Builder: Instantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t3() -> T3 {
			            let t4 = T4(t4Builder: t4Builder, t2Builder: nil)
			            return T3(t4: t4)
			        }
			        let t3: T3 = __safeDI_t3()
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenItsTypeRenamesItBesideAnOnlyIfAvailableReceiveOfABuilderRequiringAValueBuiltWithIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received let t3: T3"),
			Self.type("T3", "@Instantiated let t4: T4"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self) let t4BuilderAlias: Instantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: Instantiator<T4> = t4Builder
			            #sourceLocation()
			            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t3() -> T3 {
			            func __safeDI_t4() -> T4 {
			                #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			                let t4BuilderAlias: Instantiator<T4> = t4Builder
			                #sourceLocation()
			                return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			            }
			            let t4: T4 = __safeDI_t4()
			            return T3(t4: t4)
			        }
			        let t3: T3 = __safeDI_t3()
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenItsTypeRenamesItBesideARequiredReceiveOfABuilderReceivingAValueBuiltWithItOnlyIfAvailable() async throws {
		// Here `t2Builder` is built first, and its receive of `t3` is left `nil`.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Instantiated let t4: T4"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self) let t4BuilderAlias: Instantiator<T4>", "@Received let t2Builder: Instantiator<T2>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: nil)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: Instantiator<T4> = t4Builder
			            #sourceLocation()
			            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: t2Builder)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t3() -> T3 {
			            func __safeDI_t4() -> T4 {
			                #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			                let t4BuilderAlias: Instantiator<T4> = t4Builder
			                #sourceLocation()
			                return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: t2Builder)
			            }
			            let t4: T4 = __safeDI_t4()
			            return T3(t4: t4)
			        }
			        let t3: T3 = __safeDI_t3()
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenItsTypeRenamesItOnlyIfAvailableBesideAnOnlyIfAvailableReceiveOfABuilderReceivingAValueBuiltWithIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Instantiated let t4: T4"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self, onlyIfAvailable: true) let t4BuilderAlias: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t3() -> T3 {
			            func __safeDI_t4() -> T4 {
			                #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			                let t4BuilderAlias: Instantiator<T4>? = nil
			                #sourceLocation()
			                return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			            }
			            let t4: T4 = __safeDI_t4()
			            return T3(t4: t4)
			        }
			        let t3: T3 = __safeDI_t3()
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: Instantiator<T4>? = t4Builder
			            #sourceLocation()
			            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: t2Builder)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsSendableBuilderInsideItsOwnFunction_whenItsTypeRenamesItBesideAnOnlyIfAvailableReceiveOfABuilderWaitingOnItThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: SendableInstantiator<T2>", "@Instantiated let t4Builder: SendableInstantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?", conformances: ", Sendable"),
			Self.type("T3", "@Instantiated let t4: T4", conformances: ", Sendable"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: SendableInstantiator<T4>.self) let t4BuilderAlias: SendableInstantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: SendableInstantiator<T2>?", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_t4Builder() -> T4 {
			            let t4Builder = SendableInstantiator<T4>(__safeDI_t4Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: SendableInstantiator<T4> = t4Builder
			            #sourceLocation()
			            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			        }
			        let t4Builder = SendableInstantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t3() -> T3 {
			            func __safeDI_t4() -> T4 {
			                #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			                let t4BuilderAlias: SendableInstantiator<T4> = t4Builder
			                #sourceLocation()
			                return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			            }
			            let t4: T4 = __safeDI_t4()
			            return T3(t4: t4)
			        }
			        let t3: T3 = __safeDI_t3()
			        @Sendable nonisolated func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = SendableInstantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsSendableBuilderInsideItsOwnFunction_whenItsTypeRenamesItBesideAnOnlyIfAvailableReceiveOfABuilderThatIsNotSendableWaitingOnItThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: SendableInstantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Instantiated let t4: T4"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: SendableInstantiator<T4>.self) let t4BuilderAlias: SendableInstantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?", conformances: ", @unchecked Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_t4Builder() -> T4 {
			            let t4Builder = SendableInstantiator<T4>(__safeDI_t4Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: SendableInstantiator<T4> = t4Builder
			            #sourceLocation()
			            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			        }
			        let t4Builder = SendableInstantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t3() -> T3 {
			            func __safeDI_t4() -> T4 {
			                #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			                let t4BuilderAlias: SendableInstantiator<T4> = t4Builder
			                #sourceLocation()
			                return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			            }
			            let t4: T4 = __safeDI_t4()
			            return T3(t4: t4)
			        }
			        let t3: T3 = __safeDI_t3()
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsEachBuilderOfTwoBuilderLoop_whenOneReceivesOnlyIfAvailableABuilderWaitingOnTheLoopThroughAValue() async throws {
		// `aBuilder` and `bBuilder` receive each other. `aBuilder`'s receive of `cBuilder` is left `nil`, since `cBuilder`
		// waits on `v`, which waits on `aBuilder`; that circle holds the value `v`, so the receive is not given, and the two
		// builders are still a loop.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.twoBuilderLoopBesideReceiveWaitingOnItThroughValue, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder, cBuilder: nil)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let v = V(aBuilder: aBuilder)
			        func __safeDI_cBuilder() -> C {
			            C(v: v)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder, v: v)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsDependencyCycleError_whenTypeRenamesItsOwnLazilyInstantiatedWrapperBesideAnOnlyIfAvailableReceiveOfABuilderWaitingOnIt() async {
		// A lazily instantiated dependency is validated as the constant it stands for, so receiving it inside its own tree is
		// a cycle with no instantiator on it.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["T4.swift"]):8:5: error: Dependency cycle: @Instantiated `lazyT4: T4` -> @Received `lazyT4: T4`. `lazyT4: T4` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `lazyT4: LazilyInstantiated<T4>` is validated as `lazyT4: T4`.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let lazyT4: LazilyInstantiated<T4>", "@Instantiated let t3: T3"),
				Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
				Self.type("T3", "@Instantiated let t4: T4"),
				Self.type("T4", "@Received(fulfilledByDependencyNamed: \"lazyT4\", ofType: LazilyInstantiated<T4>.self) let lazyT4Alias: LazilyInstantiated<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – A builder its own type receives only if available, beside a receive left nil

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuilds_whenThatTypeReceivesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		// `t4Builder`'s receive of `t2Builder` is left `nil`, since `t2Builder` waits on `t3`, which requires `t4Builder`:
		// that circle holds the value `t3`. `T4`'s receive of `t4Builder`, which builds it, closes no circle but its own,
		// so it is given.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.typeReceivingItsBuilderOnlyIfAvailableBesideReceiveLeftNilThroughValue, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuilds_whenItsBuilderIsDeclaredLast() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t3: T3", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t3: t3, t2Builder: t2Builder, t4Builder: t4Builder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachBuilderToTypeItBuilds_whenItsOtherReceiveIsConsideredFirst() async throws {
		// `t4Builder` is declared before `t2Builder`, so its receive of `t2Builder` is considered first and honored, and
		// `t2Builder`'s receive of `t3` is left `nil`, which is no candidate, since `t3` is not an instantiator.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t3: T3", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t2Builder: Instantiator<T2>"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: nil)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: t2Builder)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        self.init(t3: t3, t4Builder: t4Builder, t2Builder: t2Builder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuilds_whenThatTypeRenamesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self, onlyIfAvailable: true) let t4BuilderAlias: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: Instantiator<T4>? = t4Builder
			            #sourceLocation()
			            return T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeInsideTreeItBuilds_whenThatTypeReceivesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Instantiated let t5: T5", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
			Self.type("T5", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            let t5 = T5(t4Builder: t4Builder)
			            return T4(t5: t5, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesSendableBuilderToTypeItBuilds_whenThatTypeReceivesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: SendableInstantiator<T2>", "@Instantiated let t4Builder: SendableInstantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?", conformances: ", Sendable"),
			Self.type("T3", "@Received let t4Builder: SendableInstantiator<T4>", conformances: ", Sendable"),
			Self.type("T4", "@Received(onlyIfAvailable: true) let t4Builder: SendableInstantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: SendableInstantiator<T2>?", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_t4Builder() -> T4 {
			            let t4Builder = SendableInstantiator<T4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: nil)
			        }
			        let t4Builder = SendableInstantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        @Sendable nonisolated func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = SendableInstantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuilds_whenThatTypeRequiresItBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Received let t4Builder: Instantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEachBuilderToTypeItBuilds_whenTwoTypesEachReceiveTheirOwnOnlyIfAvailableBesideReceivesLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t6Builder: Instantiator<T6>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>", "@Received let t6Builder: Instantiator<T6>"),
			Self.type("T4", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?", "@Received(onlyIfAvailable: true) let t6Builder: Instantiator<T6>?"),
			Self.type("T6", "@Received(onlyIfAvailable: true) let t6Builder: Instantiator<T6>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t6Builder() -> T6 {
			            let t6Builder = Instantiator<T6>(__safeDI_t6Builder)
			            return T6(t6Builder: t6Builder, t2Builder: nil, t4Builder: nil)
			        }
			        let t6Builder = Instantiator<T6>(__safeDI_t6Builder)
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: nil, t6Builder: t6Builder)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder, t6Builder: t6Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t6Builder: t6Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeInsideTreeItBuilds_whenBuilderIsOnRequiredLoopBesideAReceiveLeftNilThroughAValue() async throws {
		// `t4Builder` and `t5Builder` require each other, a loop of two; `X`, inside `t4Builder`'s tree, receives
		// `t4Builder` only if available.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t5Builder: Instantiator<T5>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Instantiated let x: X", "@Received let t5Builder: Instantiator<T5>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
			Self.type("T5", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("X", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t5Builder = Instantiator<T5>(__safeDI_t5Builder)
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            let x = X(t4Builder: t4Builder)
			            return T4(x: x, t5Builder: t5Builder, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t5Builder() -> T5 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T5(t4Builder: t4Builder)
			        }
			        let t5Builder = Instantiator<T5>(__safeDI_t5Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t5Builder: t5Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuilds_whenThatTypeRenamesItOnlyIfAvailableOnRequiredLoopBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t7Builder: Instantiator<T7>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self, onlyIfAvailable: true) let mine: Instantiator<T4>?", "@Received let t7Builder: Instantiator<T7>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
			Self.type("T7", "@Received let t4Builder: Instantiator<T4>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            let t7Builder = Instantiator<T7>(__safeDI_t7Builder)
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 9)
			            let mine: Instantiator<T4>? = t4Builder
			            #sourceLocation()
			            return T4(mine: mine, t7Builder: t7Builder, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			        func __safeDI_t7Builder() -> T7 {
			            let t4Builder = Instantiator<T4>(__safeDI_t4Builder)
			            return T7(t4Builder: t4Builder)
			        }
			        let t7Builder = Instantiator<T7>(__safeDI_t7Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t7Builder: t7Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesBuilderToTypeItBuilds_whenThatTypeForwardsAValueBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
			Self.type("T4", "@Forwarded let name: String", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder(name: String) -> T4 {
			            let t4Builder = Instantiator<T4> {
			                __safeDI_t4Builder(name: $0)
			            }
			            return T4(name: name, t4Builder: t4Builder, t2Builder: nil)
			        }
			        let t4Builder = Instantiator<T4> {
			            __safeDI_t4Builder(name: $0)
			        }
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesErasedBuilderToTypeItBuilds_whenThatTypeReceivesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			"public protocol P4 {}",
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated(fulfilledByType: \"T4\") let t4Builder: ErasedInstantiator<(), any P4>", "@Instantiated let t3: T3"),
			Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
			Self.type("T3", "@Received let t4Builder: ErasedInstantiator<(), any P4>"),
			Self.type("T4", "@Received(onlyIfAvailable: true) let t4Builder: ErasedInstantiator<(), any P4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?", conformances: ", P4"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_t4Builder() -> T4 {
			            let t4Builder = ErasedInstantiator<(), any P4>(__safeDI_t4Builder)
			            return T4(t4Builder: t4Builder, t2Builder: nil)
			        }
			        let t4Builder = ErasedInstantiator<(), any P4>(__safeDI_t4Builder)
			        let t3 = T3(t4Builder: t4Builder)
			        func __safeDI_t2Builder() -> T2 {
			            T2(t3: t3)
			        }
			        let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
			        self.init(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsSendableCaptureError_whenTypeInsideSendableBuilderReceivesBuilderThatIsNotSendableOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async {
		// `Inner`, built in `T4`'s tree by a `Sendable` builder, receives `t4Builder` only if available: given, as it is
		// without `T4`'s receive of `t2Builder`, so the same error as there.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Inner.swift"]):7:5: error: @Received property `t4Builder: Instantiator<T4>?` cannot be received inside a `@Sendable` function in chain: Root -> T4 -> Inner. SafeDI builds `innerBuilder: SendableInstantiator<Inner>` on `T4` in a `@Sendable` function, which cannot capture `t4Builder: Instantiator<T4>` on `Root`, because `Instantiator<T4>` is not `Sendable`. Declare `t4Builder` on `Root`, and this property, as `SendableInstantiator<T4>` to fix. `SendableInstantiator<T4>` builds `T4` in a `@Sendable` function, so what the tree of `T4` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):10:5: note: `t4Builder: Instantiator<T4>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
				Self.type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
				Self.type("T3", "@Received let t4Builder: Instantiator<T4>"),
				Self.type("T4", "@Instantiated let innerBuilder: SendableInstantiator<Inner>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
				Self.type("Inner", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsSendableCaptureError_whenTypeInsideSendableBuilderReceivesBuilderThatIsNotSendableOnlyIfAvailableInsideTreeItBuilds() async {
		// `Inner`, built in `T4`'s tree by a `Sendable` builder, receives `t4Builder` only if available: given, so the
		// `Sendable` capture error, as the same receive is outside the instantiator's own tree.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Inner.swift"]):7:5: error: @Received property `t4Builder: Instantiator<T4>?` cannot be received inside a `@Sendable` function in chain: Root -> T4 -> Inner. SafeDI builds `innerBuilder: SendableInstantiator<Inner>` on `T4` in a `@Sendable` function, which cannot capture `t4Builder: Instantiator<T4>` on `Root`, because `Instantiator<T4>` is not `Sendable`. Declare `t4Builder` on `Root`, and this property, as `SendableInstantiator<T4>` to fix. `SendableInstantiator<T4>` builds `T4` in a `@Sendable` function, so what the tree of `T4` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):7:5: note: `t4Builder: Instantiator<T4>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let t4Builder: Instantiator<T4>"),
				Self.type("T4", "@Instantiated let innerBuilder: SendableInstantiator<Inner>"),
				Self.type("Inner", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – Builders whose functions take cycle parameters

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsOwnBuilderWithOwnParameters_whenLoopMemberFunctionTakesCycleParameter() async throws {
		// `Step` declares its own `session` and closes a cycle on `screenBuilder`, so `__safeDI_screenBuilder` takes `session`. `Detail` and `History` receive `screenBuilder` inside its tree.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Settings"),
			Self.type("Screen", "@Received let session: Session", "@Received let settings: Settings", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail", "@Instantiated let history: LazilyInstantiated<History>"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("History", "@Received let session: Session", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", "@Instantiated let settings: LazilyInstantiated<Settings>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_settings() -> Settings {
			            Settings()
			        }
			        let settings = LazilyInstantiated<Settings>(__safeDI_settings)
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(session: session)
			            }
			            func __safeDI_stepBuilder() -> Step {
			                let session = Session()
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return Step(session: session, screenBuilder: screenBuilder)
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = Detail(screenBuilder: screenBuilder)
			            func __safeDI_history() -> History {
			                History(session: session, screenBuilder: screenBuilder)
			            }
			            let history = LazilyInstantiated<History>(__safeDI_history)
			            return Screen(session: session, settings: settings.instance, stepBuilder: stepBuilder, detail: detail, history: history)
			        }
			        func __safeDI_screenBuilder_received() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			        self.init(session: session, settings: settings, screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesReceivedFunctionApart_whenSiblingsBuilderFunctionHasItsName() async throws {
		// `Root` declares `screenBuilder_received`, whose builder function is `__safeDI_screenBuilder_received`, so the function every wrapper of `screenBuilder` hands takes another name.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Other"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let screenBuilder_received: Instantiator<Other>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(session: session)
			            }
			            func __safeDI_stepBuilder() -> Step {
			                let session = Session()
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return Step(session: session, screenBuilder: screenBuilder)
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = Detail(screenBuilder: screenBuilder)
			            return Screen(session: session, stepBuilder: stepBuilder, detail: detail)
			        }
			        func __safeDI_screenBuilder_received_() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			        func __safeDI_screenBuilder_received() -> Other {
			            Other()
			        }
			        let screenBuilder_received = Instantiator<Other>(__safeDI_screenBuilder_received)
			        self.init(session: session, screenBuilder: screenBuilder, screenBuilder_received: screenBuilder_received)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesReceivedFunctionApart_whenCycleClosingScopeBeneathRefersToEnclosingFunctionOfItsName() async throws {
		// `Shell` declares `screenBuilder_received`, whose builder function `__safeDI_screenBuilder_received` encloses `Flow`'s body, and `Tail`, beneath that body, closes a cycle on it by name, so the function every wrapper of `screenBuilder` hands takes another name.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Tail", "@Instantiated let screenBuilder_received: Instantiator<Flow>"),
			Self.type("Flow", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let tail: Tail"),
			Self.type("Shell", attributes: "(isRoot: true)", "@Instantiated let screenBuilder_received: Instantiator<Flow>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Shell+SafeDI.swift": generatedFileHeader + """
			extension Shell {
			    public convenience init() {
			        func __safeDI_screenBuilder_received() -> Flow {
			            let session = Session()
			            func __safeDI_screenBuilder(session: Session) -> Screen {
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                func __safeDI_stepBuilder() -> Step {
			                    let session = Session()
			                    let screenBuilder = Instantiator<Screen> {
			                        __safeDI_screenBuilder(session: session)
			                    }
			                    return Step(session: session, screenBuilder: screenBuilder)
			                }
			                let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			                let detail = Detail(screenBuilder: screenBuilder)
			                return Screen(session: session, stepBuilder: stepBuilder, detail: detail)
			            }
			            func __safeDI_screenBuilder_received_() -> Screen {
			                __safeDI_screenBuilder(session: session)
			            }
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			            func __safeDI_tail() -> Tail {
			                let screenBuilder_received = Instantiator<Flow>(__safeDI_screenBuilder_received)
			                return Tail(screenBuilder_received: screenBuilder_received)
			            }
			            let tail: Tail = __safeDI_tail()
			            return Flow(session: session, screenBuilder: screenBuilder, tail: tail)
			        }
			        let screenBuilder_received = Instantiator<Flow>(__safeDI_screenBuilder_received)
			        self.init(screenBuilder_received: screenBuilder_received)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_namesReceivedFunctionApart_whenAnotherMembersBodyDeclaresBuilderFunctionOfItsName() async throws {
		// `Peer`, on the loop with `screenBuilder`, declares `screenBuilder_received`, whose builder function in `__safeDI_peerBuilder`'s body would hide the function `Peer`'s rebinding of `screenBuilder` hands, so that function takes another name.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Other"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let peerBuilder: Instantiator<Peer>"),
			Self.type("Peer", "@Received let screenBuilder: Instantiator<Screen>", "@Instantiated let screenBuilder_received: Instantiator<Other>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let peerBuilder: Instantiator<Peer>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			            func __safeDI_stepBuilder() -> Step {
			                let session = Session()
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return Step(session: session, screenBuilder: screenBuilder)
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = Detail(peerBuilder: peerBuilder)
			            return Screen(session: session, stepBuilder: stepBuilder, detail: detail)
			        }
			        func __safeDI_screenBuilder_received_() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			        func __safeDI_peerBuilder() -> Peer {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			            func __safeDI_screenBuilder_received() -> Other {
			                Other()
			            }
			            let screenBuilder_received = Instantiator<Other>(__safeDI_screenBuilder_received)
			            return Peer(screenBuilder: screenBuilder, screenBuilder_received: screenBuilder_received)
			        }
			        let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			        self.init(session: session, screenBuilder: screenBuilder, peerBuilder: peerBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsReceivedFunctionAsRawIdentifier_whenLoopMembersLabelIsRawIdentifier() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Screen", "@Received let `c d`: Session", "@Instantiated let `a b`: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let `some thing`: Instantiator<Screen>", "@Received let peer: Instantiator<Peer>"),
			Self.type("Peer", "@Received let `some thing`: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let `c d`: Session", "@Instantiated let `some thing`: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let `c d`: Session", "@Instantiated let `some thing`: Instantiator<Screen>", "@Instantiated let peer: Instantiator<Peer>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let `c d` = Session()
			        func `__safeDI_some thing`(`c d`: Session) -> Screen {
			            let `some thing` = Instantiator<Screen> {
			                `__safeDI_some thing`(`c d`: `c d`)
			            }
			            let peer = Instantiator<Peer>(__safeDI_peer)
			            func `__safeDI_a b`() -> Step {
			                let `c d` = Session()
			                let `some thing` = Instantiator<Screen> {
			                    `__safeDI_some thing`(`c d`: `c d`)
			                }
			                return Step(`c d`: `c d`, `some thing`: `some thing`)
			            }
			            let `a b` = Instantiator<Step>(`__safeDI_a b`)
			            let detail = Detail(`some thing`: `some thing`, peer: peer)
			            return Screen(`c d`: `c d`, `a b`: `a b`, detail: detail)
			        }
			        func `__safeDI_some thing_received`() -> Screen {
			            `__safeDI_some thing`(`c d`: `c d`)
			        }
			        let `some thing` = Instantiator<Screen>(`__safeDI_some thing_received`)
			        func __safeDI_peer() -> Peer {
			            let `some thing` = Instantiator<Screen>(`__safeDI_some thing_received`)
			            return Peer(`some thing`: `some thing`)
			        }
			        let peer = Instantiator<Peer>(__safeDI_peer)
			        self.init(`c d`: `c d`, `some thing`: `some thing`, peer: peer)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsReceivedFunctionPassingDeclaringScopesValue_whenReceiverForwardsValueOfCycleParametersLabel() async throws {
		// `A` forwards a `session` of its own, which must not reach the `B` it builds: `__safeDI_bBuilder` takes `session` as a cycle parameter, and `__safeDI_bBuilder_received` passes the root's.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(session: Session, bBuilder: Instantiator<B>) {
			        self.session = session
			        self.bBuilder = bBuilder
			    }

			    @Forwarded let session: Session
			    @Received let bBuilder: Instantiator<B>
			}
			""",
			Self.type("B", "@Received let session: Session", "@Received let aBuilder: Instantiator<A>", "@Instantiated let stepBuilder: Instantiator<Step>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_aBuilder(session: Session) -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			            return A(session: session, bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(session: $0)
			        }
			        func __safeDI_bBuilder(session: Session) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(session: $0)
			            }
			            func __safeDI_stepBuilder() -> Step {
			                let session = Session()
			                let bBuilder = Instantiator<B> {
			                    __safeDI_bBuilder(session: session)
			                }
			                return Step(session: session, bBuilder: bBuilder)
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            return B(session: session, aBuilder: aBuilder, stepBuilder: stepBuilder)
			        }
			        func __safeDI_bBuilder_received() -> B {
			            __safeDI_bBuilder(session: session)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			        self.init(session: session, aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_wrapsLoopMemberCycleArgumentInsideReceivedFunction_whenCycleParameterIsMemberOfSameLoop() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Other", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Detail", "@Received let otherBuilder: Instantiator<Other>"),
			Self.type("Screen", "@Instantiated let detail: Detail", "@Instantiated let stepBuilder: Instantiator<Step>"),
			Self.type("Step", "@Instantiated let otherBuilder: Instantiator<Other>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let otherBuilder: Instantiator<Other>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_otherBuilder() -> Other {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			            return Other(screenBuilder: screenBuilder)
			        }
			        let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			        func __safeDI_screenBuilder(otherBuilder: Instantiator<Other>) -> Screen {
			            let detail = Detail(otherBuilder: otherBuilder)
			            func __safeDI_stepBuilder() -> Step {
			                func __safeDI_otherBuilder() -> Other {
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			                    return Other(screenBuilder: screenBuilder)
			                }
			                let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                func __safeDI_screenBuilder_received() -> Screen {
			                    let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                    return __safeDI_screenBuilder(otherBuilder: otherBuilder)
			                }
			                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			                return Step(otherBuilder: otherBuilder, screenBuilder: screenBuilder)
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            return Screen(detail: detail, stepBuilder: stepBuilder)
			        }
			        func __safeDI_screenBuilder_received() -> Screen {
			            let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			            return __safeDI_screenBuilder(otherBuilder: otherBuilder)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			        self.init(otherBuilder: otherBuilder, screenBuilder: screenBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresReceivedFunctionForEachMember_whenEachMemberFunctionTakesTheOtherAsCycleParameter() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("DetailA", "@Received let bBuilder: Instantiator<B>"),
			Self.type("DetailB", "@Received let aBuilder: Instantiator<A>"),
			Self.type("A", "@Instantiated let detail: DetailA", "@Instantiated let stepBuilder: Instantiator<StepA>"),
			Self.type("B", "@Instantiated let detail: DetailB", "@Instantiated let stepBuilder: Instantiator<StepB>"),
			Self.type("StepA", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("StepB", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder(bBuilder: Instantiator<B>) -> A {
			            let detail = DetailA(bBuilder: bBuilder)
			            func __safeDI_stepBuilder() -> StepA {
			                func __safeDI_bBuilder(aBuilder: Instantiator<A>) -> B {
			                    let detail = DetailB(aBuilder: aBuilder)
			                    func __safeDI_stepBuilder() -> StepB {
			                        func __safeDI_aBuilder_received() -> A {
			                            let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                            return __safeDI_aBuilder(bBuilder: bBuilder)
			                        }
			                        let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                        func __safeDI_bBuilder_received() -> B {
			                            let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                            return __safeDI_bBuilder(aBuilder: aBuilder)
			                        }
			                        let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                        return StepB(aBuilder: aBuilder, bBuilder: bBuilder)
			                    }
			                    let stepBuilder = Instantiator<StepB>(__safeDI_stepBuilder)
			                    return B(detail: detail, stepBuilder: stepBuilder)
			                }
			                func __safeDI_bBuilder_received() -> B {
			                    let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                    return __safeDI_bBuilder(aBuilder: aBuilder)
			                }
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                func __safeDI_aBuilder_received() -> A {
			                    let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                    return __safeDI_aBuilder(bBuilder: bBuilder)
			                }
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                return StepA(bBuilder: bBuilder, aBuilder: aBuilder)
			            }
			            let stepBuilder = Instantiator<StepA>(__safeDI_stepBuilder)
			            return A(detail: detail, stepBuilder: stepBuilder)
			        }
			        func __safeDI_aBuilder_received() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			            return __safeDI_aBuilder(bBuilder: bBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			        func __safeDI_bBuilder(aBuilder: Instantiator<A>) -> B {
			            let detail = DetailB(aBuilder: aBuilder)
			            func __safeDI_stepBuilder() -> StepB {
			                func __safeDI_aBuilder(bBuilder: Instantiator<B>) -> A {
			                    let detail = DetailA(bBuilder: bBuilder)
			                    func __safeDI_stepBuilder() -> StepA {
			                        func __safeDI_bBuilder_received() -> B {
			                            let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                            return __safeDI_bBuilder(aBuilder: aBuilder)
			                        }
			                        let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                        func __safeDI_aBuilder_received() -> A {
			                            let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                            return __safeDI_aBuilder(bBuilder: bBuilder)
			                        }
			                        let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                        return StepA(bBuilder: bBuilder, aBuilder: aBuilder)
			                    }
			                    let stepBuilder = Instantiator<StepA>(__safeDI_stepBuilder)
			                    return A(detail: detail, stepBuilder: stepBuilder)
			                }
			                func __safeDI_aBuilder_received() -> A {
			                    let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                    return __safeDI_aBuilder(bBuilder: bBuilder)
			                }
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                func __safeDI_bBuilder_received() -> B {
			                    let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                    return __safeDI_bBuilder(aBuilder: aBuilder)
			                }
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			                return StepB(aBuilder: aBuilder, bBuilder: bBuilder)
			            }
			            let stepBuilder = Instantiator<StepB>(__safeDI_stepBuilder)
			            return B(detail: detail, stepBuilder: stepBuilder)
			        }
			        func __safeDI_bBuilder_received() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			            return __safeDI_bBuilder(aBuilder: aBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder_received)
			        self.init(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresSendableReceivedFunction_whenSendableLoopMemberFunctionTakesCycleParameter() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			"""
			public protocol Screen: Sendable {
			    var session: Session { get }
			}
			""",
			Self.type("Session", conformances: ", Sendable"),
			"""
			@Instantiable
			public final class A: Screen, Instantiable, Sendable {
			    public init(session: Session, bBuilder: SendableErasedInstantiator<(), any Screen>) {
			        self.session = session
			        self.bBuilder = bBuilder
			    }

			    @Forwarded public let session: Session
			    @Received let bBuilder: SendableErasedInstantiator<(), any Screen>
			}
			""",
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated(fulfilledByType: \"B\") let bBuilder: SendableErasedInstantiator<(), any Screen>", conformances: ", Sendable"),
			"""
			@Instantiable
			public final class B: Screen, Instantiable, Sendable {
			    public init(session: Session, aBuilder: SendableInstantiator<A>, stepBuilder: SendableInstantiator<Step>) {
			        self.session = session
			        self.aBuilder = aBuilder
			        self.stepBuilder = stepBuilder
			    }

			    @Received public let session: Session
			    @Received let aBuilder: SendableInstantiator<A>
			    @Instantiated let stepBuilder: SendableInstantiator<Step>
			}
			""",
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", "@Instantiated let aBuilder: SendableInstantiator<A>", "@Instantiated(fulfilledByType: \"B\") let bBuilder: SendableErasedInstantiator<(), any Screen>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        @Sendable nonisolated func __safeDI_aBuilder(session: Session) -> A {
			            let bBuilder = SendableErasedInstantiator<(), any Screen>(__safeDI_bBuilder_received)
			            return A(session: session, bBuilder: bBuilder)
			        }
			        let aBuilder = SendableInstantiator<A> {
			            __safeDI_aBuilder(session: $0)
			        }
			        @Sendable nonisolated func __safeDI_bBuilder(session: Session) -> B {
			            let aBuilder = SendableInstantiator<A> {
			                __safeDI_aBuilder(session: $0)
			            }
			            @Sendable nonisolated func __safeDI_stepBuilder() -> Step {
			                let session = Session()
			                let bBuilder = SendableErasedInstantiator<(), any Screen> {
			                    __safeDI_bBuilder(session: session)
			                }
			                return Step(session: session, bBuilder: bBuilder)
			            }
			            let stepBuilder = SendableInstantiator<Step>(__safeDI_stepBuilder)
			            return B(session: session, aBuilder: aBuilder, stepBuilder: stepBuilder)
			        }
			        @Sendable nonisolated func __safeDI_bBuilder_received() -> B {
			            __safeDI_bBuilder(session: session)
			        }
			        let bBuilder = SendableErasedInstantiator<(), any Screen>(__safeDI_bBuilder_received)
			        self.init(session: session, aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Tests – Receives through a cycle-closing scope

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsNothingInsideClosedOnBuildersTree_whenOnlyCycleClosingCallReceivesBuilderThroughRequiredRename() async throws {
		// The `B` inside `A` calls the enclosing `__safeDI_bBuilder`, which binds its own `aBuilder`: nothing in `A`'s function reads one.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias)
			        }
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsNothingInsideClosedOnBuildersTree_whenOnlyCycleClosingCallReceivesBuilderThroughOnlyIfAvailableRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A>? = aBuilder
			            #sourceLocation()
			            return B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias)
			        }
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenItsTypeReceivesItBesideCycleClosingCallThatReceivesItThroughRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder, aBuilder: aBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A>? = aBuilder
			            #sourceLocation()
			            return B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_rebindsBuilderInsideItsOwnFunction_whenAnotherTypeInItsTreeReceivesItBesideCycleClosingCall() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let c: C"),
			Self.type("C", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let c = C(aBuilder: aBuilder)
			                return A(bBuilder: bBuilder, c: c)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_ordersRebindingsByFirstReceiveInsideTheBody_whenCycleClosingCallsTypeRenamesItsOwnBuilderFirst() async throws {
		// The `B` inside `A` comes first in `A`'s tree, but its rename reads the `aBuilder` its own function binds, so `C`'s receives, `xBuilder` first, order the rebindings.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let xBuilder: Instantiator<X>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let c: C"),
			Self.type("C", "@Received let xBuilder: Instantiator<X>", "@Received let aBuilder: Instantiator<A>"),
			Self.type("X", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                let c = C(xBuilder: xBuilder, aBuilder: aBuilder)
			                return A(bBuilder: bBuilder, c: c)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            func __safeDI_xBuilder() -> X {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                return X(aBuilder: aBuilder)
			            }
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 11)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return B(aBuilder: aBuilder, xBuilder: xBuilder, aBuilderAlias: aBuilderAlias)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsValueBeforeBuilderThatReceivesIt_whenValuesTreeCallsEnclosingFunctionOfTypeThatRenamesTheBuilder() async throws {
		// The `B` inside `C` calls the enclosing `__safeDI_bBuilder`, whose rename reads the `aBuilder` that function binds, so
		// `c` waits on nothing and is built before `aBuilder`, whose `A` receives it.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let c: C", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("C", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let c: C"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_bBuilder() -> B {
			            let c: C = __safeDI_c()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(c: c)
			            }
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 11)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return B(c: c, aBuilder: aBuilder, aBuilderAlias: aBuilderAlias)
			        }
			        func __safeDI_c() -> C {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return C(bBuilder: bBuilder)
			        }
			        func __safeDI_aBuilder(c: C) -> A {
			            A(c: c)
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        self.init(bBuilder: bBuilder)
			    }
			}
			""",
		])
	}

	// MARK: Tests – Still rejected

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsDependencyCycleError_whenScreenReceivesRouterBuiltAsValueThatRequiresScreensBuilder() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Router.swift"]):7:5: error: Dependency cycle: @Instantiated `screenBuilder: Instantiator<Screen>` -> @Received `router: Router` -> @Received `screenBuilder: Instantiator<Screen>`. `screenBuilder: Instantiator<Screen>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let router: Router", "@Instantiated let screenBuilder: Instantiator<Screen>"),
				Self.type("Router", "@Received let screenBuilder: Instantiator<Screen>"),
				Self.type("Screen", "@Received let router: Router"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsDependencyCycleError_whenScreenReceivesLazilyInstantiatedRouterThatRequiresScreensBuilder() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Router.swift"]):7:5: error: Dependency cycle: @Instantiated `screenBuilder: Instantiator<Screen>` -> @Received `router: Router` -> @Received `screenBuilder: Instantiator<Screen>`. `screenBuilder: Instantiator<Screen>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `router: LazilyInstantiated<Router>` is validated as `router: Router`.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let router: LazilyInstantiated<Router>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
				Self.type("Router", "@Received let screenBuilder: Instantiator<Screen>"),
				Self.type("Screen", "@Received let router: LazilyInstantiated<Router>"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsDependencyCycleError_whenConstantIsOnRingOfBuilders() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):7:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<A>` -> @Received `v: V` -> @Received `bBuilder: Instantiator<B>` -> @Received `aBuilder: Instantiator<A>`. `aBuilder: Instantiator<A>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let v: V"),
				Self.type("A", "@Received let v: V"),
				Self.type("V", "@Received let bBuilder: Instantiator<B>"),
				Self.type("B", "@Received let aBuilder: Instantiator<A>"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsDependencyCycleError_whenTypeReceivesErasingRenameOfBuilderThatBuildsIt() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Screen.swift"]):7:5: error: Dependency cycle: @Instantiated `screenBuilder: Instantiator<Screen>` -> @Received `anyBuilder: AnyBuilder` -> @Received `screenBuilder: Instantiator<Screen>`. `screenBuilder: Instantiator<Screen>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Received(fulfilledByDependencyNamed: \"screenBuilder\", ofType: Instantiator<Screen>.self, erasedToConcreteExistential: true) let anyBuilder: AnyBuilder"),
				Self.type("Screen", "@Received let anyBuilder: AnyBuilder"),
				"""
				public struct AnyBuilder {
				    public init(_ builder: Instantiator<Screen>) {}
				}
				""",
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsChainThroughValue_whenCircleOfBuildersSharesItsMembersWithCircleThroughValue() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["V.swift"]):7:5: error: Dependency cycle: @Instantiated `aBuilder: Instantiator<A>` -> @Received `v: V` -> @Received `aBuilder: Instantiator<A>`. `aBuilder: Instantiator<A>` is received while it is still being instantiated. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let v: V"),
				Self.type("A", "@Received let bBuilder: Instantiator<B>", "@Received let v: V"),
				Self.type("B", "@Received let aBuilder: Instantiator<A>"),
				Self.type("V", "@Received let aBuilder: Instantiator<A>"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsDependencyCycleError_whenLazilyInstantiatedValueIsReceivedInsideTheTreeItBuilds() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):7:5: error: Dependency cycle: `A` -> `Instantiator<B>` -> `A`. `B` receives `a: LazilyInstantiated<A>`, which is still being built when `B` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `a: LazilyInstantiated<A>` is validated as `a: A`.
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: LazilyInstantiated<A>"),
				Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
				Self.type("B", "@Received let a: LazilyInstantiated<A>"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – Determinism

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_emitsLoopInDeclarationOrderAfterWhatItReceives_whenTwentyFourBuildersInOneLoopAreDeclaredOutOfOrder() async throws {
		// Each of twenty-four builders receives the builders two and one after it, in that order, so each function rebinds
		// two members in the order its body receives them, not in label order. The root declares a value that receives a
		// member first, then the builders in a permuted order, then a value a member receives: the loop is emitted as one
		// unit, its members in declaration order, after the value it receives and before the value that receives it.
		let count = 24
		let declarationOrder = (0..<count).map { ($0 * 7) % count }
		let rootDeclarations = ["@Instantiated let consumer: Consumer"]
			+ declarationOrder.map { "@Instantiated let b\($0)Builder: Instantiator<B\($0)>" }
			+ ["@Instantiated let service: Service"]
		var fixture = [
			Self.type("Root", attributes: "(isRoot: true)", rootDeclarations),
			Self.type("Consumer", ["@Received let b0Builder: Instantiator<B0>"]),
			Self.type("Service", []),
		]
		for index in 0..<count {
			var declarations = [
				"@Received let b\((index + 2) % count)Builder: Instantiator<B\((index + 2) % count)>",
				"@Received let b\((index + 1) % count)Builder: Instantiator<B\((index + 1) % count)>",
			]
			if index == 5 {
				declarations.append("@Received let service: Service")
			}
			fixture.append(Self.type("B\(index)", declarations))
		}
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		var lines = [
			"extension Root {",
			"    public convenience init() {",
			"        let service = Service()",
		]
		for index in declarationOrder {
			let second = (index + 2) % count
			let first = (index + 1) % count
			lines += [
				"        func __safeDI_b\(index)Builder() -> B\(index) {",
				"            let b\(second)Builder = Instantiator<B\(second)>(__safeDI_b\(second)Builder)",
				"            let b\(first)Builder = Instantiator<B\(first)>(__safeDI_b\(first)Builder)",
				"            return B\(index)(b\(second)Builder: b\(second)Builder, b\(first)Builder: b\(first)Builder\(index == 5 ? ", service: service" : ""))",
				"        }",
				"        let b\(index)Builder = Instantiator<B\(index)>(__safeDI_b\(index)Builder)",
			]
		}
		lines += [
			"        let consumer = Consumer(b0Builder: b0Builder)",
			"        self.init(consumer: consumer, \(declarationOrder.map { "b\($0)Builder: b\($0)Builder" }.joined(separator: ", ")), service: service)",
			"    }",
			"}",
		]
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + lines.joined(separator: "\n")])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesEveryBuilderReceivedOnlyIfAvailable_whenTwentyFourBuildersInOneLoopAreDeclaredOutOfOrder() async throws {
		// Each of twenty-four builders receives the builders five and one after it only if available, in that order. The
		// sibling order gives some of these receives and leaves the rest `nil`; the second pass gives every one, since the
		// circle each closes holds only builders, so each function rebinds both, in the order its body receives them.
		let count = 24
		let declarationOrder = (0..<count).map { ($0 * 7) % count }
		var fixture = [
			Self.type("Root", attributes: "(isRoot: true)", declarationOrder.map { "@Instantiated let b\($0)Builder: Instantiator<B\($0)>" }),
		]
		for index in 0..<count {
			fixture.append(Self.type("B\(index)", [
				"@Received(onlyIfAvailable: true) let b\((index + 5) % count)Builder: Instantiator<B\((index + 5) % count)>?",
				"@Received(onlyIfAvailable: true) let b\((index + 1) % count)Builder: Instantiator<B\((index + 1) % count)>?",
			]))
		}
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)

		var lines = [
			"extension Root {",
			"    public convenience init() {",
		]
		for index in declarationOrder {
			let first = (index + 5) % count
			let second = (index + 1) % count
			lines += [
				"        func __safeDI_b\(index)Builder() -> B\(index) {",
				"            let b\(first)Builder = Instantiator<B\(first)>(__safeDI_b\(first)Builder)",
				"            let b\(second)Builder = Instantiator<B\(second)>(__safeDI_b\(second)Builder)",
				"            return B\(index)(b\(first)Builder: b\(first)Builder, b\(second)Builder: b\(second)Builder)",
				"        }",
				"        let b\(index)Builder = Instantiator<B\(index)>(__safeDI_b\(index)Builder)",
			]
		}
		lines += [
			"        self.init(\(declarationOrder.map { "b\($0)Builder: b\($0)Builder" }.joined(separator: ", ")))",
			"    }",
			"}",
		]
		#expect(output.generatedFiles == ["Root+SafeDI.swift": generatedFileHeader + lines.joined(separator: "\n")])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `aBuilder` and `bBuilder` receive each other, and `A` receives `cBuilder` only if available; `cBuilder` waits on `v`,
	/// which waits on `aBuilder`.
	private static let twoBuilderLoopBesideReceiveWaitingOnItThroughValue = [
		type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let v: V"),
		type("A", "@Received let bBuilder: Instantiator<B>", "@Received(onlyIfAvailable: true) let cBuilder: Instantiator<C>?"),
		type("B", "@Received let aBuilder: Instantiator<A>"),
		type("C", "@Received let v: V"),
		type("V", "@Received let aBuilder: Instantiator<A>"),
	]

	/// `T4` receives `t4Builder`, which builds it, only if available, and `t2Builder` only if available, which waits on
	/// `t3`, which requires `t4Builder`: that receive is left `nil`, and `t4Builder` still receives itself.
	private static let typeReceivingItsBuilderOnlyIfAvailableBesideReceiveLeftNilThroughValue = [
		type("Root", attributes: "(isRoot: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
		type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
		type("T3", "@Received let t4Builder: Instantiator<T4>"),
		type("T4", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
	]

	// MARK: Tests – Growth

	@Test(arguments: ["Instantiator", "SendableInstantiator"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesCodeThatGrowsLinearlyWithMembers_whenRootBuildersReceiveOneAnotherInARing(wrapper: String) async throws {
		// A ring of n members, each receiving the next: each function makes one member again, so the code grows as n.
		var lengths = [Int: Int]()
		for memberCount in [8, 16, 32] {
			let output = try await executeSafeDIToolTest(
				swiftFileContent: Self.loopOfBuilders(memberCount: memberCount, wrapper: wrapper) { member in [(member + 1) % memberCount] },
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: memberCount > 8,
			)
			lengths[memberCount] = try #require(output.generatedFiles?["Root+SafeDI.swift"]).utf8.count
		}
		let eight = try #require(lengths[8]), sixteen = try #require(lengths[16]), thirtyTwo = try #require(lengths[32])
		#expect(Double(sixteen) / Double(eight) < 2.2 && Double(thirtyTwo) / Double(sixteen) < 2.2, "\(lengths)")
	}

	@Test(arguments: ["Instantiator", "SendableInstantiator"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_writesCodeThatGrowsLinearlyWithReceives_whenEveryRootBuilderReceivesEveryOther(wrapper: String) async throws {
		// A loop of n members, each receiving every other: the declarations hold n(n-1) receives, and each function makes
		// the n-1 others again, so the code grows as the receives do, never faster.
		var lengthsPerReceive = [Int: Double]()
		for memberCount in [8, 16, 32] {
			let output = try await executeSafeDIToolTest(
				swiftFileContent: Self.loopOfBuilders(memberCount: memberCount, wrapper: wrapper) { member in (0..<memberCount).filter { $0 != member } },
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: memberCount > 8,
			)
			let length = try #require(output.generatedFiles?["Root+SafeDI.swift"]).utf8.count
			lengthsPerReceive[memberCount] = Double(length) / Double(memberCount * (memberCount - 1))
		}
		let eight = try #require(lengthsPerReceive[8]), thirtyTwo = try #require(lengthsPerReceive[32])
		#expect(thirtyTwo / eight < 1.1, "\(lengthsPerReceive)")
	}

	/// A root that instantiates `memberCount` builders of `wrapper`, each member receiving the builders `receives` names.
	private static func loopOfBuilders(memberCount: Int, wrapper: String, receives: (Int) -> [Int]) -> [String] {
		let conformances = wrapper == "SendableInstantiator" ? ", Sendable" : ""
		var types = [type("Root", attributes: "(isRoot: true)", (0..<memberCount).map { "@Instantiated let m\($0)Builder: \(wrapper)<M\($0)>" })]
		for member in 0..<memberCount {
			types.append(type("M\(member)", receives(member).map { "@Received let m\($0)Builder: \(wrapper)<M\($0)>" }, conformances: conformances))
		}
		return types
	}

	private static func type(_ name: String, attributes: String = "", _ declarations: String..., conformances: String = "") -> String {
		type(name, attributes: attributes, declarations, conformances: conformances)
	}

	private static func type(_ name: String, attributes: String = "", _ declarations: [String], conformances: String = "") -> String {
		let type = seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: conformances)
		guard !attributes.isEmpty else { return type }
		return "@Instantiable\(attributes)" + type.dropFirst("@Instantiable".count)
	}
}
