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

/// A dependency cycle is accepted when any dependency that instantiates along it is an instantiator, wherever a tree
/// enters it: a cycle closed by a constant or a lazily instantiated dependency calls the builder function of the
/// declaration it repeats, as a cycle closed by an instantiator hands that function to its instantiator. Each time the
/// instantiator builds its type, every other type on the cycle is built again too. A cycle closed by a receive, and a
/// cycle with no instantiator along it, stay errors. Most trees are compared by value with a tree built by hand.
struct SafeDIToolDeferredHopCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A constant closes the cycle

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantCallingEnclosingBuilder_whenRootEntersCycleAtConstantAndInstantiatorIsAlongIt() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == ["Root+SafeDI.swift": Self.rootEnteringFamilyAtConstant])
		// Each `cBuilder.instantiate()` builds a new `C`, and in it a new `A` and `B`.
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> { C(a: a()) }))
			        }
			        self.init(a: a())
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantCallingEnclosingBuilder_whenInstantiatorIsInTheMiddleOfCycle() async throws {
		// `Root` enters the cycle at `a`; the cycle `b -> c -> a: Instantiator<A> -> b` closes at `A.b` inside the type the
		// instantiator builds.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let c: C"),
			Self.type("C", "@Instantiated let a: Instantiator<A>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_c() -> C {
			                    func __safeDI_a() -> A {
			                        let b: B = __safeDI_b()
			                        return A(b: b)
			                    }
			                    let a = Instantiator<A>(__safeDI_a)
			                    return C(a: a)
			                }
			                let c: C = __safeDI_c()
			                return B(c: c)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func b() -> B {
			            B(c: C(a: Instantiator<A> { A(b: b()) }))
			        }
			        self.init(a: A(b: b()))
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithInstantiatorAsBefore_whenRootEntersCycleAtInstantiator() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == ["Root+SafeDI.swift": Self.rootEnteringFamilyAtInstantiator])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantCallingEnclosingBuilder_whenDeferredHopIsErasedInstantiator() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", #"@Instantiated(fulfilledByType: "C", erasedToConcreteExistential: true) let cBuilder: ErasedInstantiator<(), AnyC>"#),
			Self.type("C", attributes: "(fulfillingAdditionalTypes: [CProtocol.self])", "@Instantiated let a: A", conformances: ", CProtocol") + """


			public protocol CProtocol {}

			public struct AnyC: CProtocol {
			    public init(_ c: any CProtocol) {
			        self.c = c
			    }

			    public let c: any CProtocol
			}
			""",
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    return C(a: a)
			                }
			                let cBuilder = ErasedInstantiator<(), AnyC> {
			                    AnyC(__safeDI_cBuilder())
			                }
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantTypedAsItsProperty_whenClosingConstantIsFulfilledByAnotherType() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", #"@Instantiated(fulfilledByType: "A") let a: any AProtocol"#),
			Self.type("A", attributes: "(fulfillingAdditionalTypes: [AProtocol.self])", "@Instantiated let b: B", conformances: ", AProtocol") + "\n\npublic protocol AProtocol: AnyObject {}",
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", #"@Instantiated(fulfilledByType: "A") let a: any AProtocol"#),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: any AProtocol = __safeDI_a()
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: any AProtocol = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantSpelledAsDeclared_whenClosedOnTypeIsNested() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: Outer.A"),
			"public enum Outer {\n" + Self.type("A", "@Instantiated let b: B").split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "    \($0)" }.joined(separator: "\n") + "\n}",
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: Outer.A"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> Outer.A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: Outer.A = __safeDI_a()
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return Outer.A(b: b)
			        }
			        let a: Outer.A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantSpelledAsDeclared_whenClosedOnTypeIsSpelledThroughTypealias() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", #"@Instantiated(fulfilledByType: "A") let a: AAlias"#),
			Self.type("A", "@Instantiated let b: B") + "\n\npublic typealias AAlias = A",
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", #"@Instantiated(fulfilledByType: "A") let a: AAlias"#),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: AAlias = __safeDI_a()
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: AAlias = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesForwardedArgumentsOnlyToInstantiatorsFunction_whenTypeBuiltByInstantiatorForwardsAndConstantClosesCycle() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A", "@Forwarded let name: String"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder(name: String) -> C {
			                    let a: A = __safeDI_a()
			                    return C(a: a, name: name)
			                }
			                let cBuilder = Instantiator<C> {
			                    __safeDI_cBuilder(name: $0)
			                }
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsRenamedEnclosingBuilder_whenConstantClosesCycleBeneathFunctionTheShadowingRuleRenames() async throws {
		// `X`'s body declares the builder function of its own `a: A`, beside `z`, whose tree closes a cycle on the root's
		// `a: Other`: `X`'s function is renamed, and the constant that closes `A`'s cycle calls it by its new name.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: Other"),
			Self.type("Other", "@Instantiated let x: X"),
			Self.type("X", "@Instantiated let a: A", "@Instantiated let z: Z"),
			Self.type("Z", "@Instantiated let yBuilder: Instantiator<Y>"),
			Self.type("Y", "@Instantiated let a: Other"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> Other {
			            func __safeDI_x() -> X {
			                func __safeDI_a_A() -> A {
			                    func __safeDI_b() -> B {
			                        func __safeDI_cBuilder() -> C {
			                            let a: A = __safeDI_a_A()
			                            return C(a: a)
			                        }
			                        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                        return B(cBuilder: cBuilder)
			                    }
			                    let b: B = __safeDI_b()
			                    return A(b: b)
			                }
			                let a: A = __safeDI_a_A()
			                func __safeDI_z() -> Z {
			                    func __safeDI_yBuilder() -> Y {
			                        let a: Other = __safeDI_a()
			                        return Y(a: a)
			                    }
			                    let yBuilder = Instantiator<Y>(__safeDI_yBuilder)
			                    return Z(yBuilder: yBuilder)
			                }
			                let z: Z = __safeDI_z()
			                return X(a: a, z: z)
			            }
			            let x: X = __safeDI_x()
			            return Other(x: x)
			        }
			        let a: Other = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	// MARK: Tests – A lazily instantiated dependency closes the cycle, or is closed on

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEnclosingBuilderToWrapper_whenLazilyInstantiatedDependencyClosesCycleOnConstant() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: LazilyInstantiated<A>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a = LazilyInstantiated<A>(__safeDI_a)
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
		#expect(output.warnings.isEmpty)
		// Each `C` holds a wrapper whose instance is a new `A`, built the first time it is read.
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> { C(a: LazilyInstantiated<A>(a)) }))
			        }
			        self.init(a: a())
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsEnclosingBuilderToWrapper_whenLazilyInstantiatedDependencyClosesCycleOnLazilyInstantiatedDeclaration() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: LazilyInstantiated<A>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: LazilyInstantiated<A>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a = LazilyInstantiated<A>(__safeDI_a)
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a = LazilyInstantiated<A>(__safeDI_a)
			        self.init(a: a)
			    }
			}
			""",
		])
		#expect(output.warnings.isEmpty)
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> { C(a: LazilyInstantiated<A>(a)) }))
			        }
			        self.init(a: LazilyInstantiated<A>(a))
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsWrappersBuilder_whenConstantClosesCycleOnLazilyInstantiatedDeclaration() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: LazilyInstantiated<A>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a = LazilyInstantiated<A>(__safeDI_a)
			        self.init(a: a)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> { C(a: a()) }))
			        }
			        self.init(a: LazilyInstantiated<A>(a))
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_closesCycleAsProductionDoes_whenLazilyInstantiatedDependencyClosesCycleOnRootsLazilyInstantiatedDeclaration() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let a: LazilyInstantiated<A>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: LazilyInstantiated<A>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            a: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.a = a
			        }

			        private(set) var a: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a = LazilyInstantiated<A>(__safeDI_a)
			                    return if let safeDIBuilder = safeDIOverrides.a.b.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return if let safeDIBuilder = safeDIOverrides.a.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			            }
			            let b: B = __safeDI_b()
			            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let a = LazilyInstantiated<A>(__safeDI_a)
			        return Root(a: a)
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> { C(a: LazilyInstantiated<A>(a)) }))
			        }
			        self.init(a: LazilyInstantiated<A>(a))
			    }

			    static func mock() -> Root {
			        Root()
			    }
			}
			""",
		], probes: ["Root()", "Root.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_closesCycleAsProductionDoes_whenConstantClosesCycleOnRootsLazilyInstantiatedDeclaration() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let a: LazilyInstantiated<A>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            a: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.a = a
			        }

			        private(set) var a: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    return if let safeDIBuilder = safeDIOverrides.a.b.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return if let safeDIBuilder = safeDIOverrides.a.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			            }
			            let b: B = __safeDI_b()
			            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let a = LazilyInstantiated<A>(__safeDI_a)
			        return Root(a: a)
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> { C(a: a()) }))
			        }
			        self.init(a: LazilyInstantiated<A>(a))
			    }

			    static func mock() -> Root {
			        Root()
			    }
			}
			""",
		], probes: ["Root()", "Root.mock()"])
	}

	// MARK: Tests – Builder functions the cycle closes on take cycle parameters

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclarationToEnclosingBuilder_whenConstantClosesCycleBeneathScopeDeclaringLabelTreeReceives() async throws {
		// `B` receives `session`; `C`, between the root's `a` and the constant that closes the cycle, declares its own.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", "@Instantiated let a: A"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B"),
			Self.type("B", "@Received let session: Session", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let session: Session", "@Instantiated let a: A"),
			Self.type("Session"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_a(session: Session) -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let session = Session()
			                    let a: A = __safeDI_a(session: session)
			                    return C(session: session, a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(session: session, cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a(session: session)
			        self.init(session: session, a: a)
			    }
			}
			""",
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            b: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.session = session
			            self.b = b
			        }

			        private(set) var session: (() -> Session)?
			        private(set) var b: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_b(session: Session) -> B {
			            func __safeDI_cBuilder() -> C {
			                let session = if let safeDIBuilder = safeDIOverrides.b.cBuilder.session { safeDIBuilder() } else { Session() }
			                func __safeDI_a() -> A {
			                    let b: B = __safeDI_b(session: session)
			                    return A(b: b)
			                }
			                let a: A = __safeDI_a()
			                return if let safeDIBuilder = safeDIOverrides.b.cBuilder.safeDIBuilder { safeDIBuilder(session, a) } else { C(session: session, a: a) }
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = safeDIOverrides.b.safeDIBuilder { safeDIBuilder(session, cBuilder) } else { B(session: session, cBuilder: cBuilder) }
			        }
			        let b: B = __safeDI_b(session: session)
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((B) -> A)?
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension C {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            session: (() -> Session)? = nil,
			            _ safeDIBuilder: ((Session, A) -> C)? = nil
			        ) {
			            self.session = session
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var session: (() -> Session)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Session, A) -> C)?
			    }
			}

			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            cBuilder: C.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Session, Instantiator<C>) -> B)? = nil
			        ) {
			            self.cBuilder = cBuilder
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var cBuilder: C.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Session, Instantiator<C>) -> B)?
			    }
			}
			#endif
			""" + "\n",
		])
		// The `B` built again receives the `session` of the `C` that builds it.
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			func makeA(session: Session) -> A {
			    A(b: B(session: session, cBuilder: Instantiator<C> {
			        let cSession = Session()
			        return C(session: cSession, a: makeA(session: cSession))
			    }))
			}

			extension Root {
			    public convenience init() {
			        let session = Session()
			        self.init(session: session, a: makeA(session: session))
			    }
			}

			extension A {
			    static func mock() -> A {
			        makeA(session: Session())
			    }
			}
			""",
		], probes: ["Root()", "A.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesNearestDeclarationToEnclosingBuilder_whenLazilyInstantiatedDependencyClosesCycleBeneathScopeDeclaringLabelTreeReceives() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", "@Instantiated let a: LazilyInstantiated<A>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Received let session: Session", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let session: Session", "@Instantiated let a: LazilyInstantiated<A>"),
			Self.type("Session"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_a(session: Session) -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let session = Session()
			                    let a = LazilyInstantiated<A> {
			                        __safeDI_a(session: session)
			                    }
			                    return C(session: session, a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(session: session, cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a = LazilyInstantiated<A> {
			            __safeDI_a(session: session)
			        }
			        self.init(session: session, a: a)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			func makeA(session: Session) -> A {
			    A(b: B(session: session, cBuilder: Instantiator<C> {
			        let cSession = Session()
			        return C(session: cSession, a: LazilyInstantiated<A> { makeA(session: cSession) })
			    }))
			}

			extension Root {
			    public convenience init() {
			        let session = Session()
			        self.init(session: session, a: LazilyInstantiated<A> { makeA(session: session) })
			    }
			}
			""",
		], probes: ["Root()"])
	}

	// MARK: Tests – Cycles that stay errors

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleErrorNamingEveryDependencyAlongIt_whenNoDependencyAlongCycleIsInstantiator() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["C.swift"]):7:5: error: Dependency cycle: `A` -> `B` -> `C` -> `A`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `a: A`, `b: B`, `c: C` to an instantiator.
			\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
			\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
			\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
				Self.type("A", "@Instantiated let b: B"),
				Self.type("B", "@Instantiated let c: C"),
				Self.type("C", "@Instantiated let a: A"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleErrorNamingLazilyInstantiatedDependencyAsConstant_whenOnlyLazilyInstantiatedDependencyAlongCycleIsNotConstant() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["C.swift"]):7:5: error: Dependency cycle: `A` -> `B` -> `C` -> `A`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `a: A`, `b: B`, `c: C` to an instantiator. A lazily instantiated dependency is created once, so it cannot break a dependency cycle: `c: LazilyInstantiated<C>` is validated as `c: C`.
			\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
			\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
			\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
				Self.type("A", "@Instantiated let b: B"),
				Self.type("B", "@Instantiated let c: LazilyInstantiated<C>"),
				Self.type("C", "@Instantiated let a: A"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleErrorNamingTheOnlyDependency_whenConstantInstantiatesItsOwnType() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["A.swift"]):9:5: error: Dependency cycle: `A` -> `A`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change `a: A` to an instantiator.
			\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
				Self.type("A", "@Instantiated let b: B", "@Instantiated let a: A"),
				Self.type("B"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsCycleError_whenInstantiatorLeadsIntoCycleWithNoInstantiatorAlongIt() async {
		// `f0Builder` enters the cycle `f1 -> f2 -> f0 -> f1` but is not on it: every `F0` the cycle builds would build
		// another `F1` at once, without end.
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["F0.swift"]):7:5: error: Dependency cycle: `F1` -> `F2` -> `F0` -> `F1`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `f1: F1`, `f2: F2`, `f0: F0` to an instantiator.
			\(fixtures["F1.swift"]):1:1: note: `F1` is part of the cycle
			\(fixtures["F2.swift"]):1:1: note: `F2` is part of the cycle
			\(fixtures["F0.swift"]):1:1: note: `F0` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let f0Builder: Instantiator<F0>"),
				Self.type("F0", "@Instantiated let f1: F1"),
				Self.type("F1", "@Instantiated let f2: F2"),
				Self.type("F2", "@Instantiated let f0: F0"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsSameCycleErrorFromEveryEntry_whenDeclarationClosesCycleWithInstantiatorAndCycleWithout() async {
		// `C.a` closes `a -> cBuilder -> a`, which has an instantiator, and `a -> b -> c -> a`, which has none.
		let types = [
			Self.type("A", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let c: C"),
			Self.type("C", "@Instantiated let a: A"),
		]
		let diagnostics: (FixturePaths) -> String = { fixtures in
			"""
			\(fixtures["C.swift"]):7:5: error: Dependency cycle: `A` -> `B` -> `C` -> `A`. SafeDI accepts a dependency cycle when one of the dependencies that instantiate along it is an @Instantiated instantiator, such as an `Instantiator` or `ErasedInstantiator`, which builds its type each time it is called. Change one of `a: A`, `b: B`, `c: C` to an instantiator.
			\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
			\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
			\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
			"""
		}
		await assertThrowsError(diagnostics: diagnostics) {
			try await executeSafeDIToolTest(swiftFileContent: [Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A")] + types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		await assertThrowsError(diagnostics: diagnostics) {
			try await executeSafeDIToolTest(swiftFileContent: [Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let cBuilder: Instantiator<C>")] + types, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_throwsReceivedCycleError_whenReceiveClosesCycleWithInstantiatorAlongIt() async {
		await assertThrowsError(diagnostics: { fixtures in
			"""
			\(fixtures["C.swift"]):7:5: error: Dependency cycle: `A` -> `B` -> `Instantiator<C>` -> `A`. `C` receives `a: A`, which is still being built when `C` is built. Remove this @Received property, or receive it with `onlyIfAvailable: true` and an optional type so that it is not required.
			\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
			\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
			\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
			"""
		}) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
				Self.type("A", "@Instantiated let b: B"),
				Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
				Self.type("C", "@Received let a: A"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – Mocks of types on the cycle

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_closesCycleWithConstantInsideTypeBuiltAgain_whenMockedTypeIsClosedOnThroughInstantiator() async throws {
		// `A.mock()` builds `b`, whose instantiator builds `C`, whose `a` builds an `A` again, whose `b` closes the cycle.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": Self.rootEnteringFamilyAtInstantiator,
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            b: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.b = b
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_b() -> B {
			            func __safeDI_cBuilder() -> C {
			                func __safeDI_a() -> A {
			                    let b: B = __safeDI_b()
			                    return A(b: b)
			                }
			                let a: A = __safeDI_a()
			                return if let safeDIBuilder = safeDIOverrides.b.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = safeDIOverrides.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			        }
			        let b: B = __safeDI_b()
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((B) -> A)?
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + Self.mockConfigurationsOfCAndB + "\n",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": Self.handBuiltFamily + """


			extension Root {
			    public convenience init() {
			        self.init(cBuilder: Instantiator<C> { C(a: makeA()) })
			    }
			}

			extension A {
			    static func mock() -> A {
			        makeA()
			    }
			}
			""",
		], probes: ["Root()", "A.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_closesCycleWithConstantOnMockedTypesOwnDependency_whenMockedTypeIsBuiltAgainThroughInstantiator() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", attributes: "(generateMock: true)", "@Instantiated let a: A"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": Self.rootEnteringFamilyAtInstantiator,
			"C+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension C {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            a: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.a = a
			        }

			        private(set) var a: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> C {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    return if let safeDIBuilder = safeDIOverrides.a.b.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return if let safeDIBuilder = safeDIOverrides.a.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			            }
			            let b: B = __safeDI_b()
			            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let a: A = __safeDI_a()
			        return C(a: a)
			    }
			}
			#endif

			#if DEBUG
			extension C {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            _ safeDIBuilder: ((A) -> C)? = nil
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((A) -> C)?
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            cBuilder: C.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<C>) -> B)? = nil
			        ) {
			            self.cBuilder = cBuilder
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var cBuilder: C.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Instantiator<C>) -> B)?
			    }
			}

			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((B) -> A)?
			    }
			}
			#endif
			""" + "\n",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": Self.handBuiltFamily + """


			extension Root {
			    public convenience init() {
			        self.init(cBuilder: Instantiator<C> { C(a: makeA()) })
			    }
			}

			extension C {
			    static func mock() -> C {
			        C(a: makeA())
			    }
			}
			""",
		], probes: ["Root()", "C.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_closesCycleWithInstantiatorAsBefore_whenMockedTypeHoldsTheInstantiator() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", attributes: "(generateMock: true)", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": Self.rootEnteringFamilyAtInstantiator,
			"B+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            cBuilder: C.SafeDIMockConfiguration = .init()
			        ) {
			            self.cBuilder = cBuilder
			        }

			        private(set) var cBuilder: C.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_cBuilder() -> C {
			            func __safeDI_a() -> A {
			                func __safeDI_b() -> B {
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    return B(cBuilder: cBuilder)
			                }
			                let b: B = __safeDI_b()
			                return A(b: b)
			            }
			            let a: A = __safeDI_a()
			            return if let safeDIBuilder = safeDIOverrides.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        return B(cBuilder: cBuilder)
			    }
			}
			#endif

			#if DEBUG
			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            cBuilder: C.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<C>) -> B)? = nil
			        ) {
			            self.cBuilder = cBuilder
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var cBuilder: C.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Instantiator<C>) -> B)?
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((B) -> A)?
			    }
			}

			extension C {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            _ safeDIBuilder: ((A) -> C)? = nil
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((A) -> C)?
			    }
			}
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesOneConfigurationOfEachType_whenRootsEnterCycleAtConstantAndAtInstantiatorAndTwoTypesOnItAreMocked() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("Root2", attributes: "(isRoot: true)", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", attributes: "(generateMock: true)", "@Instantiated let a: A"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": Self.rootEnteringFamilyAtConstant,
			"Root2+SafeDI.swift": Self.rootEnteringFamilyAtInstantiator.replacingOccurrences(of: "extension Root {", with: "extension Root2 {"),
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            b: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.b = b
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_b() -> B {
			            func __safeDI_cBuilder() -> C {
			                func __safeDI_a() -> A {
			                    let b: B = __safeDI_b()
			                    return A(b: b)
			                }
			                let a: A = __safeDI_a()
			                return if let safeDIBuilder = safeDIOverrides.b.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = safeDIOverrides.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			        }
			        let b: B = __safeDI_b()
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((B) -> A)?
			    }
			}
			#endif
			""",
			"C+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension C {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            a: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.a = a
			        }

			        private(set) var a: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> C {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    return if let safeDIBuilder = safeDIOverrides.a.b.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return if let safeDIBuilder = safeDIOverrides.a.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			            }
			            let b: B = __safeDI_b()
			            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let a: A = __safeDI_a()
			        return C(a: a)
			    }
			}
			#endif

			#if DEBUG
			extension C {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            _ safeDIBuilder: ((A) -> C)? = nil
			        ) {
			            self.safeDIBuilder = safeDIBuilder
			        }

			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((A) -> C)?
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            cBuilder: C.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<C>) -> B)? = nil
			        ) {
			            self.cBuilder = cBuilder
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var cBuilder: C.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Instantiator<C>) -> B)?
			    }
			}
			#endif
			""" + "\n",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_appliesOverrideToEveryBuildOfType_whenConstantClosesCycleOnTheOverriddenType() async throws {
		// The override of `b` is read in the function the closer calls, so it builds the mock's own `b` and the `b` of each
		// `A` the instantiator builds again: three after two calls.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B") + "\n\nfinal class OverrideCalls {\n    var count = 0\n}",
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let probe = "{ let calls = OverrideCalls(); let a = A.mock(safeDIOverrides: .init(b: .init { cBuilder in calls.count += 1; return B(cBuilder: cBuilder) })); _ = a.b.cBuilder.instantiate().a.b.cBuilder.instantiate(); return calls.count }()"
		try expectValuesAgree(of: fixture, output: output, knownRight: [:], probes: [probe], knownRightExpressions: [probe: "3"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsSiblingDisambiguatedBuilder_whenConstantClosesCycleOnPromotedDependencyWhoseLabelAnotherPromotedDependencyShares() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("M", attributes: "(generateMock: true)", "@Instantiated let p: P", "@Instantiated let d: D"),
			Self.type("P", "@Received let a: A"),
			Self.type("D", "@Received let a: Other"),
			Self.type("Other"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"M+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension M {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            a_A: A.SafeDIMockConfiguration = .init(),
			            p: ((A) -> P)? = nil,
			            a_Other: (() -> Other)? = nil,
			            d: ((Other) -> D)? = nil
			        ) {
			            self.a_A = a_A
			            self.p = p
			            self.a_Other = a_Other
			            self.d = d
			        }

			        private(set) var a_A: A.SafeDIMockConfiguration
			        private(set) var p: ((A) -> P)?
			        private(set) var a_Other: (() -> Other)?
			        private(set) var d: ((Other) -> D)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> M {
			        func __safeDI_a_A() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a_A()
			                    return if let safeDIBuilder = safeDIOverrides.a_A.b.cBuilder.safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return if let safeDIBuilder = safeDIOverrides.a_A.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			            }
			            let b: B = __safeDI_b()
			            return if let safeDIBuilder = safeDIOverrides.a_A.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let a_A: A = __safeDI_a_A()
			        func __safeDI_p() -> P {
			            let a: A = a_A
			            return if let safeDIBuilder = safeDIOverrides.p { safeDIBuilder(a) } else { P(a: a) }
			        }
			        let p: P = __safeDI_p()
			        let a_Other = if let safeDIBuilder = safeDIOverrides.a_Other { safeDIBuilder() } else { Other() }
			        func __safeDI_d() -> D {
			            let a: Other = a_Other
			            return if let safeDIBuilder = safeDIOverrides.d { safeDIBuilder(a) } else { D(a: a) }
			        }
			        let d: D = __safeDI_d()
			        return M(p: p, d: d)
			    }
			}
			#endif
			""",
		])
	}

	// MARK: Tests – Sendable builder functions

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesClosedOnFunctionSendable_whenConstantClosesCycleInsideSendableInstantiatorsBuilder() async throws {
		// `A` is not `Sendable`: a `@Sendable` function may return it, and captures nothing that is not.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: SendableInstantiator<C>"),
			Self.type("C", "@Instantiated let a: A"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                @Sendable func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    return C(a: a)
			                }
			                let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesClosedOnFunctionSendable_whenSendableLazilyInstantiatedDependencyClosesCycleOnConstant() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B", conformances: ", Sendable"),
			Self.type("B", "@Instantiated let cBuilder: SendableInstantiator<C>", conformances: ", Sendable"),
			Self.type("C", "@Instantiated let a: SendableLazilyInstantiated<A>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                @Sendable func __safeDI_cBuilder() -> C {
			                    let a = SendableLazilyInstantiated<A>(__safeDI_a)
			                    return C(a: a)
			                }
			                let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
			"A+SafeDIMock.swift": Self.sendableFamilyMockOfA,
			"SafeDIMockConfiguration.swift": Self.sendableFamilyMockConfigurations(instantiatorType: "SendableInstantiator<C>"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsSendableEnclosingBuilderToWrapper_whenSendableLazilyInstantiatedDependencyClosesCycleOnItsOwnKind() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: SendableLazilyInstantiated<A>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B", conformances: ", Sendable"),
			Self.type("B", "@Instantiated let cBuilder: SendableInstantiator<C>", conformances: ", Sendable"),
			Self.type("C", "@Instantiated let a: SendableLazilyInstantiated<A>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                @Sendable func __safeDI_cBuilder() -> C {
			                    let a = SendableLazilyInstantiated<A>(__safeDI_a)
			                    return C(a: a)
			                }
			                let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a = SendableLazilyInstantiated<A>(__safeDI_a)
			        self.init(a: a)
			    }
			}
			""",
			"A+SafeDIMock.swift": Self.sendableFamilyMockOfA,
			"SafeDIMockConfiguration.swift": Self.sendableFamilyMockConfigurations(instantiatorType: "SendableInstantiator<C>"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsOverridesOutsideSendableFunctionTheCycleClosesOn_whenMockedTypeInstantiatesTypeWhoseOverrideIsNotSendable() async throws {
		// `x`'s override closure is not `@Sendable`, so neither is `A.SafeDIOverrides`: the `@Sendable` function `b` builds
		// in reads its overrides into locals declared before it.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B", "@Instantiated let x: X", conformances: ", Sendable"),
			Self.type("B", "@Instantiated let cBuilder: SendableInstantiator<C>", conformances: ", Sendable"),
			Self.type("C", "@Instantiated let a: SendableLazilyInstantiated<A>", conformances: ", Sendable"),
			Self.type("X", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            x: (() -> X)? = nil
			        ) {
			            self.b = b
			            self.x = x
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        private(set) var x: (() -> X)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let __safeDI_b__b_cBuilder_safeDIBuilder = safeDIOverrides.b.cBuilder.safeDIBuilder
			        let __safeDI_b__safeDIBuilder = safeDIOverrides.b.safeDIBuilder
			        @Sendable func __safeDI_b() -> B {
			            @Sendable func __safeDI_cBuilder() -> C {
			                @Sendable func __safeDI_a() -> A {
			                    let b: B = __safeDI_b()
			                    let x = X()
			                    return A(b: b, x: x)
			                }
			                let a = SendableLazilyInstantiated<A>(__safeDI_a)
			                return if let safeDIBuilder = __safeDI_b__b_cBuilder_safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			            }
			            let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = __safeDI_b__safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			        }
			        let b: B = __safeDI_b()
			        let x = if let safeDIBuilder = safeDIOverrides.x { safeDIBuilder() } else { X() }
			        return A(b: b, x: x)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            x: (@Sendable () -> X)? = nil,
			            _ safeDIBuilder: (@Sendable (B, X) -> A)? = nil
			        ) {
			            self.b = b
			            self.x = x
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        private(set) var x: (@Sendable () -> X)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: (@Sendable (B, X) -> A)?
			    }
			}
			#endif
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesClosedOnFunctionSendable_whenSendableLazilyInstantiatedDependencyClosesCycleWithNoSendableBuilderBetween() async throws {
		// `A` holds a plain `Instantiator` in its tree, which a `Sendable` type could not, so it is `@unchecked Sendable`.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B", conformances: ", @unchecked Sendable"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: SendableLazilyInstantiated<A>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a = SendableLazilyInstantiated<A>(__safeDI_a)
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            b: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.b = b
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let __safeDI_b__b_cBuilder_safeDIBuilder = safeDIOverrides.b.cBuilder.safeDIBuilder
			        let __safeDI_b__safeDIBuilder = safeDIOverrides.b.safeDIBuilder
			        @Sendable func __safeDI_b() -> B {
			            func __safeDI_cBuilder() -> C {
			                @Sendable func __safeDI_a() -> A {
			                    let b: B = __safeDI_b()
			                    return A(b: b)
			                }
			                let a = SendableLazilyInstantiated<A>(__safeDI_a)
			                return if let safeDIBuilder = __safeDI_b__b_cBuilder_safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = __safeDI_b__safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			        }
			        let b: B = __safeDI_b()
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: (@Sendable (B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: (@Sendable (B) -> A)?
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": Self.sendableFamilyMockConfigurations(instantiatorType: "Instantiator<C>"),
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_makesClosedOnFunctionSendable_whenSendableLazilyInstantiatedDependencyClosesCycleOnLazilyInstantiatedDeclarationWithNoSendableBuilderBetween() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: LazilyInstantiated<A>"),
			Self.type("A", "@Instantiated let b: B", conformances: ", @unchecked Sendable"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: SendableLazilyInstantiated<A>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a = SendableLazilyInstantiated<A>(__safeDI_a)
			                    return C(a: a)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a = LazilyInstantiated<A>(__safeDI_a)
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	// MARK: Tests – A cycle repeats a declaration built for the same type

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachDeclarationsOwnType_whenTwoDeclarationsOfOneLabelAndTypeAreFulfilledByDifferentTypes() async throws {
		// `Settings`' `flow` is built for `SettingsFlow`, not again for the root's `LoggedInFlow`: no cycle.
		let fixture = Self.flowFixture(rootAttributes: "(isRoot: true)", settingsAttributes: "", settingsFlow: #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flow() -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                let flow: Flow = SettingsFlow()
			                return Settings(flow: flow)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(settingsBuilder: settingsBuilder)
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        self.init(flow: LoggedInFlow(settingsBuilder: Instantiator<Settings> { Settings(flow: SettingsFlow()) }))
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsEachDeclarationsOwnType_whenTwoDeclarationsOfOneLabelAndTypeAreFulfilledByDifferentTypes() async throws {
		let fixture = Self.flowFixture(rootAttributes: "(isRoot: true, generateMock: true)", settingsAttributes: "(generateMock: true)", loggedInFlowAttributes: "(generateMock: true)", settingsFlow: #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"LoggedInFlow+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension LoggedInFlow {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            settingsBuilder: Settings.SafeDIMockConfiguration = .init()
			        ) {
			            self.settingsBuilder = settingsBuilder
			        }

			        private(set) var settingsBuilder: Settings.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> LoggedInFlow {
			        func __safeDI_settingsBuilder() -> Settings {
			            let flow: Flow = if let safeDIBuilder = safeDIOverrides.settingsBuilder.flow { safeDIBuilder() } else { SettingsFlow() }
			            return if let safeDIBuilder = safeDIOverrides.settingsBuilder.safeDIBuilder { safeDIBuilder(flow) } else { Settings(flow: flow) }
			        }
			        let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			        return LoggedInFlow(settingsBuilder: settingsBuilder)
			    }
			}
			#endif

			#if DEBUG
			extension LoggedInFlow {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            settingsBuilder: Settings.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Instantiator<Settings>) -> LoggedInFlow)? = nil
			        ) {
			            self.settingsBuilder = settingsBuilder
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var settingsBuilder: Settings.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Instantiator<Settings>) -> LoggedInFlow)?
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flow() -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                let flow: Flow = SettingsFlow()
			                return Settings(flow: flow)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(settingsBuilder: settingsBuilder)
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            flow: LoggedInFlow.SafeDIMockConfiguration = .init()
			        ) {
			            self.flow = flow
			        }

			        private(set) var flow: LoggedInFlow.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_flow() -> Flow {
			            func __safeDI_settingsBuilder() -> Settings {
			                let flow: Flow = if let safeDIBuilder = safeDIOverrides.flow.settingsBuilder.flow { safeDIBuilder() } else { SettingsFlow() }
			                return if let safeDIBuilder = safeDIOverrides.flow.settingsBuilder.safeDIBuilder { safeDIBuilder(flow) } else { Settings(flow: flow) }
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return if let safeDIBuilder = safeDIOverrides.flow.safeDIBuilder { safeDIBuilder(settingsBuilder) } else { LoggedInFlow(settingsBuilder: settingsBuilder) }
			        }
			        let flow: Flow = __safeDI_flow()
			        return Root(flow: flow)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": emptyMockConfigurationFileOutput,
			"Settings+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Settings {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            flow: (() -> Flow)? = nil
			        ) {
			            self.flow = flow
			        }

			        private(set) var flow: (() -> Flow)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Settings {
			        let flow: Flow = if let safeDIBuilder = safeDIOverrides.flow { safeDIBuilder() } else { SettingsFlow() }
			        return Settings(flow: flow)
			    }
			}
			#endif

			#if DEBUG
			extension Settings {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            flow: (() -> Flow)? = nil,
			            _ safeDIBuilder: ((Flow) -> Settings)? = nil
			        ) {
			            self.flow = flow
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var flow: (() -> Flow)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Flow) -> Settings)?
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        self.init(flow: LoggedInFlow(settingsBuilder: Instantiator<Settings> { Settings(flow: SettingsFlow()) }))
			    }

			    static func mock() -> Root {
			        Root()
			    }
			}

			extension Settings {
			    static func mock() -> Settings {
			        Settings(flow: SettingsFlow())
			    }
			}

			extension LoggedInFlow {
			    static func mock() -> LoggedInFlow {
			        LoggedInFlow(settingsBuilder: Instantiator<Settings> { Settings(flow: SettingsFlow()) })
			    }
			}
			""",
		], probes: ["Root.mock()", "Settings.mock()", "LoggedInFlow.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachDeclarationsOwnType_whenTwoErasedInstantiatorsOfOneLabelAndTypeAreFulfilledByDifferentTypes() async throws {
		// Before, the inner instantiator closed a "cycle" on the root's and built a `LoggedInFlow` where `SettingsFlow` was named.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", #"@Instantiated(fulfilledByType: "LoggedInFlow", erasedToConcreteExistential: true) let flowBuilder: ErasedInstantiator<(), AnyFlow>"#) + """


			public protocol Flow: AnyObject {}

			public final class AnyFlow: Flow {
			    public init(_ flow: Flow) {
			        self.flow = flow
			    }

			    public let flow: Flow
			}
			""",
			Self.type("LoggedInFlow", "@Instantiated let settingsBuilder: Instantiator<Settings>", conformances: ", Flow"),
			Self.type("Settings", #"@Instantiated(fulfilledByType: "SettingsFlow", erasedToConcreteExistential: true) let flowBuilder: ErasedInstantiator<(), AnyFlow>"#),
			Self.type("SettingsFlow", conformances: ", Flow"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flowBuilder() -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                func __safeDI_flowBuilder() -> SettingsFlow {
			                    SettingsFlow()
			                }
			                let flowBuilder = ErasedInstantiator<(), AnyFlow> {
			                    AnyFlow(__safeDI_flowBuilder())
			                }
			                return Settings(flowBuilder: flowBuilder)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(settingsBuilder: settingsBuilder)
			        }
			        let flowBuilder = ErasedInstantiator<(), AnyFlow> {
			            AnyFlow(__safeDI_flowBuilder())
			        }
			        self.init(flowBuilder: flowBuilder)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        self.init(flowBuilder: ErasedInstantiator<(), AnyFlow> {
			            AnyFlow(LoggedInFlow(settingsBuilder: Instantiator<Settings> {
			                Settings(flowBuilder: ErasedInstantiator<(), AnyFlow> { AnyFlow(SettingsFlow()) })
			            }))
			        })
			    }
			}
			""",
		], probes: ["Root().flowBuilder.instantiate()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsEachDeclarationsOwnType_whenLazilyInstantiatedDeclarationOfLabelIsFulfilledByAnotherTypeThanTheConstantAboveIt() async throws {
		let fixture = Self.flowFixture(rootAttributes: "(isRoot: true)", settingsAttributes: "", settingsFlow: #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: LazilyInstantiated<Flow>"#)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flow() -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                func __safeDI_flow() -> SettingsFlow {
			                    SettingsFlow()
			                }
			                let flow = LazilyInstantiated<Flow>(__safeDI_flow)
			                return Settings(flow: flow)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(settingsBuilder: settingsBuilder)
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsOuterDeclarationsRenamedBuilder_whenDeclarationOfSameLabelAndTypeForAnotherTypeIsBetweenCloserAndDeclarationItRepeats() async throws {
		// `SettingsFlow`'s `flow` repeats the root's, built for `LoggedInFlow`, past `Settings`' `flow`, built for
		// `SettingsFlow`, whose function would otherwise have the name the closer calls.
		let fixture = Self.flowFixture(
			rootAttributes: "(isRoot: true)",
			settingsAttributes: "",
			settingsFlow: #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#,
			settingsFlowDeclaration: #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#,
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flow() -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                func __safeDI_flow_Flow() -> SettingsFlow {
			                    let flow: Flow = __safeDI_flow()
			                    return SettingsFlow(flow: flow)
			                }
			                let flow: Flow = __safeDI_flow_Flow()
			                return Settings(flow: flow)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(settingsBuilder: settingsBuilder)
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": Self.shadowedClosedOnFlowKnownRight,
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsOuterDeclarationsRenamedBuilder_whenDeclarationOfSameLabelAndTypeForAnotherTypeIsBetweenCloserAndDeclarationItRepeats() async throws {
		let fixture = Self.flowFixture(
			rootAttributes: "(isRoot: true, generateMock: true)",
			settingsAttributes: "",
			settingsFlow: #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#,
			settingsFlowDeclaration: #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#,
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            flow: LoggedInFlow.SafeDIMockConfiguration = .init()
			        ) {
			            self.flow = flow
			        }

			        private(set) var flow: LoggedInFlow.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_flow() -> Flow {
			            func __safeDI_settingsBuilder() -> Settings {
			                func __safeDI_flow_Flow() -> Flow {
			                    let flow: Flow = __safeDI_flow()
			                    return if let safeDIBuilder = safeDIOverrides.flow.settingsBuilder.flow.safeDIBuilder { safeDIBuilder(flow) } else { SettingsFlow(flow: flow) }
			                }
			                let flow: Flow = __safeDI_flow_Flow()
			                return if let safeDIBuilder = safeDIOverrides.flow.settingsBuilder.safeDIBuilder { safeDIBuilder(flow) } else { Settings(flow: flow) }
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return if let safeDIBuilder = safeDIOverrides.flow.safeDIBuilder { safeDIBuilder(settingsBuilder) } else { LoggedInFlow(settingsBuilder: settingsBuilder) }
			        }
			        let flow: Flow = __safeDI_flow()
			        return Root(flow: flow)
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": Self.shadowedClosedOnFlowKnownRight + """


			extension Root {
			    static func mock() -> Root {
			        Root()
			    }
			}
			""",
		], probes: ["Root.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_callsOuterDeclarationsRenamedBuilder_whenMockedTypeIsBuiltAgainPastDeclarationOfSameLabelAndTypeForAnotherType() async throws {
		// In `Settings.mock()`, the `flow` of the `Settings` that `settingsBuilder` builds repeats the mocked type's own,
		// built for `SettingsFlow`, past `SettingsFlow`'s `flow`, built for `LoggedInFlow`.
		let fixture = Self.flowFixture(
			rootAttributes: "(isRoot: true)",
			settingsAttributes: "(generateMock: true)",
			settingsFlow: #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#,
			settingsFlowDeclaration: #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#,
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Settings+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Settings {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            flow: SettingsFlow.SafeDIMockConfiguration = .init()
			        ) {
			            self.flow = flow
			        }

			        private(set) var flow: SettingsFlow.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Settings {
			        func __safeDI_flow() -> Flow {
			            func __safeDI_flow_Flow() -> Flow {
			                func __safeDI_settingsBuilder() -> Settings {
			                    let flow: Flow = __safeDI_flow()
			                    return Settings(flow: flow)
			                }
			                let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			                return LoggedInFlow(settingsBuilder: settingsBuilder)
			            }
			            let flow: Flow = __safeDI_flow_Flow()
			            return if let safeDIBuilder = safeDIOverrides.flow.safeDIBuilder { safeDIBuilder(flow) } else { SettingsFlow(flow: flow) }
			        }
			        let flow: Flow = __safeDI_flow()
			        return Settings(flow: flow)
			    }
			}
			#endif

			#if DEBUG
			extension Settings {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            flow: SettingsFlow.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Flow) -> Settings)? = nil
			        ) {
			            self.flow = flow
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var flow: SettingsFlow.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((Flow) -> Settings)?
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": Self.shadowedClosedOnFlowKnownRight + """


			extension Settings {
			    static func mock() -> Settings {
			        func makeSettingsFlow() -> SettingsFlow {
			            SettingsFlow(flow: LoggedInFlow(settingsBuilder: Instantiator<Settings> { Settings(flow: makeSettingsFlow()) }))
			        }
			        return Settings(flow: makeSettingsFlow())
			    }
			}
			""",
		], probes: ["Settings.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_callsOuterDeclarationsRenamedBuilder_whenConstantOfSameLabelAndTypeForAnotherTypeHoldsInstantiatorThatClosesCycle() async throws {
		// Before, `X`'s `flow`, named `LoggedInFlow`, was the `SettingsFlow` whose function encloses it.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#) + "\n\npublic protocol Flow: AnyObject {}",
			Self.type("LoggedInFlow", #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#, conformances: ", Flow"),
			Self.type("SettingsFlow", "@Instantiated let xBuilder: Instantiator<X>", conformances: ", Flow"),
			Self.type("X", #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flow() -> LoggedInFlow {
			            func __safeDI_flow_Flow() -> SettingsFlow {
			                func __safeDI_xBuilder() -> X {
			                    let flow: Flow = __safeDI_flow()
			                    return X(flow: flow)
			                }
			                let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			                return SettingsFlow(xBuilder: xBuilder)
			            }
			            let flow: Flow = __safeDI_flow_Flow()
			            return LoggedInFlow(flow: flow)
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func makeLoggedInFlow() -> LoggedInFlow {
			            LoggedInFlow(flow: SettingsFlow(xBuilder: Instantiator<X> { X(flow: makeLoggedInFlow()) }))
			        }
			        self.init(flow: makeLoggedInFlow())
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOuterDeclarationsRenamedBuilderToWrapper_whenLazilyInstantiatedDependencyClosesCyclePastDeclarationOfSameLabelForAnotherType() async throws {
		let fixture = Self.flowFixture(
			rootAttributes: "(isRoot: true)",
			settingsAttributes: "",
			settingsFlow: #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#,
			settingsFlowDeclaration: #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: LazilyInstantiated<Flow>"#,
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flow() -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                func __safeDI_flow_Flow() -> SettingsFlow {
			                    let flow = LazilyInstantiated<Flow>(__safeDI_flow)
			                    return SettingsFlow(flow: flow)
			                }
			                let flow: Flow = __safeDI_flow_Flow()
			                return Settings(flow: flow)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(settingsBuilder: settingsBuilder)
			        }
			        let flow: Flow = __safeDI_flow()
			        self.init(flow: flow)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func makeLoggedInFlow() -> LoggedInFlow {
			            LoggedInFlow(settingsBuilder: Instantiator<Settings> {
			                Settings(flow: SettingsFlow(flow: LazilyInstantiated<Flow> { makeLoggedInFlow() }))
			            })
			        }
			        self.init(flow: makeLoggedInFlow())
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_handsOuterDeclarationsRenamedBuilderToInstantiator_whenErasedInstantiatorClosesCyclePastDeclarationOfSameLabelForAnotherType() async throws {
		let erasedFlowBuilder = { (type: String) in #"@Instantiated(fulfilledByType: ""# + type + #"", erasedToConcreteExistential: true) let flowBuilder: ErasedInstantiator<(), AnyFlow>"# }
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", erasedFlowBuilder("LoggedInFlow")) + """


			public protocol Flow: AnyObject {}

			public final class AnyFlow: Flow {
			    public init(_ flow: Flow) {
			        self.flow = flow
			    }

			    public let flow: Flow
			}
			""",
			Self.type("LoggedInFlow", "@Instantiated let settingsBuilder: Instantiator<Settings>", conformances: ", Flow"),
			Self.type("Settings", erasedFlowBuilder("SettingsFlow")),
			Self.type("SettingsFlow", erasedFlowBuilder("LoggedInFlow"), conformances: ", Flow"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_flowBuilder() -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                func __safeDI_flowBuilder_AnyFlow() -> SettingsFlow {
			                    let flowBuilder = ErasedInstantiator<(), AnyFlow> {
			                        AnyFlow(__safeDI_flowBuilder())
			                    }
			                    return SettingsFlow(flowBuilder: flowBuilder)
			                }
			                let flowBuilder = ErasedInstantiator<(), AnyFlow> {
			                    AnyFlow(__safeDI_flowBuilder_AnyFlow())
			                }
			                return Settings(flowBuilder: flowBuilder)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(settingsBuilder: settingsBuilder)
			        }
			        let flowBuilder = ErasedInstantiator<(), AnyFlow> {
			            AnyFlow(__safeDI_flowBuilder())
			        }
			        self.init(flowBuilder: flowBuilder)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func makeLoggedInFlow() -> LoggedInFlow {
			            LoggedInFlow(settingsBuilder: Instantiator<Settings> {
			                Settings(flowBuilder: ErasedInstantiator<(), AnyFlow> {
			                    AnyFlow(SettingsFlow(flowBuilder: ErasedInstantiator<(), AnyFlow> { AnyFlow(makeLoggedInFlow()) }))
			                })
			            })
			        }
			        self.init(flowBuilder: ErasedInstantiator<(), AnyFlow> { AnyFlow(makeLoggedInFlow()) })
			    }
			}
			""",
		], probes: ["Root().flowBuilder.instantiate()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesCycleParametersToOuterDeclarationsRenamedBuilder_whenConstantClosesCyclePastDeclarationOfSameLabelForAnotherType() async throws {
		// `LoggedInFlow` receives `session`, which `Settings` declares again between the closer and the root's `flow`: the
		// root's function takes it, and `Settings`' `flow`, built for `SettingsFlow`, takes nothing.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let session: Session", #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#) + "\n\npublic protocol Flow: AnyObject {}",
			Self.type("LoggedInFlow", "@Received let session: Session", "@Instantiated let settingsBuilder: Instantiator<Settings>", conformances: ", Flow"),
			Self.type("Session"),
			Self.type("Settings", "@Instantiated let session: Session", #"@Instantiated(fulfilledByType: "SettingsFlow") let flow: Flow"#),
			Self.type("SettingsFlow", #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#, conformances: ", Flow"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_flow(session: Session) -> LoggedInFlow {
			            func __safeDI_settingsBuilder() -> Settings {
			                let session = Session()
			                func __safeDI_flow_Flow() -> SettingsFlow {
			                    let flow: Flow = __safeDI_flow(session: session)
			                    return SettingsFlow(flow: flow)
			                }
			                let flow: Flow = __safeDI_flow_Flow()
			                return Settings(session: session, flow: flow)
			            }
			            let settingsBuilder = Instantiator<Settings>(__safeDI_settingsBuilder)
			            return LoggedInFlow(session: session, settingsBuilder: settingsBuilder)
			        }
			        let flow: Flow = __safeDI_flow(session: session)
			        self.init(session: session, flow: flow)
			    }
			}
			""",
		])
		// The `LoggedInFlow` built again receives the `Session` its `Settings` holds.
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func makeLoggedInFlow(session: Session) -> LoggedInFlow {
			            LoggedInFlow(session: session, settingsBuilder: Instantiator<Settings> {
			                let settingsSession = Session()
			                return Settings(session: settingsSession, flow: SettingsFlow(flow: makeLoggedInFlow(session: settingsSession)))
			            })
			        }
			        let session = Session()
			        self.init(session: session, flow: makeLoggedInFlow(session: session))
			    }
			}
			""",
		], probes: ["Root()"])
	}

	// MARK: Tests – A receive resolves to the nearest declaration of its label

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesClosingConstantToReceiver_whenSiblingOfClosingConstantReceivesItsLabel() async throws {
		let fixture = Self.receiverBesideCloserFixture(rootDeclaration: "@Instantiated let a: A", mockedType: nil)
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    let d = D(a: a)
			                    return C(a: a, d: d)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
		// `D` receives the `A` its own `C` holds.
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> {
			                let a = a()
			                return C(a: a, d: D(a: a))
			            }))
			        }
			        self.init(a: a())
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesForwardedPropertyToReceiver_whenTypeBuiltInsideDeclarationOfItsLabelForwardsIt() async throws {
		// Before, `C`'s receive of `a` was rejected as a receive of the `A` still being built around it, though `B`'s
		// forwarded `a` is the nearest declaration of the label.
		let fixture = Self.forwardedNearerDeclarationFixture(mockedTypes: [])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_bBuilder(a: A) -> B {
			                let c = C(a: a)
			                return B(a: a, c: c)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(a: $0)
			            }
			            return A(bBuilder: bBuilder)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
		// `C` receives the `A` `B` is handed.
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": Self.forwardedNearerDeclarationKnownRight,
		], probes: [Self.forwardedNearerDeclarationProbe])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesForwardedPropertyToReceiver_whenTypeBuiltInsideDeclarationOfItsLabelForwardsIt() async throws {
		let fixture = Self.forwardedNearerDeclarationFixture(mockedTypes: ["Root", "B"])
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"B+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            c: ((A) -> C)? = nil
			        ) {
			            self.c = c
			        }

			        private(set) var c: ((A) -> C)?
			    }

			    static func mock(
			        a: A,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        let c = if let safeDIBuilder = safeDIOverrides.c { safeDIBuilder(a) } else { C(a: a) }
			        return B(a: a, c: c)
			    }
			}
			#endif

			#if DEBUG
			extension B {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            c: ((A) -> C)? = nil,
			            _ safeDIBuilder: ((A, C) -> B)? = nil
			        ) {
			            self.c = c
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var c: ((A) -> C)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((A, C) -> B)?
			    }
			}
			#endif
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            a: A.SafeDIMockConfiguration = .init()
			        ) {
			            self.a = a
			        }

			        private(set) var a: A.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_a() -> A {
			            func __safeDI_bBuilder(a: A) -> B {
			                let c = if let safeDIBuilder = safeDIOverrides.a.bBuilder.c { safeDIBuilder(a) } else { C(a: a) }
			                return if let safeDIBuilder = safeDIOverrides.a.bBuilder.safeDIBuilder { safeDIBuilder(a, c) } else { B(a: a, c: c) }
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(a: $0)
			            }
			            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let a: A = __safeDI_a()
			        return Root(a: a)
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": Self.forwardedNearerDeclarationKnownRight + """


			extension Root {
			    static func mock() -> Root {
			        Root()
			    }
			}

			extension B {
			    static func mock(a: A) -> B {
			        B(a: a, c: C(a: a))
			    }
			}
			""",
		], probes: [
			"{ let a = Root.mock().a; return a.bBuilder.instantiate(a) }()",
			"{ let a = Root().a; return B.mock(a: a) }()",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesConstantToReceiverAsBefore_whenRootEntersCycleAtInstantiatorAndSiblingReceivesLabel() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.receiverBesideCloserFixture(rootDeclaration: "@Instantiated let cBuilder: Instantiator<C>", mockedType: nil), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_cBuilder() -> C {
			            func __safeDI_a() -> A {
			                func __safeDI_b() -> B {
			                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                    return B(cBuilder: cBuilder)
			                }
			                let b: B = __safeDI_b()
			                return A(b: b)
			            }
			            let a: A = __safeDI_a()
			            let d = D(a: a)
			            return C(a: a, d: d)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        self.init(cBuilder: cBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesClosingConstantToReceiver_whenMockedTypeDeclaresClosingConstantBesideReceiverOfIt() async throws {
		let fixture = Self.receiverBesideCloserFixture(rootDeclaration: "@Instantiated let cBuilder: Instantiator<C>", mockedType: "C")
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"C+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension C {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            a: A.SafeDIMockConfiguration = .init(),
			            d: ((A) -> D)? = nil
			        ) {
			            self.a = a
			            self.d = d
			        }

			        private(set) var a: A.SafeDIMockConfiguration
			        private(set) var d: ((A) -> D)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> C {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    let d = if let safeDIBuilder = safeDIOverrides.a.b.cBuilder.d { safeDIBuilder(a) } else { D(a: a) }
			                    return if let safeDIBuilder = safeDIOverrides.a.b.cBuilder.safeDIBuilder { safeDIBuilder(a, d) } else { C(a: a, d: d) }
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return if let safeDIBuilder = safeDIOverrides.a.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			            }
			            let b: B = __safeDI_b()
			            return if let safeDIBuilder = safeDIOverrides.a.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let a: A = __safeDI_a()
			        let d = if let safeDIBuilder = safeDIOverrides.d { safeDIBuilder(a) } else { D(a: a) }
			        return C(a: a, d: d)
			    }
			}
			#endif

			#if DEBUG
			extension C {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            d: ((A) -> D)? = nil,
			            _ safeDIBuilder: ((A, D) -> C)? = nil
			        ) {
			            self.d = d
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var d: ((A) -> D)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((A, D) -> C)?
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			func makeC() -> C {
			    let a = A(b: B(cBuilder: Instantiator<C>(makeC)))
			    return C(a: a, d: D(a: a))
			}

			extension Root {
			    public convenience init() {
			        self.init(cBuilder: Instantiator<C>(makeC))
			    }
			}

			extension C {
			    static func mock() -> C {
			        makeC()
			    }
			}
			""",
		], probes: ["Root()", "C.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesClosingConstantToReceiver_whenMockedTypeIsClosedOnAndReceiverIsBesideClosingConstant() async throws {
		let fixture = Self.receiverBesideCloserFixture(rootDeclaration: "@Instantiated let cBuilder: Instantiator<C>", mockedType: "A")
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            b: B.SafeDIMockConfiguration = .init()
			        ) {
			            self.b = b
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_b() -> B {
			            func __safeDI_cBuilder() -> C {
			                func __safeDI_a() -> A {
			                    let b: B = __safeDI_b()
			                    return A(b: b)
			                }
			                let a: A = __safeDI_a()
			                let d = if let safeDIBuilder = safeDIOverrides.b.cBuilder.d { safeDIBuilder(a) } else { D(a: a) }
			                return if let safeDIBuilder = safeDIOverrides.b.cBuilder.safeDIBuilder { safeDIBuilder(a, d) } else { C(a: a, d: d) }
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = safeDIOverrides.b.safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
			        }
			        let b: B = __safeDI_b()
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: B.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            self.b = b
			            self.safeDIBuilder = safeDIBuilder
			        }

			        private(set) var b: B.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        private(set) var safeDIBuilder: ((B) -> A)?
			    }
			}
			#endif
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			func makeC() -> C {
			    let a = A(b: B(cBuilder: Instantiator<C>(makeC)))
			    return C(a: a, d: D(a: a))
			}

			extension Root {
			    public convenience init() {
			        self.init(cBuilder: Instantiator<C>(makeC))
			    }
			}

			extension A {
			    static func mock() -> A {
			        A(b: B(cBuilder: Instantiator<C>(makeC)))
			    }
			}
			""",
		], probes: ["Root()", "A.mock()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesClosingInstantiatorToReceiver_whenSiblingOfClosingInstantiatorReceivesItsLabel() async throws {
		// Before, the root entering at `aBuilder` rejected `D`'s receive as a cycle while the root entering at `C` accepted it.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("A", "@Instantiated let c: C"),
			Self.type("C", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let d: D"),
			Self.type("D", "@Received let aBuilder: Instantiator<A>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            func __safeDI_c() -> C {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let d = D(aBuilder: aBuilder)
			                return C(aBuilder: aBuilder, d: d)
			            }
			            let c: C = __safeDI_c()
			            return A(c: c)
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
	mutating func generate_passesInstanceOfClosingWrapperToReceiver_whenSiblingOfLazilyInstantiatedCloserReceivesItsInstance() async throws {
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: LazilyInstantiated<A>", "@Instantiated let d: D"),
			Self.type("D", "@Received let a: A"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a = LazilyInstantiated<A>(__safeDI_a)
			                    let d = D(a: a.instance)
			                    return C(a: a, d: d)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesClosingConstantToReceiversOnlyIfAvailable_whenSiblingOfClosingConstantAndTypeItBuildsReceiveItsLabelOnlyIfAvailable() async throws {
		// `D` receives `a` only if available, and so does the `E` it builds: the `a` that `C`, beside `D`, declares to close
		// the cycle is available to both, and `D` makes it available to `E`, though the root's `a` is still being built.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", "@Instantiated let a: A", "@Instantiated let d: D"),
			Self.type("D", "@Received(onlyIfAvailable: true) let a: A?", "@Instantiated let e: E"),
			Self.type("E", "@Received(onlyIfAvailable: true) let a: A?"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            func __safeDI_b() -> B {
			                func __safeDI_cBuilder() -> C {
			                    let a: A = __safeDI_a()
			                    func __safeDI_d() -> D {
			                        let e = E(a: a)
			                        return D(a: a, e: e)
			                    }
			                    let d: D = __safeDI_d()
			                    return C(a: a, d: d)
			                }
			                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			                return B(cBuilder: cBuilder)
			            }
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            A(b: B(cBuilder: Instantiator<C> {
			                let a = a()
			                return C(a: a, d: D(a: a, e: E(a: a)))
			            }))
			        }
			        self.init(a: a())
			    }
			}
			""",
		], probes: ["Root()"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_passesClosingInstantiatorToReceiversOnlyIfAvailable_whenTypeBesideClosingInstantiatorBuildsTypeThatReceivesItsLabelOnlyIfAvailable() async throws {
		// The instantiator twin of the test above, which SafeDI accepted before: `E`, which `D` builds beside `C`'s
		// `aBuilder`, is passed that `aBuilder`, the nearest declaration of its label, rather than `nil` for the root's,
		// which is still being built around it.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("A", "@Instantiated let c: C"),
			Self.type("C", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let d: D"),
			Self.type("D", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?", "@Instantiated let e: E"),
			Self.type("E", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            func __safeDI_c() -> C {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                func __safeDI_d() -> D {
			                    let e = E(aBuilder: aBuilder)
			                    return D(aBuilder: aBuilder, e: e)
			                }
			                let d: D = __safeDI_d()
			                return C(aBuilder: aBuilder, d: d)
			            }
			            let c: C = __safeDI_c()
			            return A(c: c)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		try expectValuesAgree(of: fixture, output: output, knownRight: [
			"Root+SafeDI.swift": """
			extension Root {
			    public convenience init() {
			        func a() -> A {
			            let aBuilder = Instantiator<A>(a)
			            return A(c: C(aBuilder: aBuilder, d: D(aBuilder: aBuilder, e: E(aBuilder: aBuilder))))
			        }
			        self.init(aBuilder: Instantiator<A>(a))
			    }
			}
			""",
		], probes: ["Root()"])
	}

	// MARK: Tests – Generation of deep trees

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstant_whenCycleIsDeeperThanAnyRecursionCouldGo() async throws {
		// The time the compiler takes for nested builder functions grows exponentially with their depth, so the chain of
		// twenty below is compiled instead.
		let root = try await generatedRootOfConstantClosedChain(depth: 200, skipCompileVerification: true)
		// The root's own `f0` and the constant that closes the cycle call the same function.
		#expect(root.components(separatedBy: "let f0: F0 = __safeDI_f0()\n").count == 3)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_closesCycleWithConstantThatCompiles_whenCycleIsTwentyTypesLong() async throws {
		let root = try await generatedRootOfConstantClosedChain(depth: 20, skipCompileVerification: false)
		#expect(root.components(separatedBy: "let f0: F0 = __safeDI_f0()\n").count == 3)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The dependency tree of a root entering the cycle `F0 -> f1Builder: Instantiator<F1> -> F1 -> f2 -> … ->
	/// F<depth - 1> -> f0: F0` at `f0`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generatedRootOfConstantClosedChain(depth: Int, skipCompileVerification: Bool) async throws -> String {
		var fixture = [Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let f0: F0")]
		fixture.append(Self.type("F0", "@Instantiated let f1Builder: Instantiator<F1>"))
		for index in 1..<(depth - 1) {
			fixture.append(Self.type("F\(index)", "@Instantiated let f\(index + 1): F\(index + 1)"))
		}
		fixture.append(Self.type("F\(depth - 1)", "@Instantiated let f0: F0"))
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: skipCompileVerification)
		return try #require(output.generatedFiles?["Root+SafeDI.swift"])
	}

	/// Builds the `A -> B -> Instantiator<C> -> C -> A` family by hand: `makeA()` builds an `A`.
	private static let handBuiltFamily = """
	func makeA() -> A {
	    A(b: B(cBuilder: Instantiator<C> { C(a: makeA()) }))
	}
	"""

	/// The configurations of `C` and `B` in the `A -> B -> Instantiator<C> -> C -> A` family, when `A` is mocked.
	private static let mockConfigurationsOfCAndB = """
	#if DEBUG
	extension C {
	    /// Configuration for how this type is constructed within a mock tree.
	    struct SafeDIMockConfiguration {
	        init(
	            _ safeDIBuilder: ((A) -> C)? = nil
	        ) {
	            self.safeDIBuilder = safeDIBuilder
	        }

	        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
	        private(set) var safeDIBuilder: ((A) -> C)?
	    }
	}

	extension B {
	    /// Configuration for how this type is constructed within a mock tree.
	    struct SafeDIMockConfiguration {
	        init(
	            cBuilder: C.SafeDIMockConfiguration = .init(),
	            _ safeDIBuilder: ((Instantiator<C>) -> B)? = nil
	        ) {
	            self.cBuilder = cBuilder
	            self.safeDIBuilder = safeDIBuilder
	        }

	        private(set) var cBuilder: C.SafeDIMockConfiguration
	        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
	        private(set) var safeDIBuilder: ((Instantiator<C>) -> B)?
	    }
	}
	#endif
	"""

	/// `A.mock()` of the `Sendable` family `A -> B -> SendableInstantiator<C> -> C -> SendableLazilyInstantiated<A>`: the
	/// function `b` builds in is `@Sendable`, since the cycle closes on it from inside `cBuilder`'s, and reads its overrides
	/// into locals declared before it.
	private static let sendableFamilyMockOfA = generatedFileHeader + """
	#if DEBUG
	extension A {
	    /// Overrides for the mock dependency tree.
	    struct SafeDIOverrides {
	        init(
	            b: B.SafeDIMockConfiguration = .init()
	        ) {
	            self.b = b
	        }

	        private(set) var b: B.SafeDIMockConfiguration
	    }

	    static func mock(
	        safeDIOverrides: SafeDIOverrides = .init()
	    ) -> A {
	        let __safeDI_b__b_cBuilder_safeDIBuilder = safeDIOverrides.b.cBuilder.safeDIBuilder
	        let __safeDI_b__safeDIBuilder = safeDIOverrides.b.safeDIBuilder
	        @Sendable func __safeDI_b() -> B {
	            @Sendable func __safeDI_cBuilder() -> C {
	                @Sendable func __safeDI_a() -> A {
	                    let b: B = __safeDI_b()
	                    return A(b: b)
	                }
	                let a = SendableLazilyInstantiated<A>(__safeDI_a)
	                return if let safeDIBuilder = __safeDI_b__b_cBuilder_safeDIBuilder { safeDIBuilder(a) } else { C(a: a) }
	            }
	            let cBuilder = SendableInstantiator<C>(__safeDI_cBuilder)
	            return if let safeDIBuilder = __safeDI_b__safeDIBuilder { safeDIBuilder(cBuilder) } else { B(cBuilder: cBuilder) }
	        }
	        let b: B = __safeDI_b()
	        return A(b: b)
	    }
	}
	#endif

	#if DEBUG
	extension A {
	    /// Configuration for how this type is constructed within a mock tree.
	    struct SafeDIMockConfiguration {
	        init(
	            b: B.SafeDIMockConfiguration = .init(),
	            _ safeDIBuilder: (@Sendable (B) -> A)? = nil
	        ) {
	            self.b = b
	            self.safeDIBuilder = safeDIBuilder
	        }

	        private(set) var b: B.SafeDIMockConfiguration
	        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
	        private(set) var safeDIBuilder: (@Sendable (B) -> A)?
	    }
	}
	#endif
	"""

	/// The configurations of `C` and `B` in a family whose `C` closes the cycle with a `SendableLazilyInstantiated<A>`,
	/// built by an instantiator of `instantiatorType`.
	private static func sendableFamilyMockConfigurations(instantiatorType: String) -> String {
		generatedFileHeader + """
		#if DEBUG
		extension C {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            _ safeDIBuilder: (@Sendable (SendableLazilyInstantiated<A>) -> C)? = nil
		        ) {
		            self.safeDIBuilder = safeDIBuilder
		        }

		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: (@Sendable (SendableLazilyInstantiated<A>) -> C)?
		    }
		}

		extension B {
		    /// Configuration for how this type is constructed within a mock tree.
		    struct SafeDIMockConfiguration {
		        init(
		            cBuilder: C.SafeDIMockConfiguration = .init(),
		            _ safeDIBuilder: (@Sendable (\(instantiatorType)) -> B)? = nil
		        ) {
		            self.cBuilder = cBuilder
		            self.safeDIBuilder = safeDIBuilder
		        }

		        private(set) var cBuilder: C.SafeDIMockConfiguration
		        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
		        private(set) var safeDIBuilder: (@Sendable (\(instantiatorType)) -> B)?
		    }
		}
		#endif
		""" + "\n"
	}

	/// A root whose `flow` is a `LoggedInFlow`, which holds an instantiator of `Settings`, whose own flow is
	/// `settingsFlow`, with `settingsFlowDeclaration`, when given, declared by `SettingsFlow`.
	private static func flowFixture(rootAttributes: String, settingsAttributes: String, loggedInFlowAttributes: String = "", settingsFlow: String, settingsFlowDeclaration: String? = nil) -> [String] {
		[
			type("Root", attributes: rootAttributes, #"@Instantiated(fulfilledByType: "LoggedInFlow") let flow: Flow"#) + "\n\npublic protocol Flow: AnyObject {}",
			type("LoggedInFlow", attributes: loggedInFlowAttributes, "@Instantiated let settingsBuilder: Instantiator<Settings>", conformances: ", Flow"),
			type("Settings", attributes: settingsAttributes, settingsFlow),
			settingsFlowDeclaration.map { Self.type("SettingsFlow", $0, conformances: ", Flow") } ?? type("SettingsFlow", conformances: ", Flow"),
		]
	}

	/// `Root` instantiates `a: A`, whose `bBuilder: Instantiator<B>` builds a `B` that forwards `a: A` and instantiates a
	/// `C` that receives it, with `mockedTypes` generating mocks.
	private static func forwardedNearerDeclarationFixture(mockedTypes: Set<String>) -> [String] {
		let attributes = { (name: String) in mockedTypes.contains(name) ? "(generateMock: true)" : "" }
		return [
			Self.type("Root", attributes: mockedTypes.contains("Root") ? "(isRoot: true, generateMock: true)" : "(isRoot: true)", "@Instantiated let a: A"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", attributes: attributes("B"), "@Forwarded let a: A", "@Instantiated let c: C"),
			Self.type("C", "@Received let a: A"),
		]
	}

	/// What `forwardedNearerDeclarationFixture` builds from `Root()`, written by hand.
	private static let forwardedNearerDeclarationKnownRight = """
	extension Root {
	    public convenience init() {
	        self.init(a: A(bBuilder: Instantiator<B> { a in B(a: a, c: C(a: a)) }))
	    }
	}
	"""

	/// A `B` built by `forwardedNearerDeclarationFixture`'s root's `bBuilder` from the root's own `a`.
	private static let forwardedNearerDeclarationProbe = "{ let a = Root().a; return a.bBuilder.instantiate(a) }()"

	/// What the flow family with `SettingsFlow`'s `flow` built again for `LoggedInFlow` builds from `Root()`, written by hand.
	private static let shadowedClosedOnFlowKnownRight = """
	extension Root {
	    public convenience init() {
	        func makeLoggedInFlow() -> LoggedInFlow {
	            LoggedInFlow(settingsBuilder: Instantiator<Settings> { Settings(flow: SettingsFlow(flow: makeLoggedInFlow())) })
	        }
	        self.init(flow: makeLoggedInFlow())
	    }
	}
	"""

	/// The `A -> B -> Instantiator<C> -> C -> A` family with `C` also instantiating `D`, which receives `a`, entered by
	/// `rootDeclaration`, and with `mockedType` generating a mock.
	private static func receiverBesideCloserFixture(rootDeclaration: String, mockedType: String?) -> [String] {
		let attributes = { (name: String) in name == mockedType ? "(generateMock: true)" : "" }
		return [
			Self.type("Root", attributes: "(isRoot: true)", rootDeclaration),
			Self.type("A", attributes: attributes("A"), "@Instantiated let b: B"),
			Self.type("B", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("C", attributes: attributes("C"), "@Instantiated let a: A", "@Instantiated let d: D"),
			Self.type("D", "@Received let a: A"),
		]
	}

	/// What a root entering the `A -> B -> Instantiator<C> -> C -> A` family at `a` generates.
	private static let rootEnteringFamilyAtConstant = generatedFileHeader + """
	extension Root {
	    public convenience init() {
	        func __safeDI_a() -> A {
	            func __safeDI_b() -> B {
	                func __safeDI_cBuilder() -> C {
	                    let a: A = __safeDI_a()
	                    return C(a: a)
	                }
	                let cBuilder = Instantiator<C>(__safeDI_cBuilder)
	                return B(cBuilder: cBuilder)
	            }
	            let b: B = __safeDI_b()
	            return A(b: b)
	        }
	        let a: A = __safeDI_a()
	        self.init(a: a)
	    }
	}
	"""

	/// What a root entering the `A -> B -> Instantiator<C> -> C -> A` family at `cBuilder` generates, as before cycles
	/// closed by constants were accepted.
	private static let rootEnteringFamilyAtInstantiator = generatedFileHeader + """
	extension Root {
	    public convenience init() {
	        func __safeDI_cBuilder() -> C {
	            func __safeDI_a() -> A {
	                func __safeDI_b() -> B {
	                    let cBuilder = Instantiator<C>(__safeDI_cBuilder)
	                    return B(cBuilder: cBuilder)
	                }
	                let b: B = __safeDI_b()
	                return A(b: b)
	            }
	            let a: A = __safeDI_a()
	            return C(a: a)
	        }
	        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
	        self.init(cBuilder: cBuilder)
	    }
	}
	"""

	/// A public `@Instantiable` final class named `name`, with `attributes` after `@Instantiable` (such as
	/// `(isRoot: true)`), and `declarations`, each stored and taken by its initializer.
	private static func type(_ name: String, attributes: String = "", _ declarations: String..., conformances: String = "") -> String {
		let type = seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: conformances)
		guard !attributes.isEmpty else { return type }
		return "@Instantiable\(attributes)" + type.dropFirst("@Instantiable".count)
	}

	/// `files` named as `executeSafeDIToolTest` names them, after the first type each declares.
	private static func fixtureFiles(_ files: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for file in files {
			let name = file.split(separator: "\n").compactMap { line -> String? in
				guard let classRange = line.range(of: "final class ") else { return nil }
				return String(line[classRange.upperBound...].prefix { $0 != ":" })
			}.first ?? "File"
			fixtureFiles["\(name).swift"] = file
		}
		return fixtureFiles
	}

	/// Compares what `output`'s generated files build for each of `probes` with what `knownRight`, files written by hand
	/// in place of the generated ones, builds.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesAgree(
		of fixture: [String],
		output: TestOutput,
		knownRight: [String: String],
		probes: [String],
		knownRightExpressions: [String: String] = [:],
		sourceLocation: SourceLocation = #_sourceLocation,
	) throws {
		let fixtureFiles = Self.fixtureFiles(fixture)
		try expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: output.generatedFiles ?? [:]),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: knownRight),
			probes: probes.map { DifferentialValueProbe(name: $0, expression: $0, knownRightExpression: knownRightExpressions[$0]) },
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
