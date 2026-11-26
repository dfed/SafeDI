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

/// Which production roots that reach a cycle have their code laid out from their per-type plan, and which shape keeps
/// each other one on today's tree (`DependencyTreeGenerator.shapeOutsidePerTypePlan(inTreeOf:cache:)`). Each test also
/// generates its graph with every root kept on today's tree, and expects the same files.
struct SafeDIToolPerTypePlanShapesTests: ~Copyable {
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
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenScreensOnCycleReceiveValueTheirCycleDeclares() async throws {
		// Screens open each other through instantiators, one forwarded a value and instantiating a leaf, the other receiving the leaf.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Forwarded let count: Int
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: Leaf, count: Int, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.count = count; self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleReceivesValueRootDeclares() async throws {
		// A screen receives a value the root declares, which today's function captures, and so does the plan's.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeHoldsLazilyInstantiated() async throws {
		// A screen holds a `LazilyInstantiated`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let leaf: LazilyInstantiated<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: LazilyInstantiated<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .holdsLazilyInstantiated])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeReceivesValueOnlyIfAvailable() async throws {
		// A screen receives a value only if available.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received(onlyIfAvailable: true) let leaf: Leaf?
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf?, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .holdsValueOnlyIfAvailable])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeForwardsOptionalValue() async throws {
		// A screen is forwarded an optional value.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let count: Int?
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(count: Int?, s0Builder: Instantiator<S0>) { self.count = count; self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": .holdsValueOnlyIfAvailable])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeRenamesDependency() async throws {
		// A screen renames a value the root declares.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received(fulfilledByDependencyNamed: "leaf", ofType: Leaf.self) let other: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(other: Leaf, s0Builder: Instantiator<S0>) { self.other = other; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .renames])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeHoldsSendableWrapper() async throws {
		// A screen holds a `SendableInstantiator`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: SendableInstantiator<S0>
		    public init(s0Builder: SendableInstantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: SendableInstantiator<S1>
		    public init(s1Builder: SendableInstantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let s0Builder: SendableInstantiator<S0>
		    public init(s0Builder: SendableInstantiator<S0>) { self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": .holdsSendableWrapperOrFunction])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeIsForwardedSendableFunction() async throws {
		// A screen is forwarded a `@Sendable` function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let onTap: @Sendable () -> Void
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(onTap: @escaping @Sendable () -> Void, s0Builder: Instantiator<S0>) { self.onTap = onTap; self.s0Builder = s0Builder }
		}
		""")

		#expect(choices == ["Root": .holdsSendableWrapperOrFunction])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenCycleMemberIsInstantiatedErased() async throws {
		// A screen instantiates the screen that opened it as an `ErasedInstantiator`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let home: Instantiator<S0>
		    public init(home: Instantiator<S0>) { self.home = home }
		}

		@Instantiable public final class S0: Instantiable, Screen {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated(fulfilledByType: "S0", erasedToConcreteExistential: false) let s0Builder: ErasedInstantiator<(), any Screen>
		    public init(s0Builder: ErasedInstantiator<(), any Screen>) { self.s0Builder = s0Builder }
		}

		public protocol Screen {}
		""")

		#expect(choices == ["Root": .erasesCycleMember])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenInitializerDeclaresNameEscaping() async throws {
		// A screen's initializer declares a forwarded typealias of a function `@escaping`.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(s0Builder: Instantiator<S0>) { self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Forwarded let onTap: OnTap
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(onTap: @escaping OnTap, s0Builder: Instantiator<S0>) { self.onTap = onTap; self.s0Builder = s0Builder }
		}

		public typealias OnTap = () -> Void
		""")

		#expect(choices == ["Root": .declaresEscapingName])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTreeDeclaresLabelInTwoForms() async throws {
		// The root and a screen declare one label with two types.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let leaf: Instantiator<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .holdsLabelInSeveralForms])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeReceivesInstantiator() async throws {
		// A screen receives an instantiator the root declares.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leafBuilder: Instantiator<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leafBuilder: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leafBuilder = leafBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leafBuilder: Instantiator<Leaf>
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leafBuilder: Instantiator<Leaf>, s0Builder: Instantiator<S0>) { self.leafBuilder = leafBuilder; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .receivesInstantiator])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeOutsideCyclesWithChildrenIsInstantiatedTwice() async throws {
		// The root and a screen each instantiate a type outside every cycle that instantiates a value of its own.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let box: Box
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(box: Box, s0Builder: Instantiator<S0>) { self.box = box; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Instantiated let otherBox: Box
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(otherBox: Box, s0Builder: Instantiator<S0>) { self.otherBox = otherBox; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }

		@Instantiable public final class Box: Instantiable {
		    @Instantiated let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}
		""")

		#expect(choices == ["Root": .buildsTreeOutsideCyclesTwice])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenLayersOfScreensReceiveServiceRootDeclares() async throws {
		// Three layers of two screens, each opening the next layer's and the last opening the first's, every screen
		// receiving the root's service.
		let choices = try await choicesGeneratingTodaysCode(of: Self.layersOfScreens(layers: 3, width: 2))

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTypeOnCycleReceivesValueAnotherTypeDeclaresToo() async throws {
		// The root and a feature above the cycle each declare `leaf`, which a screen receives from the feature.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let feature: Feature
		    public init(leaf: Leaf, feature: Feature) { self.leaf = leaf; self.feature = feature }
		}

		@Instantiable public final class Feature: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": .receivesLabelDeclaredOutsideItsCycle])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnNoCycleIsBuiltBeneathOneCycleAndBuildsAnother() async throws {
		// `Between` is on no cycle: a screen of one cycle opens it, and it opens a screen of another, which receives a
		// value the root declares.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    @Instantiated let betweenBuilder: Instantiator<Between>
		    public init(s0Builder: Instantiator<S0>, betweenBuilder: Instantiator<Between>) { self.s0Builder = s0Builder; self.betweenBuilder = betweenBuilder }
		}

