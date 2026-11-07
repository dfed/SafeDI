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

#if canImport(Darwin)
	import Darwin
#elseif canImport(Glibc)
	import Glibc
#elseif canImport(Musl)
	import Musl
#endif
import Foundation
import Testing
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// The differential value comparator judges two paths that build one graph by the values they build, not only by
/// whether both compile. Each rejection test hands it a path whose code compiles but builds a wrong value, which an
/// acceptance-only differential passes; the acceptance tests hand it paths whose code differs while their values
/// agree.
struct DifferentialValueComparatorTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Rejections

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsNilAgainstValue_whenFeaturePathPassesNilWhereKnownRightPathPassesTheSharedInstance() throws {
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: ["e: a": "e: nil"]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "e"], feature: "e: nil", knownRight: "e: <2> A (seen, first at <1> Root > a)"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsSecondInstanceAgainstSharedOne_whenFeaturePathCreatesAnInstanceTheKnownRightPathShares() throws {
		// The feature path's extra instance numbers everything after it one higher, which is no difference.
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: ["b: B(a: a, c: C())": "b: B(a: A(), c: C())"]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "b", "a"], feature: "a: <4> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsDifferentDefaultValue_whenFeaturePathPassesAnotherValueForTheStoredDefault() throws {
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: ["title: \"default\"": "title: \"other\""]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "title"], feature: "title: String \"other\"", knownRight: "title: String \"default\""),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsDifferenceBeneathEachCallOfAnInstantiator_whenTheInstancesAnInstantiatorBuildsReceiveAnotherValue() throws {
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: ["bBuilder: Instantiator { B(a: a, c: C()) }": "bBuilder: Instantiator { B(a: A(), c: C()) }"]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "bBuilder", "instantiate()", "a"], feature: "a: <7> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "bBuilder", "instantiate() again", "a"], feature: "a: <10> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsOneInstanceFromEveryCall_whenFeaturePathsInstantiatorReturnsAnInstanceItBuiltOnce() throws {
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: [
			"let a = A()": "let a = A()\n        let builtOnce = B(a: a, c: C())",
			"bBuilder: Instantiator { B(a: a, c: C()) }": "bBuilder: Instantiator { builtOnce }",
		]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "bBuilder", "instantiate() again"], feature: "instantiate() again: <6> B (seen, first at <1> Root > bBuilder > instantiate())", knownRight: "instantiate() again: <8> B"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsADependencyHoistedOutOfAnInstantiator_whenFeaturePathsInstantiatorCapturesAnInstanceItShouldBuildOnEachCall() throws {
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: [
			"let a = A()": "let a = A()\n        let hoistedC = C()",
			"bBuilder: Instantiator { B(a: a, c: C()) }": "bBuilder: Instantiator { B(a: a, c: hoistedC) }",
		]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "bBuilder", "instantiate() again", "c"], feature: "c: <7> C (seen, first at <1> Root > bBuilder > instantiate() > c)", knownRight: "c: <9> C"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsDifferenceBeneathLazilyInstantiated_whenTheInstanceReadLastReceivesAnotherValue() throws {
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: ["lazyB: LazilyInstantiated { B(a: a, c: C()) }": "lazyB: LazilyInstantiated { B(a: A(), c: C()) }"]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<10>.instance", "a"], feature: "a: <12> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsAnInstanceReadBeforeTheProbeIsDescribed_whenFeaturePathReadsItsLazilyInstantiatedWrapperDuringConstruction() throws {
		// The instance read during construction is the one read last, and the two paths' instances agree: only the
		// wrapper's state tells an eager read from a lazy one.
		#expect(try Self.differences(betweenKnownRightGraphAnd: Self.graphGeneratedCode(replacing: [
			"let a = A()": "let a = A()\n        let lazyB = LazilyInstantiated { B(a: a, c: C()) }\n        _ = lazyB.instance",
			"lazyB: LazilyInstantiated { B(a: a, c: C()) }": "lazyB: lazyB",
		]), filesToDelete: &filesToDelete) == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "lazyB"], feature: "lazyB: <10> LazilyInstantiated<B> (already instantiated, instance read last)", knownRight: "lazyB: <10> LazilyInstantiated<B> (instance read last)"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsOneDifferenceAnExemptionAccepts_whenFeaturePathsLazilyInstantiatedClosureCapturesAnInstanceBuiltBeforeIt() throws {
		let comparison = try DifferentialValueOracle.compare(
			feature: Self.stampedPath(initializerBody: "let made = B(a: a)\n        self.init(a: a, lazyB: LazilyInstantiated { made })"),
			knownRight: Self.stampedPath(initializerBody: "self.init(a: a, lazyB: LazilyInstantiated { B(a: a) })"),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)

		// The wrapper was never read before the probe, and the instances agree: only the instance's stamp tells that
		// the feature path built it up front.
		let difference = DifferentialValueDifference(probe: "Root()", path: ["<3>.instance"], feature: "<3>.instance: <4> B (built before the probe's value)", knownRight: "<3>.instance: <4> B")
		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences == [difference])
		#expect(comparisonMade.differences(exempting: [difference]).isEmpty)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_comparesWhatAnInstanceHolds_whenItsOnlyDifferenceIsBeingBuiltBeforeTheProbesValue() throws {
		let comparison = try DifferentialValueOracle.compare(
			feature: Self.stampedPath(initializerBody: "let made = B(a: A())\n        self.init(a: a, lazyB: LazilyInstantiated { made })"),
			knownRight: Self.stampedPath(initializerBody: "self.init(a: a, lazyB: LazilyInstantiated { B(a: a) })"),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(probe: "Root()", path: ["<3>.instance"], feature: "<3>.instance: <4> B (built before the probe's value)", knownRight: "<3>.instance: <4> B"),
			DifferentialValueDifference(probe: "Root()", path: ["<3>.instance", "a"], feature: "a: <5> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_comparesTheInstanceAndEveryLaterReference_whenALazilyInstantiatedWrapperDiffersOnlyByItsState() throws {
		let fixture = """
		public final class A {
		    public init() {}
		}
		public final class B {
		    public init(a: A) {
		        self.a = a
		    }
		    public let a: A
		}
		public final class Root {
		    public init(a: A, lazyB: LazilyInstantiated<B>, lazyBAgain: LazilyInstantiated<B>) {
		        self.a = a
		        self.lazyB = lazyB
		        self.lazyBAgain = lazyBAgain
		    }
		    public let a: A
		    public let lazyB: LazilyInstantiated<B>
		    public let lazyBAgain: LazilyInstantiated<B>
		}
		"""
		func path(initializerBody: String) -> DifferentialValuePath {
			DifferentialValuePath(fixtureFiles: ["Root.swift": fixture], generatedFiles: ["Root+Make.swift": "extension Root {\n    convenience init() {\n        let a = A()\n        \(initializerBody)\n        self.init(a: a, lazyB: lazyB, lazyBAgain: lazyB)\n    }\n}\n"])
		}

		let comparison = try DifferentialValueOracle.compare(
			feature: path(initializerBody: "let lazyB = LazilyInstantiated { B(a: A()) }\n        _ = lazyB.instance"),
			knownRight: path(initializerBody: "let lazyB = LazilyInstantiated { B(a: a) }"),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)

		// The wrappers pair, so the second reference to the feature path's wrapper agrees, and the instance read last is
		// compared: an exemption of the wrapper's line accepts the early read alone.
		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "lazyB"], feature: "lazyB: <3> LazilyInstantiated<B> (already instantiated, instance read last)", knownRight: "lazyB: <3> LazilyInstantiated<B> (instance read last)"),
			DifferentialValueDifference(probe: "Root()", path: ["<3>.instance", "a"], feature: "a: <5> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsOneDifference_whenAnInstantiatorTheProbeCallsReadsTheInstanceAClosureCapturedBeforeItsWrapper() throws {
		// The probe's own call of `cBuilder` reads the instance, as the builder SafeDI generates for a type that
		// receives it by value does, before the wrapper is met and before its instance is read last.
		func path(initializerBody: String) -> DifferentialValuePath {
			DifferentialValuePath(
				fixtureFiles: ["Root.swift": Self.lazyInstanceReadByBuilderFixture],
				generatedFiles: ["Root+Make.swift": "extension RootBuilderFirst {\n    convenience init() {\n        \(initializerBody)\n        self.init(cBuilder: Instantiator { C(x: lazyX.instance) }, lazyX: lazyX)\n    }\n}\n"],
			)
		}

		let comparison = try DifferentialValueOracle.compare(
			feature: path(initializerBody: "let made = X()\n        let lazyX = LazilyInstantiated { made }"),
			knownRight: path(initializerBody: "let lazyX = LazilyInstantiated { X() }"),
			probes: [DifferentialValueProbe("RootBuilderFirst()")],
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(
				probe: "RootBuilderFirst()",
				path: ["<6>.instance"],
				feature: "<6>.instance: <4> X (built before the probe's value) (seen, first at <1> RootBuilderFirst > cBuilder > instantiate() > x)",
				knownRight: "<6>.instance: <4> X (seen, first at <1> RootBuilderFirst > cBuilder > instantiate() > x)",
			),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsMissingTraversal_whenFeaturePathStoresAWrapperTheComparatorDoesNotTraverseWhereKnownRightPathStoresOneItDoes() throws {
		let comparison = try DifferentialValueOracle.compare(
			feature: DifferentialValuePath(
				fixtureFiles: ["Graph.swift": Self.graphFixture.replacingOccurrences(of: "Instantiator<B>", with: "ErasedInstantiator<(), B>")],
				generatedFiles: ["Root+SafeDI.swift": Self.graphGeneratedCode(replacing: ["bBuilder: Instantiator { B(a: a, c: C()) }": "bBuilder: ErasedInstantiator { B(a: a, c: C()) }"])],
			),
			knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)

		// The feature path numbers five fewer instances after `bBuilder`, which is no difference.
		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "bBuilder"], feature: "bBuilder: <5> ErasedInstantiator<(), B> (not traversed)", knownRight: "bBuilder: <5> Instantiator<B>"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsWhatACycleClosingBuilderBuilds_whenFeaturePathsCycleClosingBuilderBuildsAnotherValue() throws {
		let fixture = """
		public final class Root {
		    public init(a: A, t1: T1) {
		        self.a = a
		        self.t1 = t1
		    }
		    public let a: A
		    public let t1: T1
		}
		public final class A {
		    public init() {}
		}
		public final class T1: Instantiable {
		    public init(a: A, t2Builder: Instantiator<T2>) {
		        self.a = a
		        self.t2Builder = t2Builder
		    }
		    public let a: A
		    public let t2Builder: Instantiator<T2>
		}
		public final class T2: Instantiable {
		    public init(a: A, t1Builder: Instantiator<T1>) {
		        self.a = a
		        self.t1Builder = t1Builder
		    }
		    public let a: A
		    public let t1Builder: Instantiator<T1>
		}
		"""
		// The shape SafeDI generates: the builder that closes the cycle refers to the enclosing builder function.
		let knownRightGenerated = """
		extension Root {
		    convenience init() {
		        let a = A()
		        func __safeDI_t1() -> T1 {
		            func __safeDI_t2Builder() -> T2 {
		                func __safeDI_t1Builder() -> T1 {
		                    let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		                    return T1(a: a, t2Builder: t2Builder)
		                }
		                let t1Builder = Instantiator<T1>(__safeDI_t1Builder)
		                return T2(a: a, t1Builder: t1Builder)
		            }
		            let t2Builder = Instantiator<T2>(__safeDI_t2Builder)
		            return T1(a: a, t2Builder: t2Builder)
		        }
		        self.init(a: a, t1: __safeDI_t1())
		    }
		}
		"""
		let featureGenerated = knownRightGenerated.replacingOccurrences(
			of: "let t2Builder = Instantiator<T2>(__safeDI_t2Builder)\n                    return",
			with: "let t2Builder = Instantiator<T2> { T2(a: A(), t1Builder: Instantiator<T1>(__safeDI_t1Builder)) }\n                    return",
		)

		let comparison = try DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: ["Graph.swift": fixture], generatedFiles: ["Root+SafeDI.swift": featureGenerated]),
			knownRight: DifferentialValuePath(fixtureFiles: ["Graph.swift": fixture], generatedFiles: ["Root+SafeDI.swift": knownRightGenerated]),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)

		// The cycle is unrolled once, so the builder each `T1` that `t1Builder` builds holds, the one that closes the
		// cycle, is called: where it is called, the `T2` it builds holds another `A`.
		let knownRightA = "a: <2> A (seen, first at <1> Root > a)"
		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "t1", "t2Builder", "instantiate()", "t1Builder", "instantiate()", "t2Builder", "instantiate()", "a"], feature: "a: <10> A", knownRight: knownRightA),
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "t1", "t2Builder", "instantiate()", "t1Builder", "instantiate()", "t2Builder", "instantiate() again", "a"], feature: "a: <17> A", knownRight: knownRightA),
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "t1", "t2Builder", "instantiate()", "t1Builder", "instantiate() again", "t2Builder", "instantiate()", "a"], feature: "a: <24> A", knownRight: knownRightA),
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "t1", "t2Builder", "instantiate() again", "t1Builder", "instantiate()", "t2Builder", "instantiate()", "a"], feature: "a: <33> A", knownRight: knownRightA),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsAnotherDynamicType_whenAnExistentialHoldsAValueOfAnotherTypeThatReflectsAlike() throws {
		let fixture = """
		public final class Holder {
		    public init(number: Any, text: any StringProtocol) {
		        self.number = number
		        self.text = text
		    }
		    public let number: Any
		    public let text: any StringProtocol
		}
		"""

		let comparison = try DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: ["Holder.swift": fixture], generatedFiles: ["Holder+Make.swift": "extension Holder {\n    static func make() -> Holder {\n        Holder(number: Int32(1), text: Substring(\"x\"))\n    }\n}\n"]),
			knownRight: DifferentialValuePath(fixtureFiles: ["Holder.swift": fixture], generatedFiles: ["Holder+Make.swift": "extension Holder {\n    static func make() -> Holder {\n        Holder(number: 1, text: \"x\")\n    }\n}\n"]),
			probes: [DifferentialValueProbe("Holder.make()")],
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(probe: "Holder.make()", path: ["<1> Holder", "number"], feature: "number: Int32 1", knownRight: "number: Int 1"),
			DifferentialValueDifference(probe: "Holder.make()", path: ["<1> Holder", "text"], feature: "text: Substring \"x\"", knownRight: "text: String \"x\""),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsEachElementOnlyOnePathHolds_whenCollectionsDifferInLength() throws {
		let fixture = """
		public final class Holder {
		    public init(more: [Int], fewer: [Int]) {
		        self.more = more
		        self.fewer = fewer
		    }
		    public let more: [Int]
		    public let fewer: [Int]
		}
		"""

		let comparison = try DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: ["Holder.swift": fixture], generatedFiles: ["Holder+Make.swift": "extension Holder {\n    static func make() -> Holder {\n        Holder(more: [1, 2], fewer: [1])\n    }\n}\n"]),
			knownRight: DifferentialValuePath(fixtureFiles: ["Holder.swift": fixture], generatedFiles: ["Holder+Make.swift": "extension Holder {\n    static func make() -> Holder {\n        Holder(more: [1], fewer: [1, 2])\n    }\n}\n"]),
			probes: [DifferentialValueProbe("Holder.make()")],
			filesToDelete: &filesToDelete,
		)

		let differences = try #require(comparison).differences
		#expect(differences == [
			DifferentialValueDifference(probe: "Holder.make()", path: ["<1> Holder", "more", "1"], feature: "1: Int 2", knownRight: "(absent)"),
			DifferentialValueDifference(probe: "Holder.make()", path: ["<1> Holder", "fewer", "1"], feature: "(absent)", knownRight: "1: Int 2"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_comparesSetsAndDictionariesOfClassInstancesByKindAndCountOnly_whenTheyHoldInstances() throws {
		let fixture = """
		public final class Node: Hashable {
		    public init(value: Int) {
		        self.value = value
		    }
		    public let value: Int
		    public static func == (lhs: Node, rhs: Node) -> Bool {
		        lhs === rhs
		    }
		    public func hash(into hasher: inout Hasher) {
		        hasher.combine(ObjectIdentifier(self))
		    }
		}
		public final class Holder {
		    public init(nodes: Set<Node>, nodesByName: [String: Node], values: Set<Int>) {
		        self.nodes = nodes
		        self.nodesByName = nodesByName
		        self.values = values
		    }
		    public let nodes: Set<Node>
		    public let nodesByName: [String: Node]
		    public let values: Set<Int>
		}
		"""
		func path(_ arguments: String) -> DifferentialValuePath {
			DifferentialValuePath(fixtureFiles: ["Holder.swift": fixture], generatedFiles: ["Holder+Make.swift": "extension Holder {\n    static func make() -> Holder {\n        Holder(\(arguments))\n    }\n}\n"])
		}

		let comparison = try DifferentialValueOracle.compare(
			feature: path("nodes: [Node(value: 1), Node(value: 2)], nodesByName: [\"a\": Node(value: 1)], values: [1, 2]"),
			knownRight: path("nodes: [Node(value: 1), Node(value: 3)], nodesByName: [\"a\": Node(value: 1), \"b\": Node(value: 2)], values: [1, 3]"),
			probes: [DifferentialValueProbe("Holder.make()")],
			filesToDelete: &filesToDelete,
		)

		// Sets of two instances agree whatever the instances hold, a stated limit; a dictionary of another count differs,
		// and so does a set of values.
		let differences = try #require(comparison).differences
		#expect(differences == [
			DifferentialValueDifference(probe: "Holder.make()", path: ["<1> Holder", "nodesByName"], feature: "nodesByName: Dictionary<String, Node> (not compared: dictionary of 1 class instances)", knownRight: "nodesByName: Dictionary<String, Node> (not compared: dictionary of 2 class instances)"),
			DifferentialValueDifference(probe: "Holder.make()", path: ["<1> Holder", "values", "1"], feature: "1: Int 2", knownRight: "1: Int 3"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_rejectsDifferentDefaultValue_whenASuperclassStoresTheDefault() throws {
		let fixture = """
		open class Base {
		    public init(title: String) {
		        self.title = title
		    }
		    public let title: String
		}
		public final class Child: Base {
		    public init(a: A, title: String = "default") {
		        self.a = a
		        super.init(title: title)
		    }
		    public let a: A
		}
		public final class A {
		    public init() {}
		}
		"""

		let comparison = try DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: ["Child.swift": fixture], generatedFiles: ["Child+Make.swift": "extension Child {\n    static func make() -> Child {\n        Child(a: A(), title: \"other\")\n    }\n}\n"]),
			knownRight: DifferentialValuePath(fixtureFiles: ["Child.swift": fixture], generatedFiles: ["Child+Make.swift": "extension Child {\n    static func make() -> Child {\n        Child(a: A())\n    }\n}\n"]),
			probes: [DifferentialValueProbe("Child.make()")],
			filesToDelete: &filesToDelete,
		)

		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences == [
			DifferentialValueDifference(probe: "Child.make()", path: ["<1> Child", "title"], feature: "title: String \"other\"", knownRight: "title: String \"default\""),
		])
		// A superclass's stored properties come first.
		#expect(comparisonMade.knownRightDescription == """
		probe Child.make()
		<1> Child
		  title: String "default"
		  a: <2> A

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsEveryDifferenceOfEachProbe_whenSeveralProbesDifferInSeveralPlaces() throws {
		let comparison = try DifferentialValueOracle.compare(
			feature: Self.graphPath(generated: Self.graphGeneratedCode(replacing: [
				"e: a": "e: nil",
				"title: \"default\"": "title: \"other\"",
				"bBuilder: Instantiator { B(a: a, c: C()) }": "bBuilder: Instantiator { B(a: A(), c: C()) }",
				"lazyB: LazilyInstantiated { B(a: a, c: C()) }": "lazyB: nil",
			])),
			knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe(name: "second root", expression: "Root()"), DifferentialValueProbe("A()")],
			filesToDelete: &filesToDelete,
		)

		// Each probe is numbered afresh, so the second root's differences read as the first's. The known-right path's
		// `lazyB` instance has no counterpart, so it is part of the difference at `lazyB`.
		let differencesOfARoot = { (probe: String) in
			[
				DifferentialValueDifference(probe: probe, path: ["<1> Root", "e"], feature: "e: nil", knownRight: "e: <2> A (seen, first at <1> Root > a)"),
				DifferentialValueDifference(probe: probe, path: ["<1> Root", "title"], feature: "title: String \"other\"", knownRight: "title: String \"default\""),
				DifferentialValueDifference(probe: probe, path: ["<1> Root", "bBuilder", "instantiate()", "a"], feature: "a: <7> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
				DifferentialValueDifference(probe: probe, path: ["<1> Root", "bBuilder", "instantiate() again", "a"], feature: "a: <10> A", knownRight: "a: <2> A (seen, first at <1> Root > a)"),
				DifferentialValueDifference(probe: probe, path: ["<1> Root", "lazyB"], feature: "lazyB: nil", knownRight: "lazyB: <10> LazilyInstantiated<B> (instance read last)"),
			]
		}
		let differences = try #require(comparison).differences
		#expect(differences == differencesOfARoot("Root()") + differencesOfARoot("second root"))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsOnlyTheProbeThatDiffers_whenAnEarlierProbeBuildsAnExtraInstance() throws {
		let comparison = try DifferentialValueOracle.compare(
			feature: Self.graphPath(generated: Self.graphGeneratedCode(replacing: ["b: B(a: a, c: C())": "b: B(a: A(), c: C())"])),
			knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("B(a: A(), c: C())")],
			filesToDelete: &filesToDelete,
		)

		let difference = DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "b", "a"], feature: "a: <4> A", knownRight: "a: <2> A (seen, first at <1> Root > a)")
		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences == [difference])
		#expect(comparisonMade.differences(exempting: [difference]).isEmpty)
	}

	// MARK: Acceptances

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_acceptsAPathWrittenDifferently_whenItBuildsTheSameValues() throws {
		// Builder functions declared in another order, the shared instance bound through other names, an instance
		// built in a closure called at once, a default spelled another way, and the lazily built instance's wrapper
		// declared first. Reading the instance early is a difference: the wrapper's line shows it.
		let featureGenerated = """
		extension Root {
		    convenience init() {
		        let shared = A()
		        let a = shared
		        func __safeDI_bBuilder() -> B {
		            let c = C()
		            return B(a: a, c: c)
		        }
		        let lazyB = LazilyInstantiated<B> { B(a: shared, c: C()) }
		        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
		        let b: B = { B(a: a, c: C()) }()
		        self.init(a: a, b: b, e: shared, title: "def" + "ault", bBuilder: bBuilder, lazyB: lazyB)
		    }
		}
		"""

		let comparison = try DifferentialValueOracle.compare(
			feature: Self.graphPath(generated: featureGenerated),
			knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)

		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences.isEmpty, "\(comparisonMade.report)")
		#expect(comparisonMade.featureDescription == """
		probe Root()
		<1> Root
		  a: <2> A
		  b: <3> B
		    a: <2> A (seen)
		    c: <4> C
		  e: <2> A (seen)
		  title: String "default"
		  bBuilder: <5> Instantiator<B>
		    instantiate(): <6> B
		      a: <2> A (seen)
		      c: <7> C
		    instantiate() again: <8> B
		      a: <2> A (seen)
		      c: <9> C
		  lazyB: <10> LazilyInstantiated<B> (instance read last)
		<10>.instance: <11> B
		  a: <2> A (seen)
		  c: <12> C

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_acceptsEqualGraphs_whenTheirDeclarationsAreInDifferentOrdersAndTheirCodeIsGenerated() async throws {
		let root = """
		@Instantiable(isRoot: true)
		public final class Root: Instantiable {
		    public init(a: A, b: B, lazyC: LazilyInstantiated<C>, dBuilder: Instantiator<D>, title: String = "default") {
		        self.a = a
		        self.b = b
		        self.lazyC = lazyC
		        self.dBuilder = dBuilder
		        self.title = title
		    }

		    @Instantiated let a: A
		    @Instantiated let b: B
		    @Instantiated let lazyC: LazilyInstantiated<C>
		    @Instantiated let dBuilder: Instantiator<D>
		    let title: String
		}
		"""
		let a = """
		@Instantiable
		public final class A: Instantiable {
		    public init() {}
		}
		"""
		let b = """
		@Instantiable(generateMock: true)
		public final class B: Instantiable {
		    public init(a: A, renamedA: A?) {
		        self.a = a
		        self.renamedA = renamedA
		    }

		    @Received let a: A
		    @Received(fulfilledByDependencyNamed: "a", ofType: A.self, onlyIfAvailable: true) let renamedA: A?
		}
		"""
		let c = """
		@Instantiable
		public final class C: Instantiable {
		    public init(a: A) {
		        self.a = a
		    }

		    @Received let a: A
		}
		"""
		let d = """
		@Instantiable
		public final class D: Instantiable {
		    public init(a: A, c: C) {
		        self.a = a
		        self.c = c
		    }

		    @Received let a: A
		    @Instantiated let c: C
		}
		"""
		let knownRightFixtureFiles = ["1_Root.swift": root, "2_A.swift": a, "3_B.swift": b, "4_C.swift": c, "5_D.swift": d]
		// The same types in reverse file order, with two of them declared in one file in reverse order.
		let featureFixtureFiles = ["1_DC.swift": d + "\n" + c, "2_B.swift": b, "3_A.swift": a, "4_Root.swift": root]
		let knownRightOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: knownRightFixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
		let featureOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: featureFixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete, skipCompileVerification: true)
		let probes = [DifferentialValueProbe("Root()"), DifferentialValueProbe("B.mock()")]

		let comparison = try DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: featureFixtureFiles, generatedFiles: try #require(featureOutput.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: knownRightFixtureFiles, generatedFiles: try #require(knownRightOutput.generatedFiles)),
			probes: probes,
			filesToDelete: &filesToDelete,
		)

		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences.isEmpty, "\(comparisonMade.report)")
		#expect(comparisonMade.knownRightDescription == """
		probe Root()
		<1> Root
		  a: <2> A
		  b: <3> B
		    a: <2> A (seen)
		    renamedA: <2> A (seen)
		  lazyC: <4> LazilyInstantiated<C> (instance read last)
		  dBuilder: <5> Instantiator<D>
		    instantiate(): <6> D
		      a: <2> A (seen)
		      c: <7> C
		        a: <2> A (seen)
		    instantiate() again: <8> D
		      a: <2> A (seen)
		      c: <9> C
		        a: <2> A (seen)
		  title: String "default"
		<4>.instance: <10> C
		  a: <2> A (seen)
		probe B.mock()
		<1> B
		  a: <2> A
		  renamedA: <2> A (seen)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_acceptsAGraphSplitAcrossModules_whenAModuleIsNamedLikeATypeItDeclaresANestedTypeIn() throws {
		let feature = """
		public final class Feature {
		    public init() {}
		    public struct Settings {
		        public init() {}
		        public let isEnabled = true
		    }
		}
		"""
		let root = """
		public final class Root {
		    public init() {}
		    public let feature = Feature()
		    public let settings = Feature.Settings()
		}
		"""
		let splitPath = DifferentialValuePath(modules: [
			DifferentialValueModule(name: "Feature", fixtureFiles: ["Feature.swift": feature]),
			DifferentialValueModule(name: "App", dependencyModuleNames: ["Feature"], fixtureFiles: ["Root.swift": "import Feature\n" + root]),
		])
		let singlePath = DifferentialValuePath(modules: [
			DifferentialValueModule(name: "App", fixtureFiles: ["Feature.swift": feature, "Root.swift": root]),
		])

		let comparison = try DifferentialValueOracle.compare(feature: splitPath, knownRight: singlePath, probes: [DifferentialValueProbe("Root()")], filesToDelete: &filesToDelete)

		// Only the leading `Feature.` names the module: `Feature.Feature.Settings` is `Feature.Settings`, as
		// `App.Feature.Settings` is.
		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences.isEmpty, "\(comparisonMade.report)")
		#expect(comparisonMade.featureDescription == """
		probe Root()
		<1> Root
		  feature: <2> Feature
		  settings: Feature.Settings
		    isEnabled: Bool true

		""")
	}

	// MARK: Exemptions

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func differences_removeExactlyTheDifferencesEqualToAnExemption_whenAProbeDiffersInSeveralPlaces() throws {
		let comparison = try DifferentialValueOracle.compare(
			feature: Self.graphPath(generated: Self.graphGeneratedCode(replacing: ["e: a": "e: nil", "title: \"default\"": "title: \"other\""])),
			knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)
		let nilDifference = DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "e"], feature: "e: nil", knownRight: "e: <2> A (seen, first at <1> Root > a)")
		let defaultDifference = DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "title"], feature: "title: String \"other\"", knownRight: "title: String \"default\"")

		let comparisonMade = try #require(comparison)
		// The difference after an exempted one is still compared and reported.
		#expect(comparisonMade.differences(exempting: [nilDifference]) == [defaultDifference])
		#expect(comparisonMade.differences(exempting: [defaultDifference]) == [nilDifference])
		#expect(comparisonMade.differences(exempting: [nilDifference, defaultDifference]).isEmpty)
		// An exemption is matched by its content, never by text that appears in the difference's message: one that names
		// an enclosing path, another probe, or only part of a line exempts nothing.
		#expect(comparisonMade.differences(exempting: [DifferentialValueDifference(probe: "Root()", path: ["<1> Root"], feature: "e: nil", knownRight: nilDifference.knownRight)]) == [nilDifference, defaultDifference])
		#expect(comparisonMade.differences(exempting: [DifferentialValueDifference(probe: "Root", path: ["<1> Root", "e"], feature: "e: nil", knownRight: nilDifference.knownRight)]) == [nilDifference, defaultDifference])
		#expect(comparisonMade.differences(exempting: [DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "e"], feature: "nil", knownRight: "<2> A (seen)")]) == [nilDifference, defaultDifference])
	}

	// MARK: Description

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_showsEachStoredPropertyByItsSpelling_whenAFixtureStoresEveryKindOfValue() throws {
		let fixture = """
		public protocol Shape {}
		public final class Plain: Shape {
		    public init() {}
		}
		public enum Outer {
		    public final class Inner {
		        public init() {}
		    }
		    public struct Value {
		        public let x = 1
		    }
		}
		public struct Box<T> {
		    public let value: T
		}
		public typealias PlainAlias = Plain
		public enum Mode { case fast }
		public enum Payload { case count(Int), pair(Int, String) }
		public struct Point {
		    let x: Int
		    let y: Int
		}
		fileprivate final class Helper {
		    init() {}
		}
		public final class Root {
		    public init(shared: Plain) {
		        plain = shared
		        optionalSome = shared
		        existential = shared
		        aliased = shared
		    }
		    public let plain: Plain
		    public let optionalSome: Plain?
		    public let optionalNone: Plain? = nil
		    public let closure: () -> Void = {}
		    public let sendableClosure: @Sendable () -> Void = {}
		    public let optionalClosure: (() -> Void)? = nil
		    public let tuple: (Int, label: String) = (1, "x")
		    public let existential: any Shape
		    public let nested = Outer.Inner()
		    public let nestedValue = Outer.Value()
		    public let generic = Box(value: 3)
		    public let aliased: PlainAlias
		    public let integer = 3
		    public let flag = false
		    public let text = "default"
		    public let double = 1.5
		    public let enumeration: Mode = .fast
		    public let payload: Payload = .count(2)
		    public let pair: Payload = .pair(1, "a")
		    public let array = [1, 2]
		    public let set: Set<String> = ["b", "a"]
		    public let dictionary = ["k": 1, "j": 2]
		    public let structure = Point(x: 1, y: 2)
		    public let metatype: Any.Type = Outer.Inner.self
		    private let helper = Helper()
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root(shared: Plain())")],
			filesToDelete: &filesToDelete,
		)

		// A value's dynamic type is spelled without its module, so a typealias and an existential show what they hold,
		// and a nested type keeps the type that encloses it. A leaf shows its dynamic type and its value; a closure's
		// value is `(Function)`, whatever the closure does. A private type is named apart from its runtime address.
		#expect(description == """
		probe Root(shared: Plain())
		<1> Root
		  plain: <2> Plain
		  optionalSome: <2> Plain (seen)
		  optionalNone: nil
		  closure: () -> () (Function)
		  sendableClosure: @Sendable () -> () (Function)
		  optionalClosure: nil
		  tuple: (Int, label: String)
		    .0: Int 1
		    label: String "x"
		  existential: <2> Plain (seen)
		  nested: <3> Outer.Inner
		  nestedValue: Outer.Value
		    x: Int 1
		  generic: Box<Int>
		    value: Int 3
		  aliased: <2> Plain (seen)
		  integer: Int 3
		  flag: Bool false
		  text: String "default"
		  double: Double 1.5
		  enumeration: Mode.fast
		  payload: Payload.count
		    count: Int 2
		  pair: Payload.pair
		    pair: (Int, String)
		      .0: Int 1
		      .1: String "a"
		  array: Array<Int>
		    0: Int 1
		    1: Int 2
		  set: Set<String>
		    0: String "a"
		    1: String "b"
		  dictionary: Dictionary<String, Int>
		    0: (key: String, value: Int)
		      key: String "j"
		      value: Int 2
		    1: (key: String, value: Int)
		      key: String "k"
		      value: Int 1
		  structure: Point
		    x: Int 1
		    y: Int 2
		  metatype: Outer.Inner
		  helper: <4> (private).Helper

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_traversesEachWrapperByItsKind_whenAFixtureStoresEveryWrapper() throws {
		let fixture = """
		public final class Root {
		    public init(
		        bBuilder: Instantiator<B>,
		        sendableBBuilder: SendableInstantiator<B>,
		        fBuilder: Instantiator<F>,
		        sendableFBuilder: SendableInstantiator<F>,
		        anyBBuilder: ErasedInstantiator<(), B>,
		        sendableAnyBBuilder: SendableErasedInstantiator<(), B>,
		        lazyB: LazilyInstantiated<B>,
		        sendableLazyB: SendableLazilyInstantiated<B>,
		        lazyBAgain: LazilyInstantiated<B>,
		        bBuilderAgain: Instantiator<B>
		    ) {
		        self.bBuilder = bBuilder
		        self.sendableBBuilder = sendableBBuilder
		        self.fBuilder = fBuilder
		        self.sendableFBuilder = sendableFBuilder
		        self.anyBBuilder = anyBBuilder
		        self.sendableAnyBBuilder = sendableAnyBBuilder
		        self.lazyB = lazyB
		        self.sendableLazyB = sendableLazyB
		        self.lazyBAgain = lazyBAgain
		        self.bBuilderAgain = bBuilderAgain
		    }
		    public let bBuilder: Instantiator<B>
		    public let sendableBBuilder: SendableInstantiator<B>
		    public let fBuilder: Instantiator<F>
		    public let sendableFBuilder: SendableInstantiator<F>
		    public let anyBBuilder: ErasedInstantiator<(), B>
		    public let sendableAnyBBuilder: SendableErasedInstantiator<(), B>
		    public let lazyB: LazilyInstantiated<B>
		    public let sendableLazyB: SendableLazilyInstantiated<B>
		    public let lazyBAgain: LazilyInstantiated<B>
		    public let bBuilderAgain: Instantiator<B>
		}
		public final class A: Sendable {
		    public init() {}
		}
		public final class B: Instantiable, Sendable {
		    public init(a: A) {
		        self.a = a
		    }
		    public let a: A
		}
		public final class F: Instantiable {
		    public typealias ForwardedProperties = String
		    public init(name: String) {
		        self.name = name
		    }
		    public let name: String
		}
		extension Root {
		    static func make() -> Root {
		        let a = A()
		        let bBuilder = Instantiator { B(a: a) }
		        let lazyB = LazilyInstantiated { B(a: a) }
		        return Root(
		            bBuilder: bBuilder,
		            sendableBBuilder: SendableInstantiator { B(a: a) },
		            fBuilder: Instantiator { F(name: $0) },
		            sendableFBuilder: SendableInstantiator { F(name: $0) },
		            anyBBuilder: ErasedInstantiator { B(a: a) },
		            sendableAnyBBuilder: SendableErasedInstantiator { B(a: a) },
		            lazyB: lazyB,
		            sendableLazyB: SendableLazilyInstantiated { B(a: a) },
		            lazyBAgain: lazyB,
		            bBuilderAgain: bBuilder
		        )
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root.make()")],
			filesToDelete: &filesToDelete,
		)

		// A wrapper is a class, so a wrapper two properties share is numbered once, and its instantiator is called, or
		// its instance read, once per visit. An instantiator is called twice. The instances the `LazilyInstantiated`
		// wrappers hold are read after the rest.
		#expect(description == """
		probe Root.make()
		<1> Root
		  bBuilder: <2> Instantiator<B>
		    instantiate(): <3> B
		      a: <4> A
		    instantiate() again: <5> B
		      a: <4> A (seen)
		  sendableBBuilder: <6> SendableInstantiator<B>
		    instantiate(): <7> B
		      a: <4> A (seen)
		    instantiate() again: <8> B
		      a: <4> A (seen)
		  fBuilder: <9> Instantiator<F> (not traversed: forwarded arguments)
		  sendableFBuilder: <10> SendableInstantiator<F> (not traversed: forwarded arguments)
		  anyBBuilder: <11> ErasedInstantiator<(), B> (not traversed)
		  sendableAnyBBuilder: <12> SendableErasedInstantiator<(), B> (not traversed)
		  lazyB: <13> LazilyInstantiated<B> (instance read last)
		  sendableLazyB: <14> SendableLazilyInstantiated<B> (instance read last)
		  lazyBAgain: <13> LazilyInstantiated<B> (seen)
		  bBuilderAgain: <2> Instantiator<B> (seen)
		<13>.instance: <15> B
		  a: <4> A (seen)
		<14>.instance: <16> B
		  a: <4> A (seen)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_marksTheInstanceAndNotItsWrapper_whenAStampedFixturesLazilyInstantiatedInstanceWasReadBeforeTheProbesValueWasBuilt() throws {
		let fixture = """
		\(Self.stampCounter)
		public final class B {
		    public init() {}
		    \(Self.stampProperty)
		}
		public final class Root {
		    public init(untouched: LazilyInstantiated<B>, readEarly: LazilyInstantiated<B>) {
		        self.untouched = untouched
		        self.readEarly = readEarly
		    }
		    public let untouched: LazilyInstantiated<B>
		    public let readEarly: LazilyInstantiated<B>
		    \(Self.stampProperty)
		}
		extension Root {
		    static func make() -> Root {
		        let readEarly = LazilyInstantiated { B() }
		        _ = readEarly.instance
		        return Root(untouched: LazilyInstantiated { B() }, readEarly: readEarly)
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root.make()")],
			filesToDelete: &filesToDelete,
		)

		// The early read's instance is built before `Root`, and its stamp says so. The wrapper's state is not written in a
		// stamped probe, where a read by the probe's own instantiator calls would set it too, so one early read is one mark.
		#expect(description == """
		probe Root.make()
		<1> Root
		  untouched: <2> LazilyInstantiated<B> (instance read last)
		  readEarly: <3> LazilyInstantiated<B> (instance read last)
		<2>.instance: <4> B
		<3>.instance: <5> B (built before the probe's value)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_marksAnInstanceBuiltBeforeTheProbesValue_whenAnInstantiatorTheProbeCallsReadsItFirst_inEitherDeclarationOrder() throws {
		let makers = """
		extension RootBuilderFirst {
		    static func lazy() -> RootBuilderFirst {
		        let lazyX = LazilyInstantiated { X() }
		        return RootBuilderFirst(cBuilder: Instantiator { C(x: lazyX.instance) }, lazyX: lazyX)
		    }
		    static func readDuringConstruction() -> RootBuilderFirst {
		        let lazyX = LazilyInstantiated { X() }
		        _ = lazyX.instance
		        return RootBuilderFirst(cBuilder: Instantiator { C(x: lazyX.instance) }, lazyX: lazyX)
		    }
		    static func capturedPreBuilt() -> RootBuilderFirst {
		        let made = X()
		        let lazyX = LazilyInstantiated { made }
		        return RootBuilderFirst(cBuilder: Instantiator { C(x: lazyX.instance) }, lazyX: lazyX)
		    }
		}
		extension RootLazyFirst {
		    static func lazy() -> RootLazyFirst {
		        let lazyX = LazilyInstantiated { X() }
		        return RootLazyFirst(lazyX: lazyX, cBuilder: Instantiator { C(x: lazyX.instance) })
		    }
		    static func readDuringConstruction() -> RootLazyFirst {
		        let lazyX = LazilyInstantiated { X() }
		        _ = lazyX.instance
		        return RootLazyFirst(lazyX: lazyX, cBuilder: Instantiator { C(x: lazyX.instance) })
		    }
		    static func capturedPreBuilt() -> RootLazyFirst {
		        let made = X()
		        let lazyX = LazilyInstantiated { made }
		        return RootLazyFirst(lazyX: lazyX, cBuilder: Instantiator { C(x: lazyX.instance) })
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": Self.lazyInstanceReadByBuilderFixture, "Makers.swift": makers]),
			probes: ["RootBuilderFirst", "RootLazyFirst"].flatMap { root in
				["lazy", "readDuringConstruction", "capturedPreBuilt"].map { DifferentialValueProbe("\(root).\($0)()") }
			},
			filesToDelete: &filesToDelete,
		)

		// The probe's call of `cBuilder` builds `C`, which reads the instance: lazily, after the probe's value was built;
		// otherwise, before. The instance is marked where it is read last, whichever line saw it first.
		#expect(description == """
		probe RootBuilderFirst.lazy()
		<1> RootBuilderFirst
		  cBuilder: <2> Instantiator<C>
		    instantiate(): <3> C
		      x: <4> X
		    instantiate() again: <5> C
		      x: <4> X (seen)
		  lazyX: <6> LazilyInstantiated<X> (instance read last)
		<6>.instance: <4> X (seen)
		probe RootBuilderFirst.readDuringConstruction()
		<1> RootBuilderFirst
		  cBuilder: <2> Instantiator<C>
		    instantiate(): <3> C
		      x: <4> X
		    instantiate() again: <5> C
		      x: <4> X (seen)
		  lazyX: <6> LazilyInstantiated<X> (instance read last)
		<6>.instance: <4> X (built before the probe's value) (seen)
		probe RootBuilderFirst.capturedPreBuilt()
		<1> RootBuilderFirst
		  cBuilder: <2> Instantiator<C>
		    instantiate(): <3> C
		      x: <4> X
		    instantiate() again: <5> C
		      x: <4> X (seen)
		  lazyX: <6> LazilyInstantiated<X> (instance read last)
		<6>.instance: <4> X (built before the probe's value) (seen)
		probe RootLazyFirst.lazy()
		<1> RootLazyFirst
		  lazyX: <2> LazilyInstantiated<X> (instance read last)
		  cBuilder: <3> Instantiator<C>
		    instantiate(): <4> C
		      x: <5> X
		    instantiate() again: <6> C
		      x: <5> X (seen)
		<2>.instance: <5> X (seen)
		probe RootLazyFirst.readDuringConstruction()
		<1> RootLazyFirst
		  lazyX: <2> LazilyInstantiated<X> (instance read last)
		  cBuilder: <3> Instantiator<C>
		    instantiate(): <4> C
		      x: <5> X
		    instantiate() again: <6> C
		      x: <5> X (seen)
		<2>.instance: <5> X (built before the probe's value) (seen)
		probe RootLazyFirst.capturedPreBuilt()
		<1> RootLazyFirst
		  lazyX: <2> LazilyInstantiated<X> (instance read last)
		  cBuilder: <3> Instantiator<C>
		    instantiate(): <4> C
		      x: <5> X
		    instantiate() again: <6> C
		      x: <5> X (seen)
		<2>.instance: <5> X (built before the probe's value) (seen)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_leavesALazilyBuiltInstanceUnmarked_whenTheProbesValueAlsoHoldsIt() throws {
		// A mock builds the instance of a lazily instantiated wrapper up front when the mocked type itself takes it by
		// value: a path that holds the instance differs from one that does not by its identity, not by a mark.
		let fixture = """
		\(Self.stampCounter)
		public final class X {
		    public init() {}
		    \(Self.stampProperty)
		}
		public final class Root {
		    public init(x: X, lazyX: LazilyInstantiated<X>) {
		        self.x = x
		        self.lazyX = lazyX
		    }
		    public let x: X
		    public let lazyX: LazilyInstantiated<X>
		    \(Self.stampProperty)
		}
		extension Root {
		    static func make() -> Root {
		        let lazyX = LazilyInstantiated { X() }
		        return Root(x: lazyX.instance, lazyX: lazyX)
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root.make()")],
			filesToDelete: &filesToDelete,
		)

		#expect(description == """
		probe Root.make()
		<1> Root
		  x: <2> X
		  lazyX: <3> LazilyInstantiated<X> (instance read last)
		<3>.instance: <2> X (seen)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_leavesAConstantOfTheProbesValueUnmarked_whenAnInstantiatorDeclaredBeforeItShowsItFirst() throws {
		// Generated code builds a root's constants before the root, so `a`'s stamp is below the root's, and the probe's
		// call of `bBuilder` shows it before the root's own property does.
		let fixture = """
		\(Self.stampCounter)
		public final class A {
		    public init() {}
		    \(Self.stampProperty)
		}
		public final class B: Instantiable {
		    public init(a: A) {
		        self.a = a
		    }
		    public let a: A
		    \(Self.stampProperty)
		}
		public final class Root {
		    public init(bBuilder: Instantiator<B>, a: A) {
		        self.bBuilder = bBuilder
		        self.a = a
		    }
		    public let bBuilder: Instantiator<B>
		    public let a: A
		    \(Self.stampProperty)
		}
		extension Root {
		    static func make() -> Root {
		        let a = A()
		        return Root(bBuilder: Instantiator { B(a: a) }, a: a)
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root.make()")],
			filesToDelete: &filesToDelete,
		)

		#expect(description == """
		probe Root.make()
		<1> Root
		  bBuilder: <2> Instantiator<B>
		    instantiate(): <3> B
		      a: <4> A
		    instantiate() again: <5> B
		      a: <4> A (seen)
		  a: <4> A (seen)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_marksALazilyBuiltInstanceBuiltBeforeTheProbesValue_whateverTheWrapperAndWhetherItIsOptional() throws {
		let fixture = """
		\(Self.stampCounter)
		public final class B: Sendable {
		    public init() {}
		    \(Self.stampProperty)
		}
		public final class Root {
		    public init(
		        lazyB: LazilyInstantiated<B>,
		        optionalLazyB: LazilyInstantiated<B>?,
		        sendableLazyB: SendableLazilyInstantiated<B>,
		        optionalSendableLazyB: SendableLazilyInstantiated<B>?,
		        sendableReadEarly: SendableLazilyInstantiated<B>
		    ) {
		        self.lazyB = lazyB
		        self.optionalLazyB = optionalLazyB
		        self.sendableLazyB = sendableLazyB
		        self.optionalSendableLazyB = optionalSendableLazyB
		        self.sendableReadEarly = sendableReadEarly
		    }
		    public let lazyB: LazilyInstantiated<B>
		    public let optionalLazyB: LazilyInstantiated<B>?
		    public let sendableLazyB: SendableLazilyInstantiated<B>
		    public let optionalSendableLazyB: SendableLazilyInstantiated<B>?
		    public let sendableReadEarly: SendableLazilyInstantiated<B>
		    \(Self.stampProperty)
		}
		extension Root {
		    static func make() -> Root {
		        let made = B()
		        let madeForOptional = B()
		        let madeForSendable = B()
		        let madeForOptionalSendable = B()
		        let sendableReadEarly = SendableLazilyInstantiated { B() }
		        _ = sendableReadEarly.instance
		        return Root(
		            lazyB: LazilyInstantiated { made },
		            optionalLazyB: LazilyInstantiated { madeForOptional },
		            sendableLazyB: SendableLazilyInstantiated { madeForSendable },
		            optionalSendableLazyB: SendableLazilyInstantiated { madeForOptionalSendable },
		            sendableReadEarly: sendableReadEarly
		        )
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root.make()")],
			filesToDelete: &filesToDelete,
		)

		// Each instance is built before `Root`, the probe's value, which holds none of them. A `SendableLazilyInstantiated`
		// hides whether it was read, and its instance read early is marked as a captured one is.
		#expect(description == """
		probe Root.make()
		<1> Root
		  lazyB: <2> LazilyInstantiated<B> (instance read last)
		  optionalLazyB: <3> LazilyInstantiated<B> (instance read last)
		  sendableLazyB: <4> SendableLazilyInstantiated<B> (instance read last)
		  optionalSendableLazyB: <5> SendableLazilyInstantiated<B> (instance read last)
		  sendableReadEarly: <6> SendableLazilyInstantiated<B> (instance read last)
		<2>.instance: <7> B (built before the probe's value)
		<3>.instance: <8> B (built before the probe's value)
		<4>.instance: <9> B (built before the probe's value)
		<5>.instance: <10> B (built before the probe's value)
		<6>.instance: <11> B (built before the probe's value)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_leavesALazilyBuiltInstanceUnmarked_whenItsOwnDependenciesAreBuiltInsideItsWrappersClosure() throws {
		let fixture = """
		\(Self.stampCounter)
		public final class A {
		    public init() {}
		    \(Self.stampProperty)
		}
		public final class B {
		    public init(a: A) {
		        self.a = a
		    }
		    public let a: A
		    \(Self.stampProperty)
		}
		public final class Root {
		    public init(lazyB: LazilyInstantiated<B>) {
		        self.lazyB = lazyB
		    }
		    public let lazyB: LazilyInstantiated<B>
		    \(Self.stampProperty)
		}
		extension Root {
		    static func make() -> Root {
		        Root(lazyB: LazilyInstantiated { B(a: A()) })
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root.make()")],
			filesToDelete: &filesToDelete,
		)

		// The read builds `A` and then `B`, each stamped after `Root`, the probe's value.
		#expect(description == """
		probe Root.make()
		<1> Root
		  lazyB: <2> LazilyInstantiated<B> (instance read last)
		<2>.instance: <3> B
		  a: <4> A

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_leavesALazilyBuiltInstanceUnmarked_whenItsWrapperIsBuiltByAnInstantiatorTheProbeCalls() throws {
		let fixture = """
		\(Self.stampCounter)
		public final class B {
		    public init() {}
		    \(Self.stampProperty)
		}
		public final class C: Instantiable {
		    public init(lazyB: LazilyInstantiated<B>) {
		        self.lazyB = lazyB
		    }
		    public let lazyB: LazilyInstantiated<B>
		    \(Self.stampProperty)
		}
		public final class Root {
		    public init(cBuilder: Instantiator<C>) {
		        self.cBuilder = cBuilder
		    }
		    public let cBuilder: Instantiator<C>
		    \(Self.stampProperty)
		}
		extension Root {
		    static func make() -> Root {
		        Root(cBuilder: Instantiator { C(lazyB: LazilyInstantiated { B() }) })
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Root.make()")],
			filesToDelete: &filesToDelete,
		)

		// Each `C`, and its wrapper, is built while the probe is described, and each `B` after it, when it is read.
		#expect(description == """
		probe Root.make()
		<1> Root
		  cBuilder: <2> Instantiator<C>
		    instantiate(): <3> C
		      lazyB: <4> LazilyInstantiated<B> (instance read last)
		    instantiate() again: <5> C
		      lazyB: <6> LazilyInstantiated<B> (instance read last)
		<4>.instance: <7> B
		<6>.instance: <8> B

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_callsAnInstantiatorUntilItsTypeAndPropertyAreBeingCalledTwiceOnThePath_whenInstantiatorsFormACycle() throws {
		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": Self.cycleFixture]),
			probes: [DifferentialValueProbe("T1.make()")],
			filesToDelete: &filesToDelete,
		)

		// Each call creates a new `T1` with a new `t2Builder`, so identity never repeats: the path does. The cycle is
		// unrolled once, and beneath a second call each instantiator is called once.
		#expect(description == """
		probe T1.make()
		<1> T1
		  t2Builder: <2> Instantiator<T2>
		    instantiate(): <3> T2
		      t1Builder: <4> Instantiator<T1>
		        instantiate(): <5> T1
		          t2Builder: <6> Instantiator<T2>
		            instantiate(): <7> T2
		              t1Builder: <8> Instantiator<T1>
		                instantiate(): <9> T1
		                  t2Builder: <10> Instantiator<T2> (not called: T1.t2Builder is being called twice on this path)
		                instantiate() again: <11> T1
		                  t2Builder: <12> Instantiator<T2> (not called: T1.t2Builder is being called twice on this path)
		            instantiate() again: <13> T2
		              t1Builder: <14> Instantiator<T1>
		                instantiate(): <15> T1
		                  t2Builder: <16> Instantiator<T2> (not called: T1.t2Builder is being called twice on this path)
		        instantiate() again: <17> T1
		          t2Builder: <18> Instantiator<T2>
		            instantiate(): <19> T2
		              t1Builder: <20> Instantiator<T1>
		                instantiate(): <21> T1
		                  t2Builder: <22> Instantiator<T2> (not called: T1.t2Builder is being called twice on this path)
		    instantiate() again: <23> T2
		      t1Builder: <24> Instantiator<T1>
		        instantiate(): <25> T1
		          t2Builder: <26> Instantiator<T2>
		            instantiate(): <27> T2
		              t1Builder: <28> Instantiator<T1>
		                instantiate(): <29> T1
		                  t2Builder: <30> Instantiator<T2> (not called: T1.t2Builder is being called twice on this path)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_namesAnotherModulesTypeWithoutItsModule_whenAPathSpansModules() throws {
		let path = DifferentialValuePath(modules: [
			DifferentialValueModule(
				name: "Core",
				fixtureFiles: ["Thing.swift": "public final class Thing {\n    public init() {}\n}\n"],
			),
			DifferentialValueModule(
				name: "Extensions",
				dependencyModuleNames: ["Core"],
				fixtureFiles: ["Inner.swift": "import Core\nextension Thing {\n    public struct Inner {\n        public init() {}\n        public struct Deeper {\n            public init() {}\n        }\n    }\n}\n"],
			),
			DifferentialValueModule(
				name: "App",
				dependencyModuleNames: ["Core", "Extensions"],
				fixtureFiles: ["Root.swift": """
				import Core
				import Extensions
				extension Thing.Inner {
				    public struct Further {
				        public init() {}
				    }
				}
				public final class Root {
				    public init() {}
				    public let thing = Thing()
				    public let things: [Thing] = []
				    public let inner = Thing.Inner()
				    public let deeper = Thing.Inner.Deeper()
				    public let further = Thing.Inner.Further()
				    public let inners: [Thing.Inner] = []
				}
				"""],
			),
		])

		let description = try DifferentialValueOracle.describe(path, probes: [DifferentialValueProbe("Root()")], filesToDelete: &filesToDelete)

		// A type is named without its module, and without the extensions of the path's modules it is declared in
		// (`(extension in App):(extension in Extensions):Core.Thing.Inner.Further`), so that a graph split across
		// modules compares against the same graph in one module. Two types of one name in two modules of a path
		// therefore print alike.
		#expect(description == """
		probe Root()
		<1> Root
		  thing: <2> Thing
		  things: Array<Thing>
		  inner: Thing.Inner
		  deeper: Thing.Inner.Deeper
		  further: Thing.Inner.Further
		  inners: Array<Thing.Inner>

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_keepsTheExtensionATypeIsDeclaredIn_whenItsModuleIsNotOneOfThePaths() throws {
		let fixture = """
		import Foundation
		public final class Holder {
		    public init() {}
		    public let encodingType: Any.Type = String.Encoding.self
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Holder()")],
			filesToDelete: &filesToDelete,
		)

		// Foundation declares `String.Encoding` in an extension of `String`, which swift-foundation, the Foundation of
		// Linux, declares in `FoundationEssentials`. The runtime spells it `(extension in Foundation):Swift.String.Encoding`.
		#if canImport(Darwin)
			let extensionModuleName = "Foundation"
		#else
			let extensionModuleName = "FoundationEssentials"
		#endif
		#expect(description == """
		probe Holder()
		<1> Holder
		  encodingType: (extension in \(extensionModuleName)):String.Encoding

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_listsTheValuesOfASetInTheOrderOfTheirDescriptions_andLeavesInstancesOfASetOrDictionaryUncompared() throws {
		let fixture = """
		public final class Node: Hashable {
		    public init(value: Int) {
		        self.value = value
		    }
		    public let value: Int
		    public static func == (lhs: Node, rhs: Node) -> Bool {
		        lhs === rhs
		    }
		    public func hash(into hasher: inout Hasher) {
		        hasher.combine(ObjectIdentifier(self))
		    }
		}
		public final class Holder {
		    public init() {}
		    public let nodes = Set([6, 3, 1, 5, 2, 4].map { Node(value: $0) })
		    public let valuesByNode = [Node(value: 1): 1, Node(value: 2): 2]
		    public let nested: Set<Set<Int>> = [[5], [2, 3], [4, 1]]
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Holder()")],
			filesToDelete: &filesToDelete,
		)

		// Hash order changes from process to process: values, a set of sets among them, are listed in the order of their
		// descriptions, and a set or dictionary that holds instances is described by its kind and count alone.
		#expect(description == """
		probe Holder()
		<1> Holder
		  nodes: Set<Node> (not compared: set of 6 class instances)
		  valuesByNode: Dictionary<Node, Int> (not compared: dictionary of 2 class instances)
		  nested: Set<Set<Int>>
		    0: Set<Int>
		      0: Int 1
		      1: Int 4
		    1: Set<Int>
		      0: Int 2
		      1: Int 3
		    2: Set<Int>
		      0: Int 5

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_describesAValueAlikeInEveryRun_whenItHoldsAnAddressDataOrAnAnyHashable() throws {
		let fixture = """
		import Foundation
		public final class Holder {
		    public init() {}
		    public let data = Data([1, 2, 255])
		    public let tags = AnyHashable(Set(["u", "v", "w", "x", "y", "z"]))
		    public let number = AnyHashable(1)
		    public let identifier = ObjectIdentifier(Holder.self)
		    public let pointer = UnsafeRawPointer(bitPattern: 0x1000)!
		    public let optionalPointer = UnsafeMutablePointer<Int>(bitPattern: 0x2000)
		    public let opaquePointer = OpaquePointer(bitPattern: 0x3000)!
		}
		"""
		let path = DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture])

		// Each path runs in a process of its own, with addresses and hash order of its own.
		let comparison = try DifferentialValueOracle.compare(feature: path, knownRight: path, probes: [DifferentialValueProbe("Holder()")], filesToDelete: &filesToDelete)

		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences.isEmpty, "\(comparisonMade.report)")
		#expect(comparisonMade.knownRightDescription == """
		probe Holder()
		<1> Holder
		  data: Data 3 bytes 0102ff
		  tags: Set<String>
		    0: String "u"
		    1: String "v"
		    2: String "w"
		    3: String "x"
		    4: String "y"
		    5: String "z"
		  number: Int 1
		  identifier: ObjectIdentifier (address)
		  pointer: UnsafeRawPointer (address)
		  optionalPointer: UnsafeMutablePointer<Int> (address)
		  opaquePointer: OpaquePointer (address)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_readsEachLazilyBuiltInstanceUnderTheCallsWhereItsWrapperWasMet_whenTheInstanceHoldsABuilderOfItsOwner() throws {
		// Corpus seed 2996's shape, which SafeDI accepts: each instance read last builds instances whose wrappers are read
		// last in turn, so reading them under no calls never ends.
		let fixture = """
		public final class A: Instantiable {
		    public init(lazyB: LazilyInstantiated<B>) {
		        self.lazyB = lazyB
		    }
		    public let lazyB: LazilyInstantiated<B>
		}
		public final class B: Instantiable {
		    public init(aBuilder: Instantiator<A>) {
		        self.aBuilder = aBuilder
		    }
		    public let aBuilder: Instantiator<A>
		}
		extension A {
		    static func make() -> A {
		        func makeA() -> A {
		            A(lazyB: LazilyInstantiated { B(aBuilder: Instantiator { makeA() }) })
		        }
		        return makeA()
		    }
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("A.make()")],
			filesToDelete: &filesToDelete,
		)

		#expect(description == """
		probe A.make()
		<1> A
		  lazyB: <2> LazilyInstantiated<B> (instance read last)
		<2>.instance: <3> B
		  aBuilder: <4> Instantiator<A>
		    instantiate(): <5> A
		      lazyB: <6> LazilyInstantiated<B> (instance read last)
		    instantiate() again: <7> A
		      lazyB: <8> LazilyInstantiated<B> (instance read last)
		<6>.instance: <9> B
		  aBuilder: <10> Instantiator<A>
		    instantiate(): <11> A
		      lazyB: <12> LazilyInstantiated<B> (instance not read: A.lazyB is being read twice on this path)
		    instantiate() again: <13> A
		      lazyB: <14> LazilyInstantiated<B> (instance not read: A.lazyB is being read twice on this path)
		<8>.instance: <15> B
		  aBuilder: <16> Instantiator<A>
		    instantiate(): <17> A
		      lazyB: <18> LazilyInstantiated<B> (instance not read: A.lazyB is being read twice on this path)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_stopsTraversingWrappers_whenAProbeHasSpentItsTraversals() throws {
		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": Self.cycleFixture]),
			probes: [DifferentialValueProbe("T1.make()")],
			limits: DifferentialValueLimits(traversalsPerProbe: 3),
			filesToDelete: &filesToDelete,
		)

		#expect(description == """
		probe T1.make()
		<1> T1
		  t2Builder: <2> Instantiator<T2>
		    instantiate(): <3> T2
		      t1Builder: <4> Instantiator<T1>
		        instantiate(): <5> T1
		          t2Builder: <6> Instantiator<T2>
		            instantiate(): <7> T2
		              t1Builder: <8> Instantiator<T1> (not called: the probe's 3 traversals are spent)
		            instantiate() again: <9> T2
		              t1Builder: <10> Instantiator<T1> (not called: the probe's 3 traversals are spent)
		        instantiate() again: <11> T1
		          t2Builder: <12> Instantiator<T2> (not called: the probe's 3 traversals are spent)
		    instantiate() again: <13> T2
		      t1Builder: <14> Instantiator<T1> (not called: the probe's 3 traversals are spent)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_numbersEachProbeAfresh_andMarksAnInstanceAnEarlierProbeHeld() throws {
		let fixture = """
		public final class A: Sendable {
		    public init() {}
		}
		public enum Shared {
		    public static let a = A()
		}
		public final class Holder {
		    public init() {}
		    public let shared = Shared.a
		    public let own = A()
		}
		"""

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("Holder()"), DifferentialValueProbe(name: "second holder", expression: "Holder()")],
			filesToDelete: &filesToDelete,
		)

		#expect(description == """
		probe Holder()
		<1> Holder
		  shared: <2> A
		  own: <3> A
		probe second holder
		<1> Holder
		  shared: <2> A (seen in probe Holder())
		  own: <3> A

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func describe_runsProbesWithTheAlarmSignalUnblocked_whenTheThreadThatSpawnsThemBlocksIt() throws {
		let fixture = """
		#if canImport(Glibc)
		import Glibc
		#elseif canImport(Darwin)
		import Darwin
		#endif

		public struct AlarmSignal {
		    public init() {
		        var blockedSignals = sigset_t()
		        pthread_sigmask(SIG_BLOCK, nil, &blockedSignals)
		        isBlocked = sigismember(&blockedSignals, SIGALRM) == 1
		    }

		    public let isBlocked: Bool
		}
		"""
		// On Linux, libdispatch blocks every signal but a few faults on the threads Swift concurrency runs on, and
		// swift-corelibs-foundation's `Process` hands the spawning thread's mask to the process it spawns. Blocking
		// `SIGALRM` here spawns the probes from such a thread wherever the test runs; Apple's Foundation resets the mask
		// when it spawns a process, so only on Linux does this test fail without the describer's own reset.
		var alarmSignal = sigset_t()
		sigemptyset(&alarmSignal)
		sigaddset(&alarmSignal, SIGALRM)
		var previouslyBlockedSignals = sigset_t()
		pthread_sigmask(SIG_BLOCK, &alarmSignal, &previouslyBlockedSignals)
		defer {
			pthread_sigmask(SIG_SETMASK, &previouslyBlockedSignals, nil)
		}

		let description = try DifferentialValueOracle.describe(
			DifferentialValuePath(fixtureFiles: ["Fixture.swift": fixture]),
			probes: [DifferentialValueProbe("AlarmSignal()")],
			filesToDelete: &filesToDelete,
		)

		// The alarm that ends a probe past its time limit stops the probe executable only when `SIGALRM` is unblocked.
		#expect(description == """
		probe AlarmSignal()
		AlarmSignal
		  isBlocked: Bool false

		""")
	}

	// MARK: Errors

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsNamingThePath_whenAPathsModuleDoesNotCompile() throws {
		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: Self.graphPath(generated: Self.graphGeneratedCode()),
				knownRight: Self.graphPath(generated: Self.graphGeneratedCode(replacing: ["e: a": "e: 1"])),
				probes: [DifferentialValueProbe("Root()")],
				filesToDelete: &filesToDelete,
			)
		}

		#expect(error.path == .knownRight)
		#expect(error.stage == .compilingModule("DifferentialValueGraph"))
		#expect(error.description.hasPrefix("The known-right path's module `DifferentialValueGraph` does not compile:\n"))
		#expect(error.description.contains("error: cannot convert value of type 'Int' to expected argument type 'A'"))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsNamingTheProbes_whenAProbeDoesNotCompile() throws {
		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: Self.graphPath(generated: Self.graphGeneratedCode()),
				knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
				probes: [DifferentialValueProbe("Root(missing: 1)")],
				filesToDelete: &filesToDelete,
			)
		}

		#expect(error.path == .feature)
		#expect(error.stage == .compilingProbes)
		#expect(error.description.hasPrefix("The feature path's probes do not compile:\n"))
		#expect(error.description.contains("error: "))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsWithTheDescriptionSoFar_whenAProbeTraps() throws {
		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: Self.graphPath(generated: Self.graphGeneratedCode() + "\nextension Root {\n    static func trap() -> Root {\n        fatalError(\"boom\")\n    }\n}\n"),
				knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
				probes: [DifferentialValueProbe("A()"), DifferentialValueProbe("Root.trap()")],
				filesToDelete: &filesToDelete,
			)
		}

		#expect(error.path == .feature)
		#expect(error.stage == .runningProbes)
		#expect(error.description.hasPrefix("The feature path's probes did not run to completion (exit status "))
		#expect(error.description.contains("Fatal error: boom"))
		#expect(error.description.hasSuffix("\nDescribed before it stopped:\nprobe A()\n<1> A\nprobe Root.trap()\n"))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsNamingThePath_whenAFixturePrintsAProbeHeading() throws {
		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: Self.graphPath(generated: Self.graphGeneratedCode(replacing: ["let a = A()": "let a = A()\n        print(\"probe printed by the fixture\")"])),
				knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
				probes: [DifferentialValueProbe("Root()")],
				filesToDelete: &filesToDelete,
			)
		}

		#expect(error.path == .feature)
		#expect(error.stage == .runningProbes)
		#expect(error.description.hasPrefix("The feature path's probes printed 2 probe headings for 1 probes, as when a fixture prints one:\n"))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_namesAProbeByItsExpression_whenTheExpressionSpansLines() throws {
		let expression = "{\n\tlet root = Root()\n\treturn root\n}()"

		let comparison = try DifferentialValueOracle.compare(
			feature: Self.graphPath(generated: Self.graphGeneratedCode(replacing: ["e: a": "e: nil"])),
			knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
			probes: [DifferentialValueProbe(expression)],
			filesToDelete: &filesToDelete,
		)

		// The heading prints the name on one line; a difference names the probe as it was made.
		let comparisonMade = try #require(comparison)
		#expect(comparisonMade.differences == [
			DifferentialValueDifference(probe: expression, path: ["<1> Root", "e"], feature: "e: nil", knownRight: "e: <2> A (seen, first at <1> Root > a)"),
		])
		#expect(comparisonMade.featureDescription == """
		probe {\\n\\tlet root = Root()\\n\\treturn root\\n}()
		<1> Root
		  a: <2> A
		  b: <3> B
		    a: <2> A (seen)
		    c: <4> C
		  e: nil
		  title: String "default"
		  bBuilder: <5> Instantiator<B>
		    instantiate(): <6> B
		      a: <2> A (seen)
		      c: <7> C
		    instantiate() again: <8> B
		      a: <2> A (seen)
		      c: <9> C
		  lazyB: <10> LazilyInstantiated<B> (instance read last)
		<10>.instance: <11> B
		  a: <2> A (seen)
		  c: <12> C

		""")
	}

	// MARK: Spent traversals

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsNamingTheProbeAndTheBudget_whenBothPathsSpendTheirTraversalsAtANodeBeyondWhichTheyDiffer() throws {
		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: Self.buildersPath(b2: "Instantiator { B(n: 99) }", lazyB: "LazilyInstantiated { B(n: 3) }"),
				knownRight: Self.buildersPath(lazyB: "LazilyInstantiated { B(n: 3) }"),
				probes: [DifferentialValueProbe("Root()")],
				limits: DifferentialValueLimits(traversalsPerProbe: 1),
				filesToDelete: &filesToDelete,
			)
		}

		// Beyond `b2`, the feature path builds `B(n: 99)` and the known-right path `B(n: 2)`, which neither describes.
		// The probe spends its traversals at `lazyB` too.
		#expect(error.path == nil)
		#expect(error.stage == .runningProbes)
		#expect(error.description == """
		Both paths' probe `Root()` spent its 1 traversals at <1> Root > b2, so nothing beneath it is compared. Raise `DifferentialValueLimits.traversalsPerProbe`, or accept it with an exemption equal to this difference:
		probe `Root()` at <1> Root > b2:
		  feature:     b2: <5> Instantiator<B> (not called: the probe's 1 traversals are spent)
		  known right: b2: <5> Instantiator<B> (not called: the probe's 1 traversals are spent)
		Other nodes where the graph's probes spent their traversals, each accepted only by an exemption of its own: 1
		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsNamingThePathThatSpentItsTraversals_whenOnlyOnePathSpendsThem() throws {
		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: Self.buildersPath(b1: "nil"),
				knownRight: Self.buildersPath(),
				probes: [DifferentialValueProbe("Root()")],
				limits: DifferentialValueLimits(traversalsPerProbe: 1),
				filesToDelete: &filesToDelete,
			)
		}

		// The known-right path spends its traversal on `b1`, which the feature path does not hold, and none is left for
		// `b2`, which the feature path calls.
		#expect(error.path == .knownRight)
		#expect(error.stage == .runningProbes)
		#expect(error.description == """
		The known-right path's probe `Root()` spent its 1 traversals at <1> Root > b2, so nothing beneath it is compared. Raise `DifferentialValueLimits.traversalsPerProbe`, or accept it with an exemption equal to this difference:
		probe `Root()` at <1> Root > b2:
		  feature:     b2: <2> Instantiator<B>
		  known right: b2: <5> Instantiator<B> (not called: the probe's 1 traversals are spent)
		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsNamingTheProbe_whenAProbeSpendsItsTraversalsAtALazilyInstantiatedWrapper() throws {
		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: Self.buildersPath(b2: "nil", lazyB: "LazilyInstantiated { B(n: 99) }"),
				knownRight: Self.buildersPath(b2: "nil", lazyB: "LazilyInstantiated { B(n: 3) }"),
				probes: [DifferentialValueProbe("Root()")],
				limits: DifferentialValueLimits(traversalsPerProbe: 1),
				filesToDelete: &filesToDelete,
			)
		}

		#expect(error.path == nil)
		#expect(error.stage == .runningProbes)
		#expect(error.description == """
		Both paths' probe `Root()` spent its 1 traversals at <1> Root > lazyB, so nothing beneath it is compared. Raise `DifferentialValueLimits.traversalsPerProbe`, or accept it with an exemption equal to this difference:
		probe `Root()` at <1> Root > lazyB:
		  feature:     lazyB: <5> LazilyInstantiated<B> (instance not read: the probe's 1 traversals are spent)
		  known right: lazyB: <5> LazilyInstantiated<B> (instance not read: the probe's 1 traversals are spent)
		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsTheDifferencesAndNoError_whenAProbeSpendsItsLastTraversalOnItsLastWrapper() throws {
		let comparison = try DifferentialValueOracle.compare(
			feature: Self.buildersPath(b2: "Instantiator { B(n: 99) }"),
			knownRight: Self.buildersPath(),
			probes: [DifferentialValueProbe("Root()")],
			limits: DifferentialValueLimits(traversalsPerProbe: 2),
			filesToDelete: &filesToDelete,
		)

		// The probe traverses exactly its two wrappers, so no wrapper goes untraversed.
		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "b2", "instantiate()", "n"], feature: "n: Int 99", knownRight: "n: Int 2"),
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "b2", "instantiate() again", "n"], feature: "n: Int 99", knownRight: "n: Int 2"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsOnlyTheDifference_whenAProbeSpendsItsTraversalsBeneathANodeThatDiffers() throws {
		let fixture = """
		public final class C: Instantiable {
		    public init() {}
		}
		public final class Left {
		    public init() {}
		    public let first = Instantiator { C() }
		    public let second = Instantiator { C() }
		}
		public final class Right {
		    public init() {}
		    public let first = Instantiator { C() }
		    public let second = Instantiator { C() }
		}
		public final class Root {
		    public init(child: AnyObject) {
		        self.child = child
		    }
		    public let child: AnyObject
		}
		"""
		func path(child: String) -> DifferentialValuePath {
			DifferentialValuePath(fixtureFiles: ["Root.swift": fixture], generatedFiles: ["Root+Make.swift": "extension Root {\n    convenience init() {\n        self.init(child: \(child)())\n    }\n}\n"])
		}

		let comparison = try DifferentialValueOracle.compare(
			feature: path(child: "Left"),
			knownRight: path(child: "Right"),
			probes: [DifferentialValueProbe("Root()")],
			limits: DifferentialValueLimits(traversalsPerProbe: 1),
			filesToDelete: &filesToDelete,
		)

		// Each path spends its traversal on `child.first`, beneath `child`, whose difference fails the probe and whose
		// exemption would accept everything beneath it.
		#expect(try #require(comparison).differences == [
			DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "child"], feature: "child: <2> Left", knownRight: "child: <2> Right"),
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func expectDifferentialValuesAgree_acceptsASpentBudget_whenAnExemptionEqualsTheDifferenceWhereTheProbeSpentIt() throws {
		// A feature whose graph outgrows any budget compares what lies before the node, deliberately.
		try expectDifferentialValuesAgree(
			feature: Self.buildersPath(b2: "Instantiator { B(n: 99) }"),
			knownRight: Self.buildersPath(),
			probes: [DifferentialValueProbe("Root()")],
			exempting: [
				DifferentialValueDifference(
					probe: "Root()",
					path: ["<1> Root", "b2"],
					feature: "b2: <5> Instantiator<B> (not called: the probe's 1 traversals are spent)",
					knownRight: "b2: <5> Instantiator<B> (not called: the probe's 1 traversals are spent)",
				),
			],
			limits: DifferentialValueLimits(traversalsPerProbe: 1),
			filesToDelete: &filesToDelete,
		)
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_throwsNamingANodeBeneathAnInstanceReadLast_whenAProbeSpendsItsTraversalsInsideALazilyBuiltInstance() throws {
		let fixture = """
		public final class C: Instantiable {
		    public init(n: Int) {
		        self.n = n
		    }
		    public let n: Int
		}
		public final class B {
		    public init(cBuilder: Instantiator<C>, dBuilder: Instantiator<C>) {
		        self.cBuilder = cBuilder
		        self.dBuilder = dBuilder
		    }
		    public let cBuilder: Instantiator<C>
		    public let dBuilder: Instantiator<C>
		}
		public final class Root {
		    public init(lazyB: LazilyInstantiated<B>) {
		        self.lazyB = lazyB
		    }
		    public let lazyB: LazilyInstantiated<B>
		}
		"""
		func path(n: Int) -> DifferentialValuePath {
			DifferentialValuePath(fixtureFiles: ["Root.swift": fixture], generatedFiles: ["Root+Make.swift": "extension Root {\n    convenience init() {\n        self.init(lazyB: LazilyInstantiated { B(cBuilder: Instantiator { C(n: 1) }, dBuilder: Instantiator { C(n: \(n)) }) })\n    }\n}\n"])
		}

		let error = try #require(throws: DifferentialValueOracleError.self) {
			try DifferentialValueOracle.compare(
				feature: path(n: 99),
				knownRight: path(n: 2),
				probes: [DifferentialValueProbe("Root()")],
				limits: DifferentialValueLimits(traversalsPerProbe: 2),
				filesToDelete: &filesToDelete,
			)
		}

		// The read of `lazyB`'s instance and the calls of `cBuilder` spend both traversals.
		#expect(error.path == nil)
		#expect(error.stage == .runningProbes)
		#expect(error.description == """
		Both paths' probe `Root()` spent its 2 traversals at <2>.instance > dBuilder, so nothing beneath it is compared. Raise `DifferentialValueLimits.traversalsPerProbe`, or accept it with an exemption equal to this difference:
		probe `Root()` at <2>.instance > dBuilder:
		  feature:     dBuilder: <7> Instantiator<C> (not called: the probe's 2 traversals are spent)
		  known right: dBuilder: <7> Instantiator<C> (not called: the probe's 2 traversals are spent)
		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_failsOnlyTheGraphThatSpentItsTraversals_whenGraphsAreComparedInBatches() throws {
		let graphs = [
			Self.batchGraph(named: "First", featureSharesInstance: false),
			DifferentialValueGraph(name: "Spending", feature: Self.buildersPath(b2: "Instantiator { B(n: 99) }"), knownRight: Self.buildersPath(), probes: [DifferentialValueProbe("Root()")]),
		]

		let comparisons = try #require(try DifferentialValueOracle.compare(graphs: graphs, limits: DifferentialValueLimits(traversalsPerProbe: 1), filesToDelete: &filesToDelete))

		// One batch of two paths, compared once: the graph that spent its traversals fails without the batch being
		// compared again graph by graph.
		#expect(filesToDelete.count == 2)
		#expect(try comparisons[0].result.get().differences == [
			DifferentialValueDifference(probe: "FirstRoot()", path: ["<1> FirstRoot", "e"], feature: "e: nil", knownRight: "e: <2> FirstA (seen, first at <1> FirstRoot > a)"),
		])
		let error = try #require(throws: DifferentialValueOracleError.self) { try comparisons[1].result.get() }
		#expect(error.path == nil)
		#expect(error.stage == .runningProbes)
		#expect(error.description.hasPrefix("Both paths' probe `Root()` spent its 1 traversals at <1> Root > b2, "))
	}

	// MARK: Batches

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_attributesEachDifferenceToItsGraph_whenGraphsAreComparedInBatches() throws {
		// The first two graphs share a layout and compile together; the third, compiled with another condition, alone.
		let graphs = [
			Self.batchGraph(named: "First", featureSharesInstance: true),
			Self.batchGraph(named: "Second", featureSharesInstance: false),
			Self.batchGraph(named: "Third", featureSharesInstance: true, activeCompilationConditions: ["THIRD"]),
		]

		let comparisons = try #require(try DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete))

		// Each path of each batch is one probe executable in a directory of its own: two batches of two paths. Compared
		// one graph at a time, the graphs would make six; and the third graph's types exist only under its condition.
		#expect(filesToDelete.count == 4)
		#expect(comparisons.map(\.name) == ["First", "Second", "Third"])
		#expect(try comparisons.map { try $0.result.get().differences } == [
			[],
			[DifferentialValueDifference(probe: "SecondRoot()", path: ["<1> SecondRoot", "e"], feature: "e: nil", knownRight: "e: <2> SecondA (seen, first at <1> SecondRoot > a)")],
			[],
		])
		#expect(try comparisons[1].result.get().featureDescription == """
		probe SecondRoot()
		<1> SecondRoot
		  a: <2> SecondA
		  e: nil

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_comparesEachPairInOnePath_whenGraphsHoldProbePairs() throws {
		let graphs = [
			Self.pairedGraph(named: "PairedFirst", featureSharesInstance: true),
			Self.pairedGraph(named: "PairedSecond", featureSharesInstance: false),
		]

		let comparisons = try #require(try DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete))

		// The two graphs share a layout and hold both ways in one path, so the batch is one compile of that path and one
		// probe executable, in one directory.
		#expect(filesToDelete.count == 1)
		#expect(try comparisons.map { try $0.result.get().differences } == [
			[],
			[DifferentialValueDifference(probe: "PairedSecondRoot.feature()", path: ["<1> PairedSecondRoot", "e"], feature: "e: nil", knownRight: "e: <2> PairedSecondA (seen, first at <1> PairedSecondRoot > a)")],
		])
		#expect(try comparisons[1].result.get().featureDescription == """
		probe PairedSecondRoot.feature()
		<1> PairedSecondRoot
		  a: <2> PairedSecondA
		  e: nil

		""")
		#expect(try comparisons[1].result.get().knownRightDescription == """
		probe PairedSecondRoot.feature()
		<1> PairedSecondRoot
		  a: <2> PairedSecondA
		  e: <2> PairedSecondA (seen)

		""")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_comparesEachGraphOfABatchOnItsOwn_whenOneGraphOfTheBatchDoesNotCompile() throws {
		let broken = Self.batchGraph(named: "Broken", featureSharesInstance: true)
		let graphs = [
			Self.batchGraph(named: "Compiling", featureSharesInstance: false),
			DifferentialValueGraph(
				name: broken.name,
				feature: DifferentialValuePath(modules: broken.feature.modules.map { module in
					var module = module
					module.generatedFiles = module.generatedFiles.mapValues { $0.replacingOccurrences(of: "e: a", with: "e: 1") }
					return module
				}),
				knownRight: broken.knownRight,
				probes: broken.probes,
			),
		]

		let comparisons = try #require(try DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete))

		// The batch's feature path, which does not compile, then each graph on its own: two paths, then one.
		#expect(filesToDelete.count == 4)
		#expect(comparisons.map(\.name) == ["Compiling", "Broken"])
		#expect(try comparisons[0].result.get().differences == [
			DifferentialValueDifference(probe: "CompilingRoot()", path: ["<1> CompilingRoot", "e"], feature: "e: nil", knownRight: "e: <2> CompilingA (seen, first at <1> CompilingRoot > a)"),
		])
		let error = try #require(throws: DifferentialValueOracleError.self) { try comparisons[1].result.get() }
		#expect(error.path == .feature)
		#expect(error.stage == .compilingModule(standaloneVerificationModuleName))
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsADifferenceOnlyInItsGraph_whenGraphsOfABatchHoldOneInstanceFromAModuleEveryGraphHoldsAlike() throws {
		// Graphs in a batch declare no type in common but in a module every graph of the batch holds alike, which the
		// batch compiles once, so only an instance from such a module, or from a module outside the path, can be held
		// by two of them. The type is the test's own, so its instances describe alike on every toolchain. The first
		// graph holds the shared instance on one path only, and another instance of the type on the other.
		let shared = """
		public final class SharedState: Sendable {
		    public static let instance = SharedState()
		    public init() {}
		    public let label = "shared"
		}
		"""
		func graph(named name: String, featureState: String, knownRightState: String, featureTitle: String) -> DifferentialValueGraph {
			let fixture = """
			import Shared
			public final class \(name)Root {
			    public init(state: SharedState, title: String) {
			        self.state = state
			        self.title = title
			    }
			    public let state: SharedState
			    public let title: String
			}
			"""
			func path(state: String, title: String) -> DifferentialValuePath {
				DifferentialValuePath(modules: [
					DifferentialValueModule(name: "Shared", fixtureFiles: ["Shared.swift": shared]),
					DifferentialValueModule(
						name: "App",
						dependencyModuleNames: ["Shared"],
						fixtureFiles: ["Graph.swift": fixture],
						generatedFiles: ["Generated.swift": "import Shared\nextension \(name)Root {\n    convenience init() {\n        self.init(state: \(state), title: \"\(title)\")\n    }\n}\n"],
					),
				])
			}
			return DifferentialValueGraph(name: name, feature: path(state: featureState, title: featureTitle), knownRight: path(state: knownRightState, title: "default"), probes: [DifferentialValueProbe("\(name)Root()")])
		}
		let graphs = [
			graph(named: "First", featureState: "SharedState.instance", knownRightState: "SharedState()", featureTitle: "default"),
			graph(named: "Second", featureState: "SharedState.instance", knownRightState: "SharedState.instance", featureTitle: "other"),
		]

		let comparisons = try #require(try DifferentialValueOracle.compare(graphs: graphs, filesToDelete: &filesToDelete))

		// One executable per path: the batch compiled the shared module once. A first visit in either path holds a
		// `SharedState`; only the second graph's title differs. Without a reset at the second graph, its feature path
		// would mark the shared instance as seen in the first graph's probe.
		#expect(filesToDelete.count == 2)
		#expect(try comparisons.map { try $0.result.get().differences } == [
			[],
			[DifferentialValueDifference(probe: "SecondRoot()", path: ["<1> SecondRoot", "title"], feature: "title: String \"other\"", knownRight: "title: String \"default\"")],
		])
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_reportsTheGraphWhoseProbeDoesNotFinish_whenAProbeOfABatchRunsPastItsTimeLimit() throws {
		let spinningFixture = """
		public final class SpinningRoot {
		    public init() {}
		    public static func spin() -> SpinningRoot {
		        while true {}
		    }
		}
		"""
		let spinningPath = DifferentialValuePath(fixtureFiles: ["Graph.swift": spinningFixture])
		let graphs = [
			Self.batchGraph(named: "Finishing", featureSharesInstance: true),
			// The first probe prints more lines than the error keeps.
			DifferentialValueGraph(name: "Spinning", feature: spinningPath, knownRight: spinningPath, probes: [DifferentialValueProbe("Array(0..<150)"), DifferentialValueProbe("SpinningRoot.spin()")]),
		]

		let comparisons = try #require(try DifferentialValueOracle.compare(graphs: graphs, limits: DifferentialValueLimits(probeTimeLimitInSeconds: 1), filesToDelete: &filesToDelete))

		#expect(try comparisons[0].result.get().differences.isEmpty)
		let error = try #require(throws: DifferentialValueOracleError.self) { try comparisons[1].result.get() }
		#expect(error.path == .feature)
		#expect(error.stage == .runningProbes)
		#expect(error.description.hasPrefix("The feature path's probe `SpinningRoot.spin()` did not finish within its time limit, 1 s:\n"))
		#expect(error.description.hasSuffix("\nDescribed before it stopped:\n(53 earlier lines left out)\n" + (51..<150).map { "  \($0): Int \($0)\n" }.joined() + "probe SpinningRoot.spin()\n"))
	}

	// MARK: Assertion

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func expectDifferentialValuesAgree_recordsEachUnexemptedDifference_whenPathsDiffer() throws {
		var filesToDelete = [URL]()
		defer { self.filesToDelete += filesToDelete }

		// The feature path differs in two places, one of them exempted: only the other is recorded.
		try withKnownIssue {
			try expectDifferentialValuesAgree(
				feature: Self.graphPath(generated: Self.graphGeneratedCode(replacing: ["e: a": "e: nil", "title: \"default\"": "title: \"other\""])),
				knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
				probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("A()")],
				exempting: [DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "e"], feature: "e: nil", knownRight: "e: <2> A (seen, first at <1> Root > a)")],
				filesToDelete: &filesToDelete,
			)
		} matching: { issue in
			issue.comments.first?.rawValue.hasPrefix("The feature path builds other values than the known-right path for probe `Root()` at <1> Root > title:\n  feature:     title: String \"other\"\n  known right: title: String \"default\"\nFeature path:\nprobe Root()\n") == true
		}

		try expectDifferentialValuesAgree(
			feature: Self.graphPath(generated: Self.graphGeneratedCode(replacing: ["e: a": "e: nil"])),
			knownRight: Self.graphPath(generated: Self.graphGeneratedCode()),
			probes: [DifferentialValueProbe("Root()"), DifferentialValueProbe("A()")],
			exempting: [DifferentialValueDifference(probe: "Root()", path: ["<1> Root", "e"], feature: "e: nil", knownRight: "e: <2> A (seen, first at <1> Root > a)")],
			filesToDelete: &filesToDelete,
		)
	}

	// MARK: Graph fuzzer

	@Test
	func fixture_storesEveryParameter_whenAskedTo_forSeed35() {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 35, storingEveryParameter: true)

		// The extension's `instantiate(…)` stores each parameter, the received one, the default-valued ones, and the
		// unlabeled one, so the comparator sees the values the generated call passes and the defaults it leaves in place.
		// The type stores a creation stamp too, as every class of the graph does.
		#expect(fixture.swiftFileContent.last == """
		@Instantiable(generateMock: true)
		extension S35_Ext: Instantiable {
			public static func instantiate(t4: S35_T6, title: String = "default", retryCount: Int = 3, _ note: String = "") -> S35_Ext {
				S35_Ext(t4: t4, title: title, retryCount: retryCount, note: note)
			}
		}

		public final class S35_Ext {
			let differentialValueCreationStamp = S35_CreationStamp.next()

			public init(t4: S35_T6, title: String, retryCount: Int, note: String) {
				self.t4 = t4
				self.title = title
				self.retryCount = retryCount
				self.note = note
			}

			public let t4: S35_T6
			public let title: String
			public let retryCount: Int
			public let note: String
		}

		""")
		#expect(GraphFuzzerGenerator.fixture(forSeed: 35).swiftFileContent.last == """
		@Instantiable(generateMock: true)
		extension S35_Ext: Instantiable {
			public static func instantiate(t4: S35_T6, title: String = "default", retryCount: Int = 3, _ note: String = "") -> S35_Ext {
				S35_Ext()
			}
		}

		public final class S35_Ext {
			public init() {}
		}

		""")
	}

	@Test
	func fixture_declaresTheCreationStampCounterInTheFirstFile_whenItStoresEveryParameter_forSeed35() {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 35, storingEveryParameter: true)

		// Every class stores a stamp from the graph's one counter, a class without a body among them, so that the
		// comparator sees an instance a lazily instantiated wrapper's closure captures, built before the wrapper.
		#expect(fixture.swiftFileContent.first == """
		@Instantiable(isRoot: true)
		public final class S35_Root0: Instantiable {
			let differentialValueCreationStamp = S35_CreationStamp.next()

			public init(anyT0Builder: ErasedInstantiator<S35_T3, S35_AnyT0>, t4_S35_T6: S35_Leaf, t6Builder: Instantiator<S35_T6>) {
				self.anyT0Builder = anyT0Builder
				self.t4_S35_T6 = t4_S35_T6
				self.t6Builder = t6Builder
			}

			@Instantiated(fulfilledByType: "S35_T0", erasedToConcreteExistential: true) let anyT0Builder: ErasedInstantiator<S35_T3, S35_AnyT0>
			@Instantiated let t4_S35_T6: S35_Leaf
			@Instantiated let t6Builder: Instantiator<S35_T6>
		}

		public final class S35_Value: Instantiable {
			let differentialValueCreationStamp = S35_CreationStamp.next()
		}

		public enum S35_CreationStamp {
			nonisolated(unsafe) private static var lastStamp = 0

			public static func next() -> Int {
				lastStamp += 1
				return lastStamp
			}
		}

		""")
	}

	@Test
	func fixture_storesEveryParameterInAnUncheckedSendableType_whenAMixedGraphsExtensionReceivesAWrapperThatIsNotSendable_forSeed296() {
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 296, storingEveryParameter: true)

		// The graph mixes `Sendable` and non-`Sendable` wrappers, and `instantiate(…)` receives an `Instantiator`, which
		// is not `Sendable`: a `Sendable` type cannot store it.
		#expect(fixture.swiftFileContent.last == """
		@Instantiable
		extension S296_Ext: Instantiable {
			public static func instantiate(t3Builder: Instantiator<S296_T3>, retryCount: Int = 3, _ note: String = "") -> S296_Ext {
				S296_Ext(t3Builder: t3Builder, retryCount: retryCount, note: note)
			}
		}

		public final class S296_Ext: @unchecked Sendable {
			let differentialValueCreationStamp = S296_CreationStamp.next()

			public init(t3Builder: Instantiator<S296_T3>, retryCount: Int, note: String) {
				self.t3Builder = t3Builder
				self.retryCount = retryCount
				self.note = note
			}

			public let t3Builder: Instantiator<S296_T3>
			public let retryCount: Int
			public let note: String
		}

		""")
		#expect(GraphFuzzerGenerator.fixture(forSeed: 296).swiftFileContent.last == """
		@Instantiable
		extension S296_Ext: Instantiable {
			public static func instantiate(t3Builder: Instantiator<S296_T3>, retryCount: Int = 3, _ note: String = "") -> S296_Ext {
				S296_Ext()
			}
		}

		public final class S296_Ext: Sendable {
			public init() {}
		}

		""")
	}

	@Test
	func fixture_storesDefaultValuedInitializerParameter_whenAskedTo_forSeed17() {
		// Seed 17's graph is the first with the `Sendable` builder motif, whose owner takes a default-valued `formatter`.
		let ownerSource = { (storingEveryParameter: Bool) in
			GraphFuzzerGenerator.fixture(forSeed: 17, storingEveryParameter: storingEveryParameter).swiftFileContent.first { $0.contains("class S17_T8:") }
		}

		// Each class the file declares also stores a creation stamp.
		#expect(ownerSource(true) == """
		@Instantiable
		public final class S17_T8: Instantiable, S17_T8Protocol {
			let differentialValueCreationStamp = S17_CreationStamp.next()

			public init(t9: S17_T9, formatter: S17_Formatter = S17_Formatter()) {
				self.t9 = t9
				self.formatter = formatter
			}

			@Instantiated let t9: S17_T9
			let formatter: S17_Formatter
		}

		public protocol S17_T8Protocol: AnyObject {}

		public final class S17_AnyT8 {
			let differentialValueCreationStamp = S17_CreationStamp.next()

			public init(_ value: S17_T8) {
				self.value = value
			}

			public let value: S17_T8
		}

		public final class S17_Formatter {
			let differentialValueCreationStamp = S17_CreationStamp.next()

			public init() {}
		}

		""")
		#expect(ownerSource(false) == """
		@Instantiable
		public final class S17_T8: Instantiable, S17_T8Protocol {
			public init(t9: S17_T9, formatter: S17_Formatter = S17_Formatter()) {
				self.t9 = t9
			}

			@Instantiated let t9: S17_T9
		}

		public protocol S17_T8Protocol: AnyObject {}

		public final class S17_AnyT8 {
			public init(_ value: S17_T8) {
				self.value = value
			}

			public let value: S17_T8
		}

		public final class S17_Formatter {
			public init() {}
		}

		""")
	}

	@Test
	func fixture_drawsTheSameGraph_whetherOrNotItStoresEveryParameter_forEverySmokeAndKnownIssueSeed() {
		// Storing every parameter changes only how a type is written, never what the seed draws: the declarations SafeDI
		// reads are the same, so the tool's verdict and generated code are too, and the base corpus pins do not move.
		for seed in SafeDIToolGraphFuzzerTests.smokeSeeds + SafeDIToolGraphFuzzerTests.knownIssues.flatMap(\.seeds) {
			let fixture = GraphFuzzerGenerator.fixture(forSeed: seed)
			let storingFixture = GraphFuzzerGenerator.fixture(forSeed: seed, storingEveryParameter: true)
			#expect(fixture.fileNames == storingFixture.fileNames)
			#expect(fixture.swiftFileContent.map(Self.declarationsSafeDIReads(in:)) == storingFixture.swiftFileContent.map(Self.declarationsSafeDIReads(in:)), "Seed \(seed)")
		}
	}

	/// The fixture of each of these seeds compiles when it stores no parameter: the long run compiles every corpus
	/// fixture, on its own when the tool rejects the graph, and none fails as a fixture that does not compile.
	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode), arguments: 0..<Self.storingFixtureCompilationPartCount)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func fixture_compilesWhenItStoresEveryParameter_forEachSmokeKnownIssueAndMixedGraphSeed(part: Int) throws {
		let seeds = Array(Set(SafeDIToolGraphFuzzerTests.smokeSeeds + SafeDIToolGraphFuzzerTests.knownIssues.flatMap(\.seeds) + Self.mixedGraphSeedsWhoseExtensionReceivesAWrapperThatIsNotSendable)).sorted()
		let seedsOfPart = seeds.enumerated().filter { $0.offset % Self.storingFixtureCompilationPartCount == part }.map(\.element)

		// Each fixture is compiled on its own: the tool reads the same declarations from it, so the code it generates is
		// the same as for the fixture that stores no parameter.
		let failures = try GraphFuzzerOracle.compilationFailures(of: seedsOfPart.map { seed in
			GraphFuzzerToolRuns(fixture: GraphFuzzerGenerator.fixture(forSeed: seed, storingEveryParameter: true), firstOutcome: .rejected(diagnostics: ""), secondOutcome: .rejected(diagnostics: ""))
		})

		#expect(failures.isEmpty, "\(failures.values.map(\.details))")
	}

	@Test(.enabled(if: compileVerificationIsEnabled, Self.compilesGeneratedCode))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func compare_seesADefaultTheGeneratedCallLeavesInPlace_onlyWhenTheFuzzersFixtureStoresEveryParameter() async throws {
		// Seed 0's extension-based type takes `title: String = "default"`, a root's tree builds it, and the tool accepts
		// the graph. The feature path's fixture declares another default, which a generated call leaves in place.
		let fixture = GraphFuzzerGenerator.fixture(forSeed: 0)
		let storingFixture = GraphFuzzerGenerator.fixture(forSeed: 0, storingEveryParameter: true)
		func path(of fixture: GraphFuzzerFixture, replacingDefault: Bool) async throws -> (path: DifferentialValuePath, probes: [DifferentialValueProbe]) {
			let generatedFiles = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: []).generatedFiles
			#expect(!generatedFiles.isEmpty, "Seed 0 is expected to be accepted")
			let path = DifferentialValuePath(fixture: fixture, generatedFiles: generatedFiles)
			let probes = fixture.differentialValueProbes(generatedFiles: generatedFiles)
			guard replacingDefault else { return (path, probes) }
			return (DifferentialValuePath(modules: path.modules.map { module in
				var module = module
				module.fixtureFiles = module.fixtureFiles.mapValues { $0.replacingOccurrences(of: "title: String = \"default\"", with: "title: String = \"other\"") }
				return module
			}), probes)
		}
		let knownRight = try await path(of: fixture, replacingDefault: false)
		#expect(knownRight.probes == [DifferentialValueProbe("S0_Root0()"), DifferentialValueProbe("S0_Root1()"), DifferentialValueProbe("S0_Root2()"), DifferentialValueProbe("S0_Ext.mock()")])

		let blindComparison = try await DifferentialValueOracle.compare(
			feature: try path(of: fixture, replacingDefault: true).path,
			knownRight: knownRight.path,
			probes: knownRight.probes,
			filesToDelete: &filesToDelete,
		)
		let comparison = try await DifferentialValueOracle.compare(
			feature: try path(of: storingFixture, replacingDefault: true).path,
			knownRight: try path(of: storingFixture, replacingDefault: false).path,
			probes: knownRight.probes,
			filesToDelete: &filesToDelete,
		)

		#expect(try #require(blindComparison).differences.isEmpty)
		// The generated mock's `title` parameter carries the default the tool read, so the mock builds the same value in
		// both paths: only the roots, whose trees build the type with `instantiate(…)`'s own default, differ.
		let differences = try #require(comparison).differences
		#expect(differences == ["S0_Root0", "S0_Root1", "S0_Root2"].map { root in
			DifferentialValueDifference(probe: "\(root)()", path: ["<1> \(root)", "anyT2", "value", "ext", "title"], feature: "title: String \"other\"", knownRight: "title: String \"default\"")
		})
	}

	@Test
	func differentialValueProbes_listEachRootAndEachMockWithoutRequiredParameters_forAFixtureTheToolGeneratesCodeFor() async throws {
		let fixture = GraphFuzzerFixture(seed: 7, swiftFileContent: [
			"@Instantiable(isRoot: true)\npublic final class S7_Root0: Instantiable {\n\tpublic init() {}\n}\n",
			"@Instantiable(isRoot: true)\npublic final class S7_Root1: Instantiable {\n\tpublic init() {}\n}\n",
			// A mock that takes no parameters, one whose only parameter is required, and one whose parameter has a default.
			"@Instantiable(generateMock: true)\npublic final class S7_T0: Instantiable {\n\tpublic init() {}\n}\n",
			"@Instantiable(generateMock: true)\npublic final class S7_T1: Instantiable {\n\tpublic init(name: String) {\n\t\tself.name = name\n\t}\n\n\t@Forwarded let name: String\n}\n",
			"@Instantiable(generateMock: true)\npublic final class S7_T2: Instantiable {\n\tpublic init(title: String = \"default\") {}\n}\n",
		])

		let generatedFiles = try await GraphFuzzerOracle.toolRuns(of: fixture, renamings: []).generatedFiles

		#expect(fixture.differentialValueProbes(generatedFiles: generatedFiles) == [
			DifferentialValueProbe("S7_Root0()"),
			DifferentialValueProbe("S7_Root1()"),
			DifferentialValueProbe("S7_T0.mock()"),
			DifferentialValueProbe("S7_T2.mock()"),
		])
	}

	// MARK: Private

	private static let compilesGeneratedCode: Comment = "The comparator compiles and runs generated code, which SAFEDI_SKIP_COMPILE_CHECK skips"

	/// Two types whose instantiators build one another, each call a new instance.
	private static let cycleFixture = """
	public final class T1: Instantiable {
	    public init(t2Builder: Instantiator<T2>) {
	        self.t2Builder = t2Builder
	    }
	    public let t2Builder: Instantiator<T2>
	}
	public final class T2: Instantiable {
	    public init(t1Builder: Instantiator<T1>) {
	        self.t1Builder = t1Builder
	    }
	    public let t1Builder: Instantiator<T1>
	}
	extension T1 {
	    static func make() -> T1 {
	        func makeT1() -> T1 {
	            T1(t2Builder: Instantiator { T2(t1Builder: Instantiator { makeT1() }) })
	        }
	        return makeT1()
	    }
	}
	"""

	/// The graph every rejection test builds: a root that stores a shared instance three ways, a default, an
	/// instantiator, and a lazily instantiated wrapper.
	private static let graphFixture = """
	public final class Root {
	    public init(a: A, b: B, e: A?, title: String, bBuilder: Instantiator<B>, lazyB: LazilyInstantiated<B>?) {
	        self.a = a
	        self.b = b
	        self.e = e
	        self.title = title
	        self.bBuilder = bBuilder
	        self.lazyB = lazyB
	    }
	    public let a: A
	    public let b: B
	    public let e: A?
	    public let title: String
	    public let bBuilder: Instantiator<B>
	    public let lazyB: LazilyInstantiated<B>?
	}
	public final class A {
	    public init() {}
	}
	public final class B: Instantiable {
	    public init(a: A, c: C) {
	        self.a = a
	        self.c = c
	    }
	    public let a: A
	    public let c: C
	}
	public final class C {
	    public init() {}
	}
	"""

	/// What the known-right path generates for `graphFixture`, with each of `replacements` made for a feature path.
	private static func graphGeneratedCode(replacing replacements: KeyValuePairs<String, String> = [:]) -> String {
		var code = """
		extension Root {
		    convenience init() {
		        let a = A()
		        self.init(a: a, b: B(a: a, c: C()), e: a, title: "default", bBuilder: Instantiator { B(a: a, c: C()) }, lazyB: LazilyInstantiated { B(a: a, c: C()) })
		    }
		}
		"""
		for (original, replacement) in replacements {
			code = code.replacingOccurrences(of: original, with: replacement)
		}
		return code
	}

	/// The counter a fixture with creation stamps declares, and the stamp each of its classes stores.
	private static let stampCounter = DifferentialValueCreationStamp.counterDeclaration(named: "Stamp")
	private static let stampProperty = DifferentialValueCreationStamp.property(counterNamed: "Stamp")

	/// Classes with creation stamps: an `X` lazily instantiated, a `C` built by an instantiator that receives `x: X` by
	/// value, and two roots holding both, one declaring the builder first and one the wrapper.
	private static let lazyInstanceReadByBuilderFixture = """
	\(stampCounter)
	public final class X {
	    public init() {}
	    \(stampProperty)
	}
	public final class C: Instantiable {
	    public init(x: X) {
	        self.x = x
	    }
	    public let x: X
	    \(stampProperty)
	}
	public final class RootBuilderFirst {
	    public init(cBuilder: Instantiator<C>, lazyX: LazilyInstantiated<X>) {
	        self.cBuilder = cBuilder
	        self.lazyX = lazyX
	    }
	    public let cBuilder: Instantiator<C>
	    public let lazyX: LazilyInstantiated<X>
	    \(stampProperty)
	}
	public final class RootLazyFirst {
	    public init(lazyX: LazilyInstantiated<X>, cBuilder: Instantiator<C>) {
	        self.lazyX = lazyX
	        self.cBuilder = cBuilder
	    }
	    public let lazyX: LazilyInstantiated<X>
	    public let cBuilder: Instantiator<C>
	    \(stampProperty)
	}
	"""

	/// A path whose classes carry creation stamps, building a root that holds `a` and a lazily instantiated `B`. The
	/// generated initializer binds `a` before `initializerBody`.
	private static func stampedPath(initializerBody: String) -> DifferentialValuePath {
		let fixture = """
		\(stampCounter)
		public final class A {
		    public init() {}
		    \(stampProperty)
		}
		public final class B {
		    public init(a: A) {
		        self.a = a
		    }
		    public let a: A
		    \(stampProperty)
		}
		public final class Root {
		    public init(a: A, lazyB: LazilyInstantiated<B>) {
		        self.a = a
		        self.lazyB = lazyB
		    }
		    public let a: A
		    public let lazyB: LazilyInstantiated<B>
		    \(stampProperty)
		}
		"""
		return DifferentialValuePath(
			fixtureFiles: ["Root.swift": fixture],
			generatedFiles: ["Root+Make.swift": "extension Root {\n    convenience init() {\n        let a = A()\n        \(initializerBody)\n    }\n}\n"],
		)
	}

	/// A root holding two instantiators and a lazily instantiated wrapper of `B`, each optional.
	private static let buildersFixture = """
	public final class B: Instantiable {
	    public init(n: Int) {
	        self.n = n
	    }
	    public let n: Int
	}
	public final class Root {
	    public init(b1: Instantiator<B>?, b2: Instantiator<B>?, lazyB: LazilyInstantiated<B>?) {
	        self.b1 = b1
	        self.b2 = b2
	        self.lazyB = lazyB
	    }
	    public let b1: Instantiator<B>?
	    public let b2: Instantiator<B>?
	    public let lazyB: LazilyInstantiated<B>?
	}
	"""

	/// A path building `buildersFixture`'s root with `b1`, `b2`, and `lazyB`.
	private static func buildersPath(b1: String = "Instantiator { B(n: 1) }", b2: String = "Instantiator { B(n: 2) }", lazyB: String = "nil") -> DifferentialValuePath {
		DifferentialValuePath(
			fixtureFiles: ["Root.swift": buildersFixture],
			generatedFiles: ["Root+Make.swift": "extension Root {\n    convenience init() {\n        self.init(b1: \(b1), b2: \(b2), lazyB: \(lazyB))\n    }\n}\n"],
		)
	}

	private static func graphPath(generated: String) -> DifferentialValuePath {
		DifferentialValuePath(
			modules: [DifferentialValueModule(name: "DifferentialValueGraph", fixtureFiles: ["Graph.swift": graphFixture], generatedFiles: ["Root+SafeDI.swift": generated])],
		)
	}

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private static func differences(betweenKnownRightGraphAnd featureGenerated: String, filesToDelete: inout [URL]) throws -> [DifferentialValueDifference] {
		let comparison = try DifferentialValueOracle.compare(
			feature: graphPath(generated: featureGenerated),
			knownRight: graphPath(generated: graphGeneratedCode()),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
		)
		return try #require(comparison).differences
	}

	/// A graph of a batch whose types begin with `name`, and whose feature path shares the root's instance or passes
	/// `nil` in its place. Every graph's generated file has the same name, as a fuzzer graph's mock configuration does.
	private static func batchGraph(named name: String, featureSharesInstance: Bool, activeCompilationConditions: [String] = []) -> DifferentialValueGraph {
		// Code compiled only under the graph's conditions, if it has any.
		let guarded = { (code: String) in
			activeCompilationConditions.isEmpty ? code : "#if \(activeCompilationConditions.joined(separator: " && "))\n\(code)\n#endif\n"
		}
		let fixture = """
		public final class \(name)Root {
		    public init(a: \(name)A, e: \(name)A?) {
		        self.a = a
		        self.e = e
		    }
		    public let a: \(name)A
		    public let e: \(name)A?
		}
		public final class \(name)A {
		    public init() {}
		}
		"""
		func path(sharingInstance: Bool) -> DifferentialValuePath {
			DifferentialValuePath(
				fixtureFiles: ["Graph.swift": guarded(fixture)],
				generatedFiles: ["Generated.swift": guarded("extension \(name)Root {\n    convenience init() {\n        let a = \(name)A()\n        self.init(a: a, e: \(sharingInstance ? "a" : "nil"))\n    }\n}\n")],
				activeCompilationConditions: activeCompilationConditions,
			)
		}
		return DifferentialValueGraph(name: name, feature: path(sharingInstance: featureSharesInstance), knownRight: path(sharingInstance: true), probes: [DifferentialValueProbe("\(name)Root()")])
	}

	/// A graph of one path that builds its root two ways, `feature()` and `knownRight()`, the second sharing one
	/// instance between two properties and the first sharing it or passing `nil`, compared as one probe pair.
	private static func pairedGraph(named name: String, featureSharesInstance: Bool) -> DifferentialValueGraph {
		let fixture = """
		public final class \(name)Root {
		    public init(a: \(name)A, e: \(name)A?) {
		        self.a = a
		        self.e = e
		    }
		    public let a: \(name)A
		    public let e: \(name)A?
		}
		public final class \(name)A {
		    public init() {}
		}
		"""
		let generated = """
		extension \(name)Root {
		    static func feature() -> \(name)Root {
		        let a = \(name)A()
		        return \(name)Root(a: a, e: \(featureSharesInstance ? "a" : "nil"))
		    }

		    static func knownRight() -> \(name)Root {
		        let a = \(name)A()
		        return \(name)Root(a: a, e: a)
		    }
		}
		"""
		return DifferentialValueGraph(
			name: name,
			path: DifferentialValuePath(fixtureFiles: ["Graph.swift": fixture], generatedFiles: ["Generated.swift": generated]),
			probePairs: [DifferentialValueProbePair(name: "\(name)Root.feature()", featureExpression: "\(name)Root.feature()", knownRightExpression: "\(name)Root.knownRight()")],
		)
	}

	/// The lines of a fuzzer file that SafeDI reads: attributes, type and extension declarations, `instantiate`
	/// signatures, and decorated properties, with initializer bodies, stored defaults, and helper types left out.
	private static func declarationsSafeDIReads(in content: String) -> [GraphFuzzerSourceLine] {
		GraphFuzzerSourceLine.lines(of: content).filter { line in
			switch line {
			case .instantiableAttribute, .typeDeclaration, .instantiateMethod, .property:
				true
			case .other:
				false
			}
		}
	}

	/// The corpus seeds whose fixture, before the extended type of a mixed graph that stores its parameters was
	/// `@unchecked Sendable`, did not compile when it stored every parameter: each stores a received `Instantiator`,
	/// `ErasedInstantiator`, or `LazilyInstantiated`. The tool accepts 296, 515, 1231, 1553, 2403, 2559, 2794, 2964,
	/// 3302, 3360, 3797, and 4244.
	private static let mixedGraphSeedsWhoseExtensionReceivesAWrapperThatIsNotSendable: [UInt64] = [
		127, 184, 200, 225, 296, 509, 515, 543, 544, 844, 1_231, 1_553, 1_988, 2_091, 2_403, 2_446, 2_559, 2_608, 2_685,
		2_715, 2_766, 2_794, 2_871, 2_964, 3_281, 3_302, 3_360, 3_797, 3_968, 4_047, 4_235, 4_244, 4_293, 4_355, 4_410,
		4_580, 4_614, 4_701,
	]

	/// The compilations of the storing fixtures run in this many parts, which the test runs concurrently.
	private static let storingFixtureCompilationPartCount = 4

	private var filesToDelete: [URL]
}
