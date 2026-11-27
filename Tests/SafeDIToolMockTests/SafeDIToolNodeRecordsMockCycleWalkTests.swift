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

/// An internal mock root whose world holds a cycle of instantiators, in each shape the records walk refuses in a
/// production root's world (`NodeRecordRefusal`'s `cycle…` cases), laid out from the node records of its world in the
/// slot form of the mock cycle kind. Each mock is to be laid out, and to build the walk's values on every lap, an
/// override set at each place a lap reaches included.
struct SafeDIToolNodeRecordsMockCycleWalkTests: ~Copyable {
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

	/// `C` is built beneath `B`, where it closes on `B`'s place, and beneath `A`, where it builds `B` again
	/// (`cycleMemberBuiltTwoWays`): in the mock, one function of `C` serves both, and the lap decides which.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleMemberIsBuiltWhereItClosesOnAnotherPlace() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) {
				        self.bBuilder = bBuilder
				        self.cBuilder = cBuilder
				    }
				    @Instantiated let bBuilder: Instantiator<B>
				    @Instantiated let cBuilder: Instantiator<C>
				    public var marker = ""
				}
				""",
				"B.swift": """
				@Instantiable
				public final class B: Instantiable, Marked {
				    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
				    @Instantiated let cBuilder: Instantiator<C>
				    public var marker = ""
				}
				""",
				"C.swift": """
				@Instantiable
				public final class C: Instantiable, Marked {
				    public init(bBuilder: Instantiator<B>, aBuilder: Instantiator<A>) {
				        self.bBuilder = bBuilder
				        self.aBuilder = aBuilder
				    }
				    @Instantiated let bBuilder: Instantiator<B>
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().aBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init(cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.b.c\") }), { marked(B(cBuilder: $0), \"a.b\") }), cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.c\") }), { marked(A(bBuilder: $0, cBuilder: $1), \"a\") })))"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init(cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.b.c\") }), { marked(B(cBuilder: $0), \"a.b\") }), cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.c\") }), { marked(A(bBuilder: $0, cBuilder: $1), \"a\") }))).aBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().cBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init(cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.b.c\") }), { marked(B(cBuilder: $0), \"a.b\") }), cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.c\") }), { marked(A(bBuilder: $0, cBuilder: $1), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init(cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.b.c\") }), { marked(B(cBuilder: $0), \"a.b\") }), cBuilder: .init({ marked(C(bBuilder: $0, aBuilder: $1), \"a.c\") }), { marked(A(bBuilder: $0, cBuilder: $1), \"a\") }))).aBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["a", "a.b", "a.b.c", "a.c"],
		)
	}

	/// `Root` enters the ring of `Parent` and `Child` at each of them: each entry's places read the overrides they were
	/// entered with, around every lap.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenRootEntersCycleAtTwoPlaces() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, childBuilder: Instantiator<Child>) {
				        self.parentBuilder = parentBuilder
				        self.childBuilder = childBuilder
				    }
				    @Instantiated let parentBuilder: Instantiator<Parent>
				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) { self.childBuilder = childBuilder }
				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>) { self.parentBuilder = parentBuilder }
				    @Instantiated let parentBuilder: Instantiator<Parent>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().parentBuilder.instantiate().childBuilder.instantiate().parentBuilder.instantiate().childBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().childBuilder.instantiate().parentBuilder.instantiate().childBuilder.instantiate().parentBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.parentBuilder.instantiate().childBuilder.instantiate().parentBuilder.instantiate().childBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.ringOverrides)).parentBuilder.instantiate().childBuilder.instantiate().parentBuilder.instantiate().childBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.childBuilder.instantiate().parentBuilder.instantiate().childBuilder.instantiate().parentBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.ringOverrides)).childBuilder.instantiate().parentBuilder.instantiate().childBuilder.instantiate().parentBuilder.instantiate()"),
			],
			markers: ["parent", "child", "child.parent"],
		)
	}

	/// `Step`, between `Screen`'s place and the call that closes the cycle on it, declares `session`, which `Screen`
	/// receives (`cycleTakesParameters`): each lap's `Screen` holds the `session` its own `Step` built.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeBetweenCycleMemberAndCloserDeclaresLabelTheCycleReceives() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(session: Session, screenBuilder: Instantiator<Screen>) {
				        self.session = session
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let session: Session
				    @Instantiated let screenBuilder: Instantiator<Screen>
				    public var marker = ""
				}
				""",
				"Session.swift": """
				@Instantiable
				public final class Session: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
				"Screen.swift": """
				@Instantiable
				public final class Screen: Instantiable, Marked {
				    public init(session: Session, stepBuilder: Instantiator<Step>) {
				        self.session = session
				        self.stepBuilder = stepBuilder
				    }
				    @Received let session: Session
				    @Instantiated let stepBuilder: Instantiator<Step>
				    public var marker = ""
				}
				""",
				"Step.swift": """
				@Instantiable
				public final class Step: Instantiable, Marked {
				    public init(session: Session, screenBuilder: Instantiator<Screen>) {
				        self.session = session
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let session: Session
				    @Instantiated let screenBuilder: Instantiator<Screen>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().screenBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden", expression: "Root.mock(safeDIOverrides: .init(session: { marked(Session(), \"session\") }, screenBuilder: .init(stepBuilder: .init(session: { marked(Session(), \"step.session\") }, { marked(Step(session: $0, screenBuilder: $1), \"step\") }), { marked(Screen(session: $0, stepBuilder: $1), \"screen\") })))"),
				DifferentialValueProbe(name: "overridden.screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(session: { marked(Session(), \"session\") }, screenBuilder: .init(stepBuilder: .init(session: { marked(Session(), \"step.session\") }, { marked(Step(session: $0, screenBuilder: $1), \"step\") }), { marked(Screen(session: $0, stepBuilder: $1), \"screen\") }))).screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(session: { marked(Session(), \"session\") }, screenBuilder: .init(stepBuilder: .init(session: { marked(Session(), \"step.session\") }, { marked(Step(session: $0, screenBuilder: $1), \"step\") }), { marked(Screen(session: $0, stepBuilder: $1), \"screen\") }))).screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()"),
			],
			markers: ["session", "step.session", "step", "screen"],
			cycleParameters: ["Screen": [Property(label: "session", typeDescription: .simple(name: "Session"))]],
		)
	}

	/// `A`'s body names `Leaf`'s `aBuilder` apart from the root's, which `bBuilder`'s tree closes on, and `Other`'s body
	/// keeps the name of the same variant's function (`cycleBuilderNameShared`).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTwoBodiesNameOneVariantsFunctionApart() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>, other: Other) {
				        self.aBuilder = aBuilder
				        self.other = other
				    }
				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let other: Other
				    public var marker = ""
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(bBuilder: Instantiator<B>, aBuilder: Instantiator<Leaf>) {
				        self.bBuilder = bBuilder
				        self.aBuilder = aBuilder
				    }
				    @Instantiated let bBuilder: Instantiator<B>
				    @Instantiated let aBuilder: Instantiator<Leaf>
				    public var marker = ""
				}
				""",
				"B.swift": """
				@Instantiable
				public final class B: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
				"Other.swift": """
				@Instantiable
				public final class Other: Instantiable, Marked {
				    public init(aBuilder: Instantiator<Leaf>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<Leaf>
				    public var marker = ""
				}
				""",
				"Leaf.swift": """
				@Instantiable
				public final class Leaf: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().other.aBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().aBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().aBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.other", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }), other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }))).other"),
				DifferentialValueProbe(name: "overridden.other.aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }), other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }))).other.aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }), other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }), other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
			],
			markers: ["a", "a.b", "a.leaf", "other", "other.leaf"],
		)
	}

	/// `Screen`'s function takes `session`, which `Step` declares again before the call that closes the cycle: `Root` and
	/// `Hub`, which takes no places, each enter the cycle handing their own, and `Mid`, between `Screen` and `Step`, reads
	/// the one its `Screen` took, on every lap from either entry.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleTakesParameterFromEachEntryAndTypeBetweenReadsIt() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(session: Session, screenBuilder: Instantiator<Screen>, hubBuilder: Instantiator<Hub>) {
				        self.session = session
				        self.screenBuilder = screenBuilder
				        self.hubBuilder = hubBuilder
				    }
				    @Instantiated let session: Session
				    @Instantiated let screenBuilder: Instantiator<Screen>
				    @Instantiated let hubBuilder: Instantiator<Hub>
				    public var marker = ""
				}
				""",
				"Session.swift": """
				@Instantiable
				public final class Session: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
				"Hub.swift": """
				@Instantiable
				public final class Hub: Instantiable, Marked {
				    public init(session: Session, screenBuilder: Instantiator<Screen>) {
				        self.session = session
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let session: Session
				    @Instantiated let screenBuilder: Instantiator<Screen>
				    public var marker = ""
				}
				""",
				"Screen.swift": """
				@Instantiable
				public final class Screen: Instantiable, Marked {
				    public init(session: Session, midBuilder: Instantiator<Mid>) {
				        self.session = session
				        self.midBuilder = midBuilder
				    }
				    @Received let session: Session
				    @Instantiated let midBuilder: Instantiator<Mid>
				    public var marker = ""
				}
				""",
				"Mid.swift": """
				@Instantiable
				public final class Mid: Instantiable, Marked {
				    public init(session: Session, stepBuilder: Instantiator<Step>) {
				        self.session = session
				        self.stepBuilder = stepBuilder
				    }
				    @Received let session: Session
				    @Instantiated let stepBuilder: Instantiator<Step>
				    public var marker = ""
				}
				""",
				"Step.swift": """
				@Instantiable
				public final class Step: Instantiable, Marked {
				    public init(session: Session, screenBuilder: Instantiator<Screen>) {
				        self.session = session
				        self.screenBuilder = screenBuilder
				    }
				    @Instantiated let session: Session
				    @Instantiated let screenBuilder: Instantiator<Screen>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().hubBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.screenBuilder.instantiate().midBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.parameterOverrides)).screenBuilder.instantiate().midBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.hubBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.parameterOverrides)).hubBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.parameterOverrides)).screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.hubBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.parameterOverrides)).hubBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate().stepBuilder.instantiate().screenBuilder.instantiate().midBuilder.instantiate()"),
			],
			markers: ["session", "hub.session", "step.session"],
			cycleParameters: ["Screen": [Property(label: "session", typeDescription: .simple(name: "Session"))]],
		)
	}

	/// `B`, on the cycle of `A` and `B`, receives `session` only if available, so its variants key it as an optional
	/// parameter (`cycleVariantsPartitionApart`): every lap's `B` holds the root's `session`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleMemberReceivesValueOnlyIfAvailable() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(session: Session, aBuilder: Instantiator<A>) {
				        self.session = session
				        self.aBuilder = aBuilder
				    }
				    @Instantiated let session: Session
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
				"Session.swift": """
				@Instantiable
				public final class Session: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Instantiated let bBuilder: Instantiator<B>
				    public var marker = ""
				}
				""",
				"B.swift": """
				@Instantiable
				public final class B: Instantiable, Marked {
				    public init(session: Session?, aBuilder: Instantiator<A>) {
				        self.session = session
				        self.aBuilder = aBuilder
				    }
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(session: { marked(Session(), \"session\") }, aBuilder: .init(bBuilder: .init({ marked(B(session: $0, aBuilder: $1), \"a.b\") }), { marked(A(bBuilder: $0), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(session: { marked(Session(), \"session\") }, aBuilder: .init(bBuilder: .init({ marked(B(session: $0, aBuilder: $1), \"a.b\") }), { marked(A(bBuilder: $0), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["session", "a", "a.b"],
		)
	}

	/// `B`, on the cycle of `B` and `C`, receives `session` only if available, and its one variant is built where nothing
	/// declares `session` (beneath `Root`) and where `A` does: each lap's `B` holds `nil` or the `session` its own `A` built.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleMemberReceivesValueOnlyIfAvailableWhereOnlySomePathsDeclareIt() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(bBuilder: Instantiator<B>, aBuilder: Instantiator<A>) {
				        self.bBuilder = bBuilder
				        self.aBuilder = aBuilder
				    }
				    @Instantiated let bBuilder: Instantiator<B>
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
				"Session.swift": """
				@Instantiable
				public final class Session: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(session: Session, bBuilder: Instantiator<B>) {
				        self.session = session
				        self.bBuilder = bBuilder
				    }
				    @Instantiated let session: Session
				    @Instantiated let bBuilder: Instantiator<B>
				    public var marker = ""
				}
				""",
				"B.swift": """
				@Instantiable
				public final class B: Instantiable, Marked {
				    public init(session: Session?, cBuilder: Instantiator<C>) {
				        self.session = session
				        self.cBuilder = cBuilder
				    }
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Instantiated let cBuilder: Instantiator<C>
				    public var marker = ""
				}
				""",
				"C.swift": """
				@Instantiable
				public final class C: Instantiable, Marked {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Instantiated let bBuilder: Instantiator<B>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.partitionOverrides)).bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.partitionOverrides)).aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: \(Self.partitionOverrides)).aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["b", "a", "a.session", "a.b"],
		)
	}

	/// `Root` builds `b` by value, and `A`, on the cycle `b` closes, builds it again as a `LazilyInstantiated`: one cycle
	/// identity built both ways, a twin (`cycleVariantsPartitionApart`).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleIdentityIsBuiltLazilyAndByValue() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(b: B) { self.b = b }
				    @Instantiated let b: B
				    public var marker = ""
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(b: LazilyInstantiated<B>) { self.b = b }
				    @Instantiated let b: LazilyInstantiated<B>
				    public var marker = ""
				}
				""",
				"B.swift": """
				@Instantiable
				public final class B: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().b.aBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().b.aBuilder.instantiate().b.instance.aBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().b.aBuilder.instantiate().b.instance.aBuilder.instantiate().b.instance.aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.b.aBuilder.instantiate().b.instance.aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(b: .init({ marked(B(aBuilder: $0), \"b\") }))).b.aBuilder.instantiate().b.instance.aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.b.aBuilder.instantiate().b.instance.aBuilder.instantiate().b.instance.aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(b: .init({ marked(B(aBuilder: $0), \"b\") }))).b.aBuilder.instantiate().b.instance.aBuilder.instantiate().b.instance.aBuilder.instantiate()"),
			],
			markers: ["b"],
		)
	}

	/// `B` is built in a `@Sendable` function, from which the call that closes the cycle refers to `A`'s function, so the
	/// places a lap enters are handed through a `@Sendable` function.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleClosesInsideSendableFunction() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(bBuilder: SendableInstantiator<B>) { self.bBuilder = bBuilder }
				    @Instantiated let bBuilder: SendableInstantiator<B>
				    public var marker = ""
				}
				""",
				"B.swift": """
				@Instantiable
				public final class B: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), { marked(A(bBuilder: $0), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), { marked(A(bBuilder: $0), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
			],
			markers: ["a", "a.b"],
		)
	}

	/// `Node`, closed on through its own `Instantiator`, is a child of `Host`'s level named apart from the `node` its
	/// sibling `Peer` receives, so its function is `__safeDI_node_Node`, which the call that closes the cycle names; it
	/// takes no parameter for `node`, its own label. `Node` also declares `token`, which nothing fulfills.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleClosesOnRootChildNamedApart() async throws {
		try await expectWalksValues(
			fixture: [
				"Host.swift": """
				@Instantiable(generateMock: true)
				public final class Host: Instantiable, Marked {
				    public init(node: Node, peer: Peer) {
				        self.node = node
				        self.peer = peer
				    }
				    @Instantiated let node: Node
				    @Received let peer: Peer
				    public var marker = ""
				}
				""",
				"Node.swift": """
				@Instantiable
				public final class Node: Instantiable, Marked {
				    public init(loopBuilder: Instantiator<Loop>, token: Token?) {
				        self.loopBuilder = loopBuilder
				        self.token = token
				    }
				    @Instantiated let loopBuilder: Instantiator<Loop>
				    @Instantiated(onlyIfAvailable: true) let token: Token?
				    public var marker = ""
				}
				""",
				"Loop.swift": """
				@Instantiable
				public final class Loop: Instantiable, Marked {
				    public init(node: Node) {
				        self.node = node
				    }
				    @Instantiated let node: Node
				    public var marker = ""
				}
				""",
				"Peer.swift": """
				@Instantiable
				public final class Peer: Instantiable, Marked {
				    public init(node: Other) {
				        self.node = node
				    }
				    @Received let node: Other
				    public var marker = ""
				}
				""",
				"Other.swift": """
				@Instantiable
				public final class Other: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}

				public final class Token: Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Host.mock().node.loopBuilder.instantiate().node.loopBuilder.instantiate().node"),
				DifferentialValueProbe("Host.mock().peer"),
				DifferentialValueProbe(name: "overridden.node.loopBuilder.instantiate().node.loopBuilder.instantiate().node", expression: "Host.mock(safeDIOverrides: \(Self.namedApartOverrides)).node.loopBuilder.instantiate().node.loopBuilder.instantiate().node"),
				DifferentialValueProbe(name: "overridden.peer", expression: "Host.mock(safeDIOverrides: \(Self.namedApartOverrides)).peer"),
			],
			markers: ["node", "loop", "other", "token"],
		)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// Overrides of each of the three places of the ring two entries give `Root`'s mock.
	private static let ringOverrides = ".init(parentBuilder: .init({ marked(Parent(childBuilder: $0), \"parent\") }), childBuilder: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), \"child.parent\") }), { marked(Child(parentBuilder: $0), \"child\") }))"

	/// Overrides of the places of `B` beneath `Root` and beneath `A`, and of `A` and its `session`.
	private static let partitionOverrides = #".init(bBuilder: .init({ marked(B(session: $0, cBuilder: $1), "b") }), aBuilder: .init(session: { marked(Session(), "a.session") }, bBuilder: .init({ marked(B(session: $0, cBuilder: $1), "a.b") }), { marked(A(session: $0, bBuilder: $1), "a") }))"#

	/// Overrides of the `session` `Root`, `Hub` and the first lap's `Step` each declare.
	private static let parameterOverrides = #".init(session: { marked(Session(), "session") }, screenBuilder: .init(midBuilder: .init(stepBuilder: .init(session: { marked(Session(), "step.session") }))), hubBuilder: .init(session: { marked(Session(), "hub.session") }))"#

	/// Overrides of `Host`'s `node`, which every lap's `Node` reads, its `Loop`, the `Other` `Peer` receives, and `token`.
	private static let namedApartOverrides = #".init(node_Node: .init(loopBuilder: .init({ marked(Loop(node: $0), "loop") }), { marked(Node(loopBuilder: $0, token: $1), "node") }), node_Other: { marked(Other(), "other") }, token: marked(Token(), "token"))"#

	private static let markedFile = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}
	"""

	/// Generates `fixture` with the walk and with the mock roots laid out from node records, expects the mock root to be
	/// laid out from them, and compares what each probe builds in the two.
	/// `cycleParameters` is what the facts answer for each function a cycle closes on, by the type it builds, which the
	/// stand-in for the cycle parameter fact reads (`CycleParametersForTesting`) until that fact lands.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectWalksValues(fixture: [String: String], probes: [DifferentialValueProbe], markers: [String], cycleParameters: [String: [Property]] = [:]) async throws {
		var fixtureFiles = fixture
		fixtureFiles["Marked.swift"] = Self.markedFile
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await CycleParametersForTesting.$byTypeName.withValue(cycleParameters) {
			try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [[]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: probes,
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built.
		for marker in markers {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	private static func layingOutMockRoots<Output>(
		filesToDelete: inout [URL],
		_ body: (inout [URL]) async throws -> Output,
	) async throws -> (Output, [NodeRecordsReport]) {
		let (stream, continuation) = AsyncStream.makeStream(of: NodeRecordsReport.self)
		var filesMade = [URL]()
		defer { filesToDelete += filesMade }
		let output = try await NodeRecordsObservation.$laysOutMockRoots.withValue(true) {
			try await NodeRecordsObservation.$observer.withValue({ continuation.yield($0) }) {
				try await body(&filesMade)
			}
		}
		continuation.finish()
		var reports = [NodeRecordsReport]()
		for await report in stream {
			reports.append(report)
		}
		return (output, reports.sorted { $0.root < $1.root })
	}
}
