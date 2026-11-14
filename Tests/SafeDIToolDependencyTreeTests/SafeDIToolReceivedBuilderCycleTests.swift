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
			        @Sendable func __safeDI_aBuilder() -> A {
			            let bBuilder = SendableErasedInstantiator<(), any Screen>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			        @Sendable func __safeDI_bBuilder() -> B {
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
			        @Sendable func __safeDI_aBuilder(session: Session) -> A {
			            let bBuilder = SendableErasedInstantiator<(), any Screen>(__safeDI_bBuilder_received)
			            return A(session: session, bBuilder: bBuilder)
			        }
			        let aBuilder = SendableInstantiator<A> {
			            __safeDI_aBuilder(session: $0)
			        }
			        @Sendable func __safeDI_bBuilder(session: Session) -> B {
			            let aBuilder = SendableInstantiator<A> {
			                __safeDI_aBuilder(session: $0)
			            }
			            @Sendable func __safeDI_stepBuilder() -> Step {
			                let session = Session()
			                let bBuilder = SendableErasedInstantiator<(), any Screen> {
			                    __safeDI_bBuilder(session: session)
			                }
			                return Step(session: session, bBuilder: bBuilder)
			            }
			            let stepBuilder = SendableInstantiator<Step>(__safeDI_stepBuilder)
			            return B(session: session, aBuilder: aBuilder, stepBuilder: stepBuilder)
			        }
			        @Sendable func __safeDI_bBuilder_received() -> B {
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
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder)
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
			            func __safeDI_aBuilder() -> A {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder)
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
			            func __safeDI_c() -> C {
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return C(bBuilder: bBuilder)
			            }
			            let c: C = __safeDI_c()
			            func __safeDI_aBuilder() -> A {
			                A(c: c)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 11)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return B(c: c, aBuilder: aBuilder, aBuilderAlias: aBuilderAlias)
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

	private static func type(_ name: String, attributes: String = "", _ declarations: String..., conformances: String = "") -> String {
		type(name, attributes: attributes, declarations, conformances: conformances)
	}

	private static func type(_ name: String, attributes: String = "", _ declarations: [String], conformances: String = "") -> String {
		let type = seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: conformances)
		guard !attributes.isEmpty else { return type }
		return "@Instantiable\(attributes)" + type.dropFirst("@Instantiable".count)
	}
}
