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
	mutating func generate_keepsTheTreesLayout_whenTypeBetweenCycleMemberAndCloserDeclaresLabelTheCycleReceives() async throws {
		// `Step`, between `Screen`'s place and the call that closes the cycle on it, declares `session`, which `Screen` receives.
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
		#expect(reports.map(\.refusal) == ["cycleTakesParameters"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenTypeReceivesBuilderInWorldWithCycle() async throws {
		// `Detail` receives `screenBuilder`, which the cycle of `Screen` and `Step` builds.
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
		#expect(reports.map(\.refusal) == ["cycleReceivesBuilder"])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTheTreesLayout_whenBuilderOfAnotherTypeSharesCycleMembersLabel() async throws {
		// `Other`'s `aBuilder` builds `Leaf`, and the root's `aBuilder` builds `A`, on the cycle of `A` and `B`.
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
		#expect(reports.map(\.refusal) == ["cycleBuilderNameShared"])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static func layingOutRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
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