		@Instantiable public final class Between: Instantiable {
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(s1Builder: Instantiator<S1>) { self.s1Builder = s1Builder }
		}

		@Instantiable public final class S1: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let s1Builder: Instantiator<S1>
		    public init(leaf: Leaf, s1Builder: Instantiator<S1>) { self.leaf = leaf; self.s1Builder = s1Builder }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenScreenOnCycleOpensScreenOnNoCycleThatReceivesValueRootDeclares() async throws {
		// `Detail` is on no cycle: a screen that opens itself opens it, and its function captures the root's leaf, as the
		// screen's does.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    @Instantiated let detailBuilder: Instantiator<Detail>
		    public init(s0Builder: Instantiator<S0>, detailBuilder: Instantiator<Detail>) { self.s0Builder = s0Builder; self.detailBuilder = detailBuilder }
		}

		@Instantiable public final class Detail: Instantiable {
		    @Received let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenScreenOnCycleHoldsValueWithChildThatReceivesValueRootDeclares() async throws {
		// `Panel` is a value of the screen with a child of its own, and both receive the root's leaf.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(leaf: Leaf, s0Builder: Instantiator<S0>) { self.leaf = leaf; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Instantiated let s0Builder: Instantiator<S0>
		    @Instantiated let panel: Panel
		    public init(s0Builder: Instantiator<S0>, panel: Panel) { self.s0Builder = s0Builder; self.panel = panel }
		}

		@Instantiable public final class Panel: Instantiable {
		    @Received let leaf: Leaf
		    @Instantiated let row: Row
		    public init(leaf: Leaf, row: Row) { self.leaf = leaf; self.row = row }
		}

		@Instantiable public final class Row: Instantiable {
		    @Received let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeNamedWithSendableIsHeld() async throws {
		// A type's name holds the word `Sendable`; no type of the tree is a `Sendable` wrapper or a `@Sendable` function.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let sendableThing: SendableThing
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(sendableThing: SendableThing, s0Builder: Instantiator<S0>) { self.sendableThing = sendableThing; self.s0Builder = s0Builder }
		}

