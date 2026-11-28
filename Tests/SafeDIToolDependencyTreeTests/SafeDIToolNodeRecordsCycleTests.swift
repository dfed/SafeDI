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

struct SafeDIToolNodeRecordsCycleTests: ~Copyable {
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
	mutating func generate_laysOutRootAsTheTreeDoes_whenTwoTypesInstantiateEachOther() async throws {
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCycleForwardsValueAndReceivesOneRootDeclares() async throws {
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let leaf: Leaf
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(leaf: Leaf, aBuilder: Instantiator<A>) { self.leaf = leaf; self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Forwarded let id: Int
					    @Received let leaf: Leaf
					    @Instantiated let bBuilder: Instantiator<B>
					    public init(id: Int, leaf: Leaf, bBuilder: Instantiator<B>) { self.id = id; self.leaf = leaf; self.bBuilder = bBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Received let id: Int
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(id: Int, aBuilder: Instantiator<A>) { self.id = id; self.aBuilder = aBuilder }
					}

					@Instantiable public final class Leaf: Instantiable { public init() {} }
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let leaf = Leaf()
			        func __safeDI_aBuilder(id: Int) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(id: id)
			            }
			            return A(id: id, leaf: leaf, bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder(id: Int) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(id: $0)
			            }
			            return B(id: id, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(id: $0)
			        }
			        self.init(leaf: leaf, aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCycleMemberReceivesValueItsCycleDeclaresAfterTheBuilder() async throws {
		// `A` declares `bBuilder` before `model`, which `B`'s tree receives: `A` builds `model` first.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let model: Model
					    public init(bBuilder: Instantiator<B>, model: Model) { self.bBuilder = bBuilder; self.model = model }
					}

					@Instantiable public final class B: Instantiable {
					    @Received let model: Model
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(model: Model, aBuilder: Instantiator<A>) { self.model = model; self.aBuilder = aBuilder }
					}

					@Instantiable public final class Model: Instantiable { public init() {} }
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let model = Model()
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(model: model)
			            }
			            return A(bBuilder: bBuilder, model: model)
			        }
			        func __safeDI_bBuilder(model: Model) -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(model: model, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCycleClosesThroughConstant() async throws {
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let b: B
					    public init(b: B) { self.b = b }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        func __safeDI_b() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCycleMemberIsBuiltOnTwoBranchesThatCloseOnOnePlace() async throws {
		// `C` is built beneath `A` and beneath `B`, and each place of it closes on `A`'s.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let cBuilder: Instantiator<C>
					    public init(bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) { self.bBuilder = bBuilder; self.cBuilder = cBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let cBuilder: Instantiator<C>
					    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
					}

					@Instantiable public final class C: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return A(bBuilder: bBuilder, cBuilder: cBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return B(cBuilder: cBuilder)
			        }
			        func __safeDI_cBuilder() -> C {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return C(aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenCycleMemberIsBuiltWhereItClosesOnAnotherPlace() async throws {
		// `C` is built beneath `B`, where it closes on `B`'s place, and beneath `A`, where it builds `B` again.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let cBuilder: Instantiator<C>
					    public init(bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) { self.bBuilder = bBuilder; self.cBuilder = cBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let cBuilder: Instantiator<C>
					    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
					}

					@Instantiable public final class C: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(bBuilder: Instantiator<B>, aBuilder: Instantiator<A>) { self.bBuilder = bBuilder; self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return A(bBuilder: bBuilder, cBuilder: cBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return B(cBuilder: cBuilder)
			        }
			        func __safeDI_cBuilder() -> C {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return C(bBuilder: bBuilder, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["cycleMemberBuiltTwoWays"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenTheFactsAnswerTheParametersOfTheFunctionACycleClosesOn() async throws {
		// `Step`, between `Screen`'s place and the call that closes the cycle on it, declares `session`, which `Screen` receives,
		// so `Screen`'s function takes it, as the facts answer.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let session: Session
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(session: Session, screenBuilder: Instantiator<Screen>) { self.session = session; self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Session: Instantiable {
					    public init() {}
					}

					@Instantiable public final class Screen: Instantiable {
					    @Received let session: Session
					    @Instantiated let stepBuilder: Instantiator<Step>
					    public init(session: Session, stepBuilder: Instantiator<Step>) { self.session = session; self.stepBuilder = stepBuilder }
					}

					@Instantiable public final class Step: Instantiable {
					    @Instantiated let session: Session
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(session: Session, screenBuilder: Instantiator<Screen>) { self.session = session; self.screenBuilder = screenBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            return Screen(session: session, stepBuilder: stepBuilder)
			        }
			        func __safeDI_stepBuilder() -> Step {
			            let session = Session()
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(session: session)
			            }
			            return Step(session: session, screenBuilder: screenBuilder)
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(session: session)
			        }
			        self.init(session: session, screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenFunctionBetweenCycleClosingCallAndClosedOnFunctionMakesLoopMemberAgain() async throws {
		// `T1` makes its own `t1Builder` again and closes the cycle on `T3`'s function, which `T0` builds `T1` in: the tree
		// nests each function in the body that builds it, where the engine would declare the three together in `Host`'s.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					seamFixtureType(named: "Root", isRoot: true, isFinalClass: true, declarations: ["@Instantiated let hostBuilder: Instantiator<Host>"]),
					seamFixtureType(named: "Host", isFinalClass: true, declarations: ["@Forwarded let t1Builder: Instantiator<T1>", "@Instantiated let t3Builder: Instantiator<T3>"]),
					seamFixtureType(named: "T3", isFinalClass: true, declarations: ["@Instantiated let t0Builder: Instantiator<T0>", "@Received let t1Builder: Instantiator<T1>"]),
					seamFixtureType(named: "T0", isFinalClass: true, declarations: ["@Instantiated let t1Builder: Instantiator<T1>"]),
					seamFixtureType(named: "T1", isFinalClass: true, declarations: ["@Instantiated let t3Builder: Instantiator<T3>"]),
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_hostBuilder(t1Builder: Instantiator<T1>) -> Host {
			            func __safeDI_t3Builder(t1Builder: Instantiator<T1>) -> T3 {
			                func __safeDI_t0Builder() -> T0 {
			                    func __safeDI_t1Builder() -> T1 {
			                        let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			                        let t3Builder = Instantiator<T3> {
			                            __safeDI_t3Builder(t1Builder: t1Builder)
			                        }
			                        return T1(t3Builder: t3Builder)
			                    }
			                    let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
			                    return T0(t1Builder: t1Builder)
			                }
			                let t0Builder = Instantiator<T0>(__safeDI_t0Builder)
			                return T3(t0Builder: t0Builder, t1Builder: t1Builder)
			            }
			            let t3Builder = Instantiator<T3> {
			                __safeDI_t3Builder(t1Builder: t1Builder)
			            }
			            return Host(t1Builder: t1Builder, t3Builder: t3Builder)
			        }
			        let hostBuilder = Instantiator<Host> {
			            __safeDI_hostBuilder(t1Builder: $0)
			        }
			        self.init(hostBuilder: hostBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["cycleHoldsLoopRebinding"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenTypeReceivesBuilderInWorldWithCycle() async throws {
		// `Detail` receives `screenBuilder`, which the cycle of `Screen` and `Step` builds: `Screen` is a loop of one, which
		// rebinds `screenBuilder` at its top, and the cycle closes on its function. The records refuse a loop member a cycle
		// closes on, which the tree can wrap through a `_received` function, whatever the facts' parameters.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Screen: Instantiable {
					    @Instantiated let stepBuilder: Instantiator<Step>
					    @Instantiated let detail: Detail
					    public init(stepBuilder: Instantiator<Step>, detail: Detail) { self.stepBuilder = stepBuilder; self.detail = detail }
					}

					@Instantiable public final class Detail: Instantiable {
					    @Received let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}

					@Instantiable public final class Step: Instantiable {
					    @Instantiated let screenBuilder: Instantiator<Screen>
					    public init(screenBuilder: Instantiator<Screen>) { self.screenBuilder = screenBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_screenBuilder() -> Screen {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			            func __safeDI_stepBuilder() -> Step {
			                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			                return Step(screenBuilder: screenBuilder)
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = Detail(screenBuilder: screenBuilder)
			            return Screen(stepBuilder: stepBuilder, detail: detail)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder)
			        self.init(screenBuilder: screenBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["builderLoopTakesCycleParameters"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCycleReentersNodeWhoseReceiveAnotherDeclarationAnswers() async throws {
		// `Reader` receives `tag`, which the root declares above `A` and `B` declares on the cycle of `A` and `B`: the call
		// from `B` closes the cycle on `A`'s function, which takes `tag` as a parameter, the facts' parameter of `A`, and
		// is passed the root's `tag` and `B`'s.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let tag: Instantiator<Tag>
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(tag: Instantiator<Tag>, aBuilder: Instantiator<A>) { self.tag = tag; self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let reader: Reader
					    @Instantiated let b: B
					    public init(reader: Reader, b: B) { self.reader = reader; self.b = b }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let tag: Instantiator<Tag>
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(tag: Instantiator<Tag>, aBuilder: Instantiator<A>) { self.tag = tag; self.aBuilder = aBuilder }
					}

					@Instantiable public final class Reader: Instantiable {
					    @Received let tag: Instantiator<Tag>
					    public init(tag: Instantiator<Tag>) { self.tag = tag }
					}

					@Instantiable public final class Tag: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_tag() -> Tag {
			            Tag()
			        }
			        let tag = Instantiator<Tag>(__safeDI_tag)
			        func __safeDI_aBuilder(tag: Instantiator<Tag>) -> A {
			            let reader = Reader(tag: tag)
			            let b: B = __safeDI_b()
			            return A(reader: reader, b: b)
			        }
			        func __safeDI_b() -> B {
			            let tag = Instantiator<Tag>(__safeDI_tag)
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(tag: tag)
			            }
			            return B(tag: tag, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(tag: tag)
			        }
			        self.init(tag: tag, aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == [nil])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
		#expect(reports.flatMap(\.differences) == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenBuilderOfAnotherTypeSharesCycleMembersLabel() async throws {
		// `Other`'s `aBuilder` builds `Leaf`, and the root's `aBuilder` builds `A`, on the cycle of `A` and `B`. No call
		// that closes the cycle is beneath `Other`, so its body keeps the name, and the root's functions are named apart
		// where they are laid out.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    @Instantiated let other: Other
					    public init(aBuilder: Instantiator<A>, other: Other) { self.aBuilder = aBuilder; self.other = other }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class Other: Instantiable {
					    @Instantiated let aBuilder: Instantiator<Leaf>
					    public init(aBuilder: Instantiator<Leaf>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class Leaf: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_aBuilder_() -> Leaf {
			            Leaf()
			        }
			        func __safeDI_other() -> Other {
			            let aBuilder = Instantiator<Leaf>(__safeDI_aBuilder_)
			            return Other(aBuilder: aBuilder)
			        }
			        let other: Other = __safeDI_other()
			        self.init(aBuilder: aBuilder, other: other)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenBodyBetweenCycleMemberAndCloserDeclaresBuilderOfItsName() async throws {
		// `A`'s body declares `aBuilder` for `Leaf` beside `bBuilder`, whose tree closes the cycle on the root's `aBuilder`,
		// so `A`'s body names `Leaf`'s function apart.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let aBuilder: Instantiator<Leaf>
					    public init(bBuilder: Instantiator<B>, aBuilder: Instantiator<Leaf>) {
					        self.bBuilder = bBuilder
					        self.aBuilder = aBuilder
					    }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class Leaf: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let aBuilder = Instantiator<Leaf>(__safeDI_aBuilder_)
			            return A(bBuilder: bBuilder, aBuilder: aBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        func __safeDI_aBuilder_() -> Leaf {
			            Leaf()
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCallClosesCycleOnFunctionItsBodyRenamed() async throws {
		// `A`'s body names `C`'s `aBuilder` apart from the root's, which `bBuilder`'s tree closes on, and `D` closes the
		// cycle of `C` and `D` on `C`'s function by its new name.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let aBuilder: Instantiator<C>
					    public init(bBuilder: Instantiator<B>, aBuilder: Instantiator<C>) {
					        self.bBuilder = bBuilder
					        self.aBuilder = aBuilder
					    }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class C: Instantiable {
					    @Instantiated let dBuilder: Instantiator<D>
					    public init(dBuilder: Instantiator<D>) { self.dBuilder = dBuilder }
					}

					@Instantiable public final class D: Instantiable {
					    @Instantiated let aBuilder: Instantiator<C>
					    public init(aBuilder: Instantiator<C>) { self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let aBuilder = Instantiator<C>(__safeDI_aBuilder_)
			            return A(bBuilder: bBuilder, aBuilder: aBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        func __safeDI_aBuilder_() -> C {
			            let dBuilder = Instantiator<D>(__safeDI_dBuilder)
			            return C(dBuilder: dBuilder)
			        }
			        func __safeDI_dBuilder() -> D {
			            let aBuilder = Instantiator<C>(__safeDI_aBuilder_)
			            return D(aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenCallReachesAnotherVariantOfDeclarationOnThePath() async throws {
		// `Root` declares `x` lazily and `Mid` declares it by value, so `Mid`'s call of `A` reaches another variant of `A`'s
		// declaration than `Root`'s, where today's tree closes the cycle on `Root`'s place of it.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let x: LazilyInstantiated<X>
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(x: LazilyInstantiated<X>, aBuilder: Instantiator<A>) {
					        self.x = x
					        self.aBuilder = aBuilder
					    }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let midBuilder: Instantiator<Mid>
					    @Instantiated let dBuilder: Instantiator<D>
					    public init(midBuilder: Instantiator<Mid>, dBuilder: Instantiator<D>) {
					        self.midBuilder = midBuilder
					        self.dBuilder = dBuilder
					    }
					}

					@Instantiable public final class Mid: Instantiable {
					    @Instantiated let x: X
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(x: X, aBuilder: Instantiator<A>) {
					        self.x = x
					        self.aBuilder = aBuilder
					    }
					}

					@Instantiable public final class D: Instantiable {
					    @Received let x: X
					    public init(x: X) { self.x = x }
					}

					@Instantiable public final class X: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_x() -> X {
			            X()
			        }
			        let x = LazilyInstantiated<X>(__safeDI_x)
			        func __safeDI_aBuilder(x: LazilyInstantiated<X>) -> A {
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(x: x)
			            }
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder() -> Mid {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: LazilyInstantiated<X> { x })
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        func __safeDI_dBuilder(x: LazilyInstantiated<X>) -> D {
			            D(x: x.instance)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(x: x)
			        }
			        self.init(x: x, aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["cycleVariantsPartitionApart"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenSharedPlaceBuildsAnotherVariantOfDeclarationOnThePath() async throws {
		// `Root` builds `Mid` first, whose tree builds the variant of `A` that reads `Mid`'s `x`. `Root`'s `aBuilder` then
		// reaches `Mid`'s shared place beneath its own variant of `A`, where today's tree closes the cycle on that place.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let x: LazilyInstantiated<X>
					    @Instantiated let midBuilder: Instantiator<Mid>
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(x: LazilyInstantiated<X>, midBuilder: Instantiator<Mid>, aBuilder: Instantiator<A>) {
					        self.x = x
					        self.midBuilder = midBuilder
					        self.aBuilder = aBuilder
					    }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let midBuilder: Instantiator<Mid>
					    @Instantiated let dBuilder: Instantiator<D>
					    public init(midBuilder: Instantiator<Mid>, dBuilder: Instantiator<D>) {
					        self.midBuilder = midBuilder
					        self.dBuilder = dBuilder
					    }
					}

					@Instantiable public final class Mid: Instantiable {
					    @Instantiated let x: X
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(x: X, aBuilder: Instantiator<A>) {
					        self.x = x
					        self.aBuilder = aBuilder
					    }
					}

					@Instantiable public final class D: Instantiable {
					    @Received let x: X
					    public init(x: X) { self.x = x }
					}

					@Instantiable public final class X: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_x() -> X {
			            X()
			        }
			        let x = LazilyInstantiated<X>(__safeDI_x)
			        func __safeDI_midBuilder() -> Mid {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(x: x)
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        func __safeDI_aBuilder(x: X) -> A {
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(x: LazilyInstantiated<X> { x })
			            }
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_dBuilder(x: LazilyInstantiated<X>) -> D {
			            D(x: x.instance)
			        }
			        let midBuilder = Instantiator<Mid>(__safeDI_midBuilder)
			        func __safeDI_aBuilder_(x: LazilyInstantiated<X>) -> A {
			            let midBuilder = Instantiator<Mid>(__safeDI_midBuilder_)
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(x: x)
			            }
			            return A(midBuilder: midBuilder, dBuilder: dBuilder)
			        }
			        func __safeDI_midBuilder_() -> Mid {
			            let x = X()
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder_(x: LazilyInstantiated<X> { x })
			            }
			            return Mid(x: x, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder_(x: x)
			        }
			        self.init(x: x, midBuilder: midBuilder, aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["cycleVariantsPartitionApart"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenSharedPlaceBuildsTwinOfPlaceOnThePath() async throws {
		// `Root` builds `Second` first, whose `model` is on the cycle through `secondBuilder`. `First`'s lazy `model`, its
		// twin, then reaches `secondBuilder`'s shared place, where today's tree closes the cycle on the lazy `model`.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let secondBuilder: Instantiator<Second>
					    @Instantiated let firstBuilder: Instantiator<First>
					    public init(secondBuilder: Instantiator<Second>, firstBuilder: Instantiator<First>) {
					        self.secondBuilder = secondBuilder
					        self.firstBuilder = firstBuilder
					    }
					}

					@Instantiable public final class First: Instantiable {
					    @Instantiated let theme: Theme
					    @Instantiated let model: LazilyInstantiated<Model>
					    public init(theme: Theme, model: LazilyInstantiated<Model>) {
					        self.theme = theme
					        self.model = model
					    }
					}

					@Instantiable public final class Second: Instantiable {
					    @Instantiated let theme: Theme
					    @Instantiated let model: Model
					    public init(theme: Theme, model: Model) {
					        self.theme = theme
					        self.model = model
					    }
					}

					@Instantiable public final class Model: Instantiable {
					    @Received let theme: Theme
					    @Instantiated let secondBuilder: Instantiator<Second>
					    public init(theme: Theme, secondBuilder: Instantiator<Second>) {
					        self.theme = theme
					        self.secondBuilder = secondBuilder
					    }
					}

					@Instantiable public final class Theme: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_secondBuilder() -> Second {
			            let theme = Theme()
			            let model: Model = __safeDI_model(theme: theme)
			            return Second(theme: theme, model: model)
			        }
			        func __safeDI_model(theme: Theme) -> Model {
			            let secondBuilder = Instantiator<Second>(__safeDI_secondBuilder)
			            return Model(theme: theme, secondBuilder: secondBuilder)
			        }
			        let secondBuilder = Instantiator<Second>(__safeDI_secondBuilder)
			        func __safeDI_firstBuilder() -> First {
			            let theme = Theme()
			            let model = LazilyInstantiated<Model> {
			                __safeDI_model(theme: theme)
			            }
			            return First(theme: theme, model: model)
			        }
			        let firstBuilder = Instantiator<First>(__safeDI_firstBuilder)
			        self.init(secondBuilder: secondBuilder, firstBuilder: firstBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["cycleVariantsPartitionApart"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenTwoBodiesNameOneVariantsFunctionApart() async throws {
		// `A`'s body names `Leaf`'s `aBuilder` apart from the root's, which `bBuilder`'s tree closes on, and `Other`'s body
		// keeps the name of the same variant's function.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    @Instantiated let other: Other
					    public init(aBuilder: Instantiator<A>, other: Other) {
					        self.aBuilder = aBuilder
					        self.other = other
					    }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    @Instantiated let aBuilder: Instantiator<Leaf>
					    public init(bBuilder: Instantiator<B>, aBuilder: Instantiator<Leaf>) {
					        self.bBuilder = bBuilder
					        self.aBuilder = aBuilder
					    }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class Other: Instantiable {
					    @Instantiated let aBuilder: Instantiator<Leaf>
					    public init(aBuilder: Instantiator<Leaf>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class Leaf: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            let aBuilder = Instantiator<Leaf>(__safeDI_aBuilder_)
			            return A(bBuilder: bBuilder, aBuilder: aBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        func __safeDI_aBuilder_() -> Leaf {
			            Leaf()
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        func __safeDI_other() -> Other {
			            let aBuilder = Instantiator<Leaf>(__safeDI_aBuilder_)
			            return Other(aBuilder: aBuilder)
			        }
			        let other: Other = __safeDI_other()
			        self.init(aBuilder: aBuilder, other: other)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["cycleBuilderNameShared"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCycleClosesInsideSendableFunction() async throws {
		// `B` is built in a `@Sendable` function, from which the call that closes the cycle refers to `A`'s function, which
		// is `@Sendable` too.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: SendableInstantiator<B>
					    public init(bBuilder: SendableInstantiator<B>) { self.bBuilder = bBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        @Sendable nonisolated func __safeDI_aBuilder() -> A {
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        @Sendable nonisolated func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenEveryCallAnswersValueCycleMemberReceivesOnlyIfAvailable() async throws {
		// `B`, on the cycle of `A` and `B`, receives `session` only if available, so its variant keys it as an optional
		// parameter. `Root` declares `session` before the cycle, so every call of `B` answers it: one body, as the tree's.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let session: Session
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(session: Session, aBuilder: Instantiator<A>) { self.session = session; self.aBuilder = aBuilder }
					}

					@Instantiable public final class Session: Instantiable {
					    public init() {}
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Received(onlyIfAvailable: true) let session: Session?
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(session: Session?, aBuilder: Instantiator<A>) { self.session = session; self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let session = Session()
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(session: session, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(session: session, aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenNoCallAnswersValueCycleMemberReceivesOnlyIfAvailable() async throws {
		// `B`, on the cycle of `A` and `B`, receives `session` only if available, so its variant keys it as an optional
		// parameter, and no type declares `session`: every call of `B` passes `nil`.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					}

					@Instantiable public final class Session: Instantiable {
					    public init() {}
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					}

					@Instantiable public final class B: Instantiable {
					    @Received(onlyIfAvailable: true) let session: Session?
					    @Instantiated let aBuilder: Instantiator<A>
					    public init(session: Session?, aBuilder: Instantiator<A>) { self.session = session; self.aBuilder = aBuilder }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return A(bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return B(session: nil, aBuilder: aBuilder)
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			        self.init(aBuilder: aBuilder)
			    }
			}
			""",
		])
		#expect(reports.map(\.refusal) == ["cycleVariantsPartitionApart"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysOutRootAsTheTreeDoes_whenCycleClosesThroughErasedInstantiator() async throws {
		// `A` is built at the root and again inside `C`, which `B` builds through an erased instantiator. Both calls of `A`
		// read its label from a scope that declares it as a plain constant: that `C` is built erased changes nothing `A`
		// reads, so one variant serves both.
		let (output, reports) = try await Self.layingOutRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true) public final class Root: Instantiable {
					    @Instantiated let a: A
					    public init(a: A) { self.a = a }
					}

					@Instantiable public final class A: Instantiable {
					    @Instantiated let b: B
					    public init(b: B) { self.b = b }
					}

					@Instantiable public final class B: Instantiable {
					    @Instantiated(fulfilledByType: "C", erasedToConcreteExistential: true) let cBuilder: ErasedInstantiator<(), AnyC>
					    public init(cBuilder: ErasedInstantiator<(), AnyC>) { self.cBuilder = cBuilder }
					}

					@Instantiable(fulfillingAdditionalTypes: [CProtocol.self]) public final class C: Instantiable, CProtocol {
					    @Instantiated let a: A
					    public init(a: A) { self.a = a }
					}

					public protocol CProtocol {}

					public struct AnyC: CProtocol {
					    public init(_ c: any CProtocol) {
					        self.c = c
					    }

					    public let c: any CProtocol
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_a() -> A {
			            let b: B = __safeDI_b()
			            return A(b: b)
			        }
			        func __safeDI_b() -> B {
			            let cBuilder = ErasedInstantiator<(), AnyC> {
			                AnyC(__safeDI_cBuilder())
			            }
			            return B(cBuilder: cBuilder)
			        }
			        func __safeDI_cBuilder() -> C {
			            let a: A = __safeDI_a()
			            return C(a: a)
			        }
			        let a: A = __safeDI_a()
			        self.init(a: a)
			    }
			}
			""",
		])
		#expect(reports.map(\.isLaidOutFromNodeRecords) == [true])
	}

	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports)
	}
}
