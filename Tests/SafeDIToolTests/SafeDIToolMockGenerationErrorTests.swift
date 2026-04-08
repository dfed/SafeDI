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
@testable import SafeDITool

struct SafeDIToolMockGenerationErrorTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Error Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenPartiallyLazyCycleThroughInstantiatorBoundary() async {
		await assertThrowsError(
			"""
			Dependency cycle detected. Cycles with a mix of constant and lazy (Instantiator) dependencies cannot be resolved. Make all dependencies in the cycle lazy by using Instantiator:
			\tPlayer -> Instantiator<CachedItem> -> Player
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Player: Instantiable {
					    public init(cachedItemBuilder: Instantiator<CachedItem>) {
					        self.cachedItemBuilder = cachedItemBuilder
					    }
					    @Instantiated let cachedItemBuilder: Instantiator<CachedItem>
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct CachedItem: Instantiable {
					    public init(player: Player, name: String) {
					        self.player = player
					        self.name = name
					    }
					    @Instantiated let player: Player
					    @Forwarded let name: String
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenConstantDependencyCycleExists() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tA -> B -> C -> A
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(a: A) { self.a = a }
					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct A: Instantiable {
					    public init(b: B) { self.b = b }
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct C: Instantiable {
					    public init(a: A) { self.a = a }
					    @Instantiated let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenUnfulfillableInstantiatedPropertyExists() async {
		await assertThrowsError(
			"""
			No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `Unknown`
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(unknown: Unknown) { self.unknown = unknown }
					    @Instantiated let unknown: Unknown
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenReceivedPropertyIsUnfulfillable() async {
		await assertThrowsError(
			"""
			@Received property `service: Service` is not @Instantiated or @Forwarded in chain:
			\tRoot -> Child
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(child: Child, other: Other) {
					        self.child = child
					        self.other = other
					    }
					    @Instantiated let child: Child
					    @Instantiated let other: Other
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(service: Service) { self.service = service }
					    @Received let service: Service
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Other: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenInstantiatedPropertyRefersToSelf() async {
		await assertThrowsError(
			"""
			Dependency cycle detected:
			\tSelfReferencing -> SelfReferencing
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(selfReferencing: SelfReferencing) { self.selfReferencing = selfReferencing }
					    @Instantiated let selfReferencing: SelfReferencing
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct SelfReferencing: Instantiable {
					    public init(selfReferencing: SelfReferencing) { self.selfReferencing = selfReferencing }
					    @Instantiated let selfReferencing: SelfReferencing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenInstantiatedPropertyHasForwardedArgument() async {
		await assertThrowsError(
			"""
			Property `child: Child` on Root has at least one @Forwarded property. Property should instead be of type `Instantiator<Child>`.
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(name: String) { self.name = name }
					    @Forwarded let name: String
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenReceivedInstantiatorDependencyCycleExists_withRoot() async {
		await assertThrowsError(
			"""
			Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `B` as @Instantiated to fix. Full cycle:
			\tInstantiator<A> -> B -> Instantiator<A>
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true, generateMock: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Instantiated let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct A: Instantiable {
					    public init(b: B) { self.b = b }
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct B: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received let aBuilder: Instantiator<A>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenReceivedInstantiatorDependencyCycleExists_withoutRoot() async {
		// Same cycle as the _withRoot test but no root — the cycle is only visible
		// after mock generation promotes @Received dependencies.
		await assertThrowsError(
			"""
			Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `B` as @Instantiated to fix. Full cycle:
			\tInstantiator<A> -> B -> Instantiator<A>
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct A: Instantiable {
					    public init(b: B) { self.b = b }
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct B: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received let aBuilder: Instantiator<A>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_misconfiguredMockMethodEmitsComment() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Parent: Instantiable {
				    public init(child: Child, shared: Shared?) {
				        self.child = child
				        self.shared = shared
				    }
				    @Received let child: Child
				    @Received(onlyIfAvailable: true) let shared: Shared?
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Child: Instantiable {
				    public init(unrelated: Unrelated?, shared: Shared?) {
				        self.unrelated = unrelated
				        self.shared = shared
				    }
				    @Received(onlyIfAvailable: true) let unrelated: Unrelated?
				    @Received(onlyIfAvailable: true) let shared: Shared?

				    public static func mock() -> Child {
				        Child(unrelated: nil, shared: nil)
				    }
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Shared: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Unrelated: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		// Child's mock() is missing required dependency parameters (unrelated, shared).
		// The generated mock emits the "incorrectly configured" comment in the .mock()
		// call, triggering a build error that directs the user to the macro fix-it.
		#expect(output.mockFiles["Parent+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Parent {
		    public struct SafeDIParameters {
		        public struct Child_Configuration {
		            public init(
		                _ safeDIBuilder: ((Unrelated?, Shared?) -> Child)? = nil
		            ) {
		                self.safeDIBuilder = safeDIBuilder
		            }

		            public let safeDIBuilder: ((Unrelated?, Shared?) -> Child)?
		        }

		        public init(
		            child: Child_Configuration = .init()
		        ) {
		            self.child = child
		        }

		        public let child: Child_Configuration
		    }

		    public static func mock(
		        shared: Shared? = nil,
		        unrelated: Unrelated? = nil,
		        safeDIParameters: SafeDIParameters = .init()
		    ) -> Parent {
		        let child = (safeDIParameters.child.safeDIBuilder ?? Child.mock(unrelated:shared:))(unrelated, shared)
		        return Parent(child: child, shared: shared)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Parent+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_mockMethodMissingDependencyEmitsComment() async throws {
		// Parent has a child whose mock() takes only some of its dependencies.
		// The .mock() call emits the "incorrectly configured" comment, triggering
		// a build error that directs the user to the macro fix-it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public struct Root: Instantiable {
				    public init(presenter: Presenter) { self.presenter = presenter }
				    @Instantiated let presenter: Presenter
				}
				""",
				"""
				@Instantiable(generateMock: true, customMockName: "customMock")
				public struct Presenter: Instantiable {
				    public init(service: Service, client: Client) {
				        self.service = service
				        self.client = client
				    }
				    @Instantiated let service: Service
				    @Instantiated let client: Client
				    public static func customMock(service: Service) -> Presenter {
				        Presenter(service: service, client: Client())
				    }
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Service: Instantiable {
				    public init() {}
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct Client: Instantiable {
				    public init() {}
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		// Presenter's mock() takes only `service`, not `client`.
		// The generated mock emits a comment in the .mock() call that triggers
		// a build error, directing the user to the @Instantiable macro fix-it.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    public struct SafeDIParameters {
		        public struct Service_Configuration {
		            public init(
		                _ safeDIBuilder: (() -> Service)? = nil
		            ) {
		                self.safeDIBuilder = safeDIBuilder
		            }

		            public let safeDIBuilder: (() -> Service)?
		        }

		        public struct Client_Configuration {
		            public init(
		                _ safeDIBuilder: (() -> Client)? = nil
		            ) {
		                self.safeDIBuilder = safeDIBuilder
		            }

		            public let safeDIBuilder: (() -> Client)?
		        }

		        public struct Presenter_Configuration {
		            public init(
		                service: Service_Configuration = .init(),
		                client: Client_Configuration = .init(),
		                _ safeDIBuilder: ((Service) -> Presenter)? = nil
		            ) {
		                self.service = service
		                self.client = client
		                self.safeDIBuilder = safeDIBuilder
		            }

		            public let service: Service_Configuration
		            public let client: Client_Configuration
		            public let safeDIBuilder: ((Service) -> Presenter)?
		        }

		        public init(
		            presenter: Presenter_Configuration = .init()
		        ) {
		            self.presenter = presenter
		        }

		        public let presenter: Presenter_Configuration
		    }

		    public static func mock(
		        safeDIParameters: SafeDIParameters = .init()
		    ) -> Root {
		        let service = (safeDIParameters.presenter.service.safeDIBuilder ?? Service.init)()
		        let client = (safeDIParameters.presenter.client.safeDIBuilder ?? Client.init)()
		        let presenter = (safeDIParameters.presenter.safeDIBuilder ?? Presenter.customMock(service:))(service)
		        return Root(presenter: presenter)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_parseErrorWritesErrorStubToMockOutputs() async throws {
		// When source has parse errors, mock outputs should get the error stub too
		// (not be left stale or missing).
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public struct Root: Instantiable {
				    public init() {}

				    :::brokenSyntax
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		// Both dependency tree AND mock outputs should have the error.
		// Path is dynamic so we check for the #error directive presence.
		let rootDependencyTree = try #require(output.dependencyTreeFiles["Root+SafeDI.swift"])
		#expect(rootDependencyTree.contains("#error"), "Dependency tree output should have #error. Output:\n\(rootDependencyTree)")
		let rootMock = try #require(output.mockFiles["Root+SafeDIMock.swift"])
		#expect(rootMock.contains("#error"), "Mock output should have #error. Output:\n\(rootMock)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsError_whenNonRootInstantiatedPropertyHasForwardedArgument() async {
		// Parent is NOT a root — only generateMock: true. Child has @Forwarded.
		// Production validation never sees this graph (no root entry point),
		// but mock generation must still catch the forwarded-property error.
		await assertThrowsError(
			"""
			Property `child: Child` on Parent has at least one @Forwarded property. Property should instead be of type `Instantiator<Child>`.
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(generateMock: true)
					public struct Parent: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable(generateMock: true)
					public struct Child: Instantiable {
					    public init(name: String) { self.name = name }
					    @Forwarded let name: String
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete = [URL]()
}