		@Instantiable public final class S0: Instantiable {
		    @Received let sendableThing: SendableThing
		    @Instantiated let s0Builder: Instantiator<S0>
		    public init(sendableThing: SendableThing, s0Builder: Instantiator<S0>) { self.sendableThing = sendableThing; self.s0Builder = s0Builder }
		}

		@Instantiable public final class SendableThing: Instantiable { public init() {} }
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenTypeOnCycleOpensScreenForwardedValueThatReceivesValueRootDeclares() async throws {
		// `T3` is forwarded a name and receives the root's service, which its function captures, as `T2`'s does.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let t2: T2
		    @Instantiated let service: Service
		    public init(t2: T2, service: Service) { self.t2 = t2; self.service = service }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }

		@Instantiable public final class T2: Instantiable {
		    @Instantiated let t3Builder: Instantiator<T3>
		    @Instantiated let t2Builder: Instantiator<T2>
		    @Received let service: Service
		    public init(t3Builder: Instantiator<T3>, t2Builder: Instantiator<T2>, service: Service) { self.t3Builder = t3Builder; self.t2Builder = t2Builder; self.service = service }
		}

		@Instantiable public final class T3: Instantiable {
		    @Forwarded let name: String
		    @Received let service: Service
		    public init(name: String, service: Service) { self.name = name; self.service = service }
		}
		""")

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsRootOnTodaysTree_whenTreePastTheLimitReachesNoCycle() async throws {
		// No type of the tree is built again, so there is nothing to plan and nothing to report.
		let choices = try await choicesGeneratingTodaysCode(of: """
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let leaf: Leaf
		    @Instantiated let screenBuilder: Instantiator<Screen>
		    public init(leaf: Leaf, screenBuilder: Instantiator<Screen>) { self.leaf = leaf; self.screenBuilder = screenBuilder }
		}

		@Instantiable public final class Screen: Instantiable {
		    @Received let leaf: Leaf
		    public init(leaf: Leaf) { self.leaf = leaf }
		}

		@Instantiable public final class Leaf: Instantiable { public init() {} }
		""")

		#expect(choices == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsEveryRootOnTodaysTree_whenTreesAreWithinTheLimit() async throws {
		// Under the limit the tool ships with, no root is asked for a plan, so none is reported.
		let choices = try await choicesGeneratingTodaysCode(of: Self.layersOfScreens(layers: 2, width: 2), abandoningTodaysTreePast: nil)

		#expect(choices == [:])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_laysRootOutFromItsPlanWithTodaysCode_whenItsTreePassesTheLimitTheToolShipsWith() async throws {
		// Layers of screens whose tree per path holds more places than the limit, generated with no limit set by the test,
		// then with every tree kept per path.
		let choices = try await choicesGeneratingTodaysCode(of: Self.layersOfScreens(layers: 4, width: 3), abandoningTodaysTreePast: nil, comparingWithTreesWithin: .max)

		#expect(choices == ["Root": nil])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_reportsTodaysFirstError_whenPlanningRootPastTheLimitThrowsAnother() async {
		// Today's tree builds `S0`'s children before the root's second, so it reports `xBuilder`; the plan builds the
		// root's own body first, and would report `yBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["S0.swift"]):5:5: error: The first generic argument of `xBuilder: ErasedInstantiator<Int, AnyX>` on `S0` must be the @Forwarded properties of `X`, which it builds. Declare it as `ErasedInstantiator<String, AnyX>`.
				"""
			},
		) {
			try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(0) {
				try await executeSafeDIToolTest(
					swiftFileContent: [
						"""
						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(s0Builder: Instantiator<S0>, yBuilder: ErasedInstantiator<Int, AnyX>) { self.s0Builder = s0Builder; self.yBuilder = yBuilder }
						    @Instantiated let s0Builder: Instantiator<S0>
						    @Instantiated(fulfilledByType: "Y", erasedToConcreteExistential: true) let yBuilder: ErasedInstantiator<Int, AnyX>
						}
						""",
						"""
						@Instantiable
						public final class S0: Instantiable {
						    public init(s0Builder: Instantiator<S0>, xBuilder: ErasedInstantiator<Int, AnyX>) { self.s0Builder = s0Builder; self.xBuilder = xBuilder }
						    @Instantiated let s0Builder: Instantiator<S0>
						    @Instantiated(fulfilledByType: "X", erasedToConcreteExistential: true) let xBuilder: ErasedInstantiator<Int, AnyX>
						}
						""",
						"""
						public protocol XProtocol {}
						public final class AnyX: XProtocol { public init(_ x: some XProtocol) {} }

						@Instantiable
						public final class X: XProtocol, Instantiable {
						    public init(name: String) { self.name = name }
						    @Forwarded let name: String
						}
						""",
						"""
						@Instantiable
						public final class Y: XProtocol, Instantiable {
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
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `layers` layers of `width` screens: each screen receives the root's service and opens every screen of the next
	/// layer, and the last layer's open the first's.
	private static func layersOfScreens(layers: Int, width: Int) -> String {
		var declarations = ["""
		@Instantiable(isRoot: true) public final class Root: Instantiable {
		    @Instantiated let service: Service
		    @Instantiated let home: S0_0
		    public init(service: Service, home: S0_0) { self.service = service; self.home = home }
		}

		@Instantiable public final class Service: Instantiable { public init() {} }
		"""]
		for layer in 0..<layers {
			for screen in 0..<width {
				let next = (layer + 1) % layers
				let builders = (0..<width).map { "s\(next)_\($0)Builder" }
				let types = (0..<width).map { "S\(next)_\($0)" }
				let properties = zip(builders, types).map { "    @Instantiated let \($0): Instantiator<\($1)>" }.joined(separator: "\n")
				let parameters = zip(builders, types).map { "\($0): Instantiator<\($1)>" }.joined(separator: ", ")
				let assignments = builders.map { "self.\($0) = \($0)" }.joined(separator: "; ")
				declarations.append("""
				@Instantiable public final class S\(layer)_\(screen): Instantiable {
				    @Received let service: Service
				\(properties)
				    public init(service: Service, \(parameters)) { self.service = service; \(assignments) }
				}
				""")
			}
		}
		return declarations.joined(separator: "\n\n")
	}

	private static func withoutSourceLocations(_ file: String) -> String {
		file.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.contains("#sourceLocation(file:") }.joined(separator: "\n")
	}

	/// Why each root of `swiftFileContent` that reaches a cycle is kept on today's tree, `nil` for one laid out from its
	/// plan. Records an issue where the files generated differ from those generated with every root kept on today's tree.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func choicesGeneratingTodaysCode(
		of swiftFileContent: String,
		abandoningTodaysTreePast scopeGeneratorLimit: Int? = 0,
		comparingWithTreesWithin todaysScopeGeneratorLimit: Int? = nil,
	) async throws -> [String: RootTreeChoiceObservation.PerPathReason?] {
		let (stream, continuation) = AsyncStream.makeStream(of: (String, RootTreeChoiceObservation.PerPathReason?).self)
		// With no place allowed, every root's tree per path is abandoned at once, so each root is laid out from its plan
		// wherever a root past the limit would be. `nil` leaves the limit the tool ships with.
		let output = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(scopeGeneratorLimit) {
			try await RootTreeChoiceObservation.$observer.withValue({ root, perPathReason in
				continuation.yield((root, perPathReason))
			}) {
				try await executeSafeDIToolTest(
					swiftFileContent: [swiftFileContent],
					buildSwiftOutputDirectory: true,
					filesToDelete: &filesToDelete,
				)
			}
		}
		continuation.finish()
		var choices = [String: RootTreeChoiceObservation.PerPathReason?]()
		for await (root, perPathReason) in stream {
			choices[root] = perPathReason
		}
		// Within the limit, every root keeps its tree per path.
		let todaysOutput = try await RootTreeChoiceObservation.$scopeGeneratorLimitOverride.withValue(todaysScopeGeneratorLimit) {
			try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
		// A rename's `#sourceLocation` names its fixture's file, which each run writes in a folder of its own.
		#expect(output.dependencyTreeFiles.mapValues(Self.withoutSourceLocations) == todaysOutput.dependencyTreeFiles.mapValues(Self.withoutSourceLocations))
		return choices
	}
}
