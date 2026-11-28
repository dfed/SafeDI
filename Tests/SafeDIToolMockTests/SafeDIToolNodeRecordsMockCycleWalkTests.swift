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

	/// The root builds `Other` before `aBuilder`, so the body that names `Leaf`’s `aBuilder` apart is read before the body
	/// that keeps its name: the function takes the name apart in both, in whichever order the bodies are read.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTheBodyThatNamesAVariantsFunctionApartIsReadBeforeTheOneThatKeepsItsName() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(other: Other, aBuilder: Instantiator<A>) {
				        self.other = other
				        self.aBuilder = aBuilder
				    }
				    @Instantiated let other: Other
				    @Instantiated let aBuilder: Instantiator<A>
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
				DifferentialValueProbe(name: "overridden.other", expression: "Root.mock(safeDIOverrides: .init(other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }), aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }))).other"),
				DifferentialValueProbe(name: "overridden.other.aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }), aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }))).other.aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }), aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(other: .init(aBuilder: { marked(Leaf(), \"other.leaf\") }, { marked(Other(aBuilder: $0), \"other\") }), aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), aBuilder: { marked(Leaf(), \"a.leaf\") }, { marked(A(bBuilder: $0, aBuilder: $1), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
			],
			markers: ["a", "a.b", "a.leaf", "other", "other.leaf"],
		)
	}

	/// `A`’s body names `Leaf`’s `aBuilder` apart, `__safeDI_aBuilder_Leaf`, which is the name of the function `Other`’s body,
	/// which keeps `Leaf`’s under its label, declares for its `aBuilder_Leaf`: one place cannot take the name apart in
	/// both, so the walk writes the mock (`cycleBuilderNameShared`).
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isWrittenByTheWalk_whenANameApartMeetsAnotherFunctionOfTheBodyThatKeepsTheVariantsName() async throws {
		var fixture = [
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
			    public init(aBuilder: Instantiator<Leaf>, aBuilder_Leaf: Instantiator<Twig>) {
			        self.aBuilder = aBuilder
			        self.aBuilder_Leaf = aBuilder_Leaf
			    }
			    @Instantiated let aBuilder: Instantiator<Leaf>
			    @Instantiated let aBuilder_Leaf: Instantiator<Twig>
			    public var marker = ""
			}
			""",
			"Twig.swift": """
			@Instantiable
			public final class Twig: Instantiable, Marked {
			    public init() {}
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
		]
		fixture["Marked.swift"] = Self.markedFile
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { [fixture] filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["cycleBuilderNameShared"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
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
	/// identity built both ways, whose lazy call closes the cycle on the place by value above it, as today’s tree closes it.
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

	/// The root's own child is built in a `@Sendable` function, which is handed the places `mock()` holds with none entered,
	/// and the call that closes the cycle is made from a function that function calls.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenRootEntersCycleAtSendableFunction() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: SendableInstantiator<A>
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
				    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: SendableInstantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), { marked(A(bBuilder: $0), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["a", "a.b"],
		)
	}

	/// Every function on the cycle is `@Sendable`, and each hands the places on.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryFunctionOnCycleIsSendable() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: SendableInstantiator<A>
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
				    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: SendableInstantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), { marked(A(bBuilder: $0), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["a", "a.b"],
		)
	}

	/// `B`, built in a `@Sendable` function on the cycle, builds `Mid` in a function of its own and a `Leaf` in place, and `A`,
	/// whose function that one calls, builds a `Leaf` through a builder and a `Mid` by value: each is handed its override of
	/// the configuration its parent was handed with the places. `Mid` builds a `Leaf` too, so that node has a parent that
	/// takes the places and one that takes none. The places hold `A`'s configuration, which holds `Mid`'s: both are of the
	/// `Sendable` form, since a `@Sendable` function builds `A` where the cycle closes.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenFunctionsOnCycleThatClosesInsideSendableFunctionBuildChildrenOffIt() async throws {
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
				    public init(bBuilder: SendableInstantiator<B>, leafBuilder: Instantiator<Leaf>, mid: Mid) {
				        self.bBuilder = bBuilder
				        self.leafBuilder = leafBuilder
				        self.mid = mid
				    }
				    @Instantiated let bBuilder: SendableInstantiator<B>
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				    @Instantiated let mid: Mid
				    public var marker = ""
				}
				""",
				"B.swift": """
				@Instantiable
				public final class B: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>, midBuilder: Instantiator<Mid>, leaf: Leaf) {
				        self.aBuilder = aBuilder
				        self.midBuilder = midBuilder
				        self.leaf = leaf
				    }
				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let midBuilder: Instantiator<Mid>
				    @Instantiated let leaf: Leaf
				    public var marker = ""
				}
				""",
				"Mid.swift": """
				@Instantiable
				public final class Mid: Instantiable, Marked {
				    public init(leaf: Leaf) { self.leaf = leaf }
				    @Instantiated let leaf: Leaf
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
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init(midBuilder: .init(leaf: { marked(Leaf(), \"a.b.mid.leaf\") }, { marked(Mid(leaf: $0), \"a.b.mid\") }), leaf: { marked(Leaf(), \"a.b.leaf\") }, { marked(B(aBuilder: $0, midBuilder: $1, leaf: $2), \"a.b\") }), leafBuilder: { marked(Leaf(), \"a.leaf\") }, mid: .init(leaf: { marked(Leaf(), \"a.mid.leaf\") }, { marked(Mid(leaf: $0), \"a.mid\") }), { marked(A(bBuilder: $0, leafBuilder: $1, mid: $2), \"a\") }))).aBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init(midBuilder: .init(leaf: { marked(Leaf(), \"a.b.mid.leaf\") }, { marked(Mid(leaf: $0), \"a.b.mid\") }), leaf: { marked(Leaf(), \"a.b.leaf\") }, { marked(B(aBuilder: $0, midBuilder: $1, leaf: $2), \"a.b\") }), leafBuilder: { marked(Leaf(), \"a.leaf\") }, mid: .init(leaf: { marked(Leaf(), \"a.mid.leaf\") }, { marked(Mid(leaf: $0), \"a.mid\") }), { marked(A(bBuilder: $0, leafBuilder: $1, mid: $2), \"a\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["a", "a.b", "a.b.mid", "a.b.mid.leaf", "a.b.leaf", "a.leaf", "a.mid", "a.mid.leaf"],
		)
	}

	/// `S`, on no cycle, is built in a `@Sendable` function, which reads its override of a local and hands `A`, on the cycle,
	/// the places `mock()` holds with none entered and a field of that local. `A` builds `Mid` off the cycle, in a function
	/// of its own.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenSendableFunctionOnNoCycleBuildsCycle() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(sBuilder: SendableInstantiator<S>) { self.sBuilder = sBuilder }
				    @Instantiated let sBuilder: SendableInstantiator<S>
				    public var marker = ""
				}
				""",
				"S.swift": """
				@Instantiable
				public final class S: Instantiable, Marked {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(bBuilder: Instantiator<B>, mid: Mid) {
				        self.bBuilder = bBuilder
				        self.mid = mid
				    }
				    @Instantiated let bBuilder: Instantiator<B>
				    @Instantiated let mid: Mid
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
				"Mid.swift": """
				@Instantiable
				public final class Mid: Instantiable, Marked {
				    public init(leaf: Leaf) { self.leaf = leaf }
				    @Instantiated let leaf: Leaf
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
				DifferentialValueProbe("Root.mock().sBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().sBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.sBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(sBuilder: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"s.a.b\") }), mid: .init(leaf: { marked(Leaf(), \"s.a.mid.leaf\") }, { marked(Mid(leaf: $0), \"s.a.mid\") }), { marked(A(bBuilder: $0, mid: $1), \"s.a\") }), { marked(S(aBuilder: $0), \"s\") }))).sBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.sBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(sBuilder: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"s.a.b\") }), mid: .init(leaf: { marked(Leaf(), \"s.a.mid.leaf\") }, { marked(Mid(leaf: $0), \"s.a.mid\") }), { marked(A(bBuilder: $0, mid: $1), \"s.a\") }), { marked(S(aBuilder: $0), \"s\") }))).sBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["s", "s.a", "s.a.b", "s.a.mid", "s.a.mid.leaf"],
		)
	}

	/// `First`'s `A` is on no cycle and is built in a `@Sendable` function, which enters the nearest place of its type for
	/// the `A` the cycle beneath it builds: it takes the places, so it reads its configuration of them and no local.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenSendableFunctionOnNoCycleEntersNearestPlaceOfItsType() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(first: SendableInstantiator<A>) { self.first = first }
				    @Instantiated let first: SendableInstantiator<A>
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
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().first.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.first.instantiate()", expression: "Root.mock(safeDIOverrides: .init(first: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"first.b\") }), { marked(A(bBuilder: $0), \"first\") }))).first.instantiate()"),
				DifferentialValueProbe(name: "overridden.first.instantiate().bBuilder.instantiate().aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(first: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"first.b\") }), { marked(A(bBuilder: $0), \"first\") }))).first.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
			],
			markers: ["first", "first.b"],
		)
	}

	/// `P` is on no cycle and built in a function that is not `@Sendable`, and it enters the cycle at `A`, which a
	/// `@Sendable` function builds: that function cannot capture `P`'s configuration, which is not of the `Sendable` form,
	/// so `P`'s body binds `A`'s configuration to a local before it and hands the places that local.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenFunctionOnNoCycleEntersCycleAtSendableFunction() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(p: P) { self.p = p }
				    @Instantiated let p: P
				    public var marker = ""
				}
				""",
				"P.swift": """
				@Instantiable
				public final class P: Instantiable, Marked {
				    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: SendableInstantiator<A>
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
				    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: SendableInstantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().p.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.p", expression: "Root.mock(safeDIOverrides: .init(p: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"p.a.b\") }), { marked(A(bBuilder: $0), \"p.a\") }), { marked(P(aBuilder: $0), \"p\") }))).p"),
				DifferentialValueProbe(name: "overridden.p.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(p: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"p.a.b\") }), { marked(A(bBuilder: $0), \"p.a\") }), { marked(P(aBuilder: $0), \"p\") }))).p.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
			],
			markers: ["p", "p.a", "p.a.b"],
		)
	}

	/// The mock's own overrides are not `Sendable`, since they hold a value it receives only if available, and the root's
	/// body enters the cycle at `A`, which a `@Sendable` function builds: the body binds `A`'s configuration to a local
	/// before that function, which captures the local and not the overrides.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenRootWhoseOverridesAreNotSendableEntersCycleAtSendableFunction() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(aBuilder: SendableInstantiator<A>, thing: Thing?) {
				        self.aBuilder = aBuilder
				        self.thing = thing
				    }
				    @Instantiated let aBuilder: SendableInstantiator<A>
				    @Received(onlyIfAvailable: true) let thing: Thing?
				    public var marker = ""
				}
				""",
				"Thing.swift": """
				public final class Thing {
				    public init() {}
				    public var count = 0
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
				    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: SendableInstantiator<A>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(bBuilder: .init({ marked(B(aBuilder: $0), \"a.b\") }), { marked(A(bBuilder: $0), \"a\") }), thing: Thing())).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate()"),
			],
			markers: ["a", "a.b"],
		)
	}

	/// `X` and `Y` are on a cycle of their own that no `@Sendable` function builds, so their configurations are not of the
	/// `Sendable` form, which the places `A` and `B`'s cycle makes `Sendable` could not hold: the walk writes the mock.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isWrittenByTheWalk_whenAnotherCycleOfTheMockIsBuiltOutsideEverySendableFunction() async throws {
		let fixture = [
			"Marked.swift": Self.markedFile,
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Marked {
			    public init(aBuilder: Instantiator<A>, xBuilder: Instantiator<X>) {
			        self.aBuilder = aBuilder
			        self.xBuilder = xBuilder
			    }
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let xBuilder: Instantiator<X>
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
			"X.swift": """
			@Instantiable
			public final class X: Instantiable, Marked {
			    public init(yBuilder: Instantiator<Y>) { self.yBuilder = yBuilder }
			    @Instantiated let yBuilder: Instantiator<Y>
			    public var marker = ""
			}
			""",
			"Y.swift": """
			@Instantiable
			public final class Y: Instantiable, Marked {
			    public init(xBuilder: Instantiator<X>) { self.xBuilder = xBuilder }
			    @Instantiated let xBuilder: Instantiator<X>
			    public var marker = ""
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { [fixture] filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["sendable"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	/// `A` instantiates `token` only if available, which nothing fulfills, so `mock()` takes an override of it, and `B`
	/// builds `A` again in a `@Sendable` function, which could not capture the override: the walk, which binds `token` to
	/// `nil` there and to the override in the `A` the root builds, writes the mock.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isWrittenByTheWalk_whenTypeOnCycleBuiltInSendableFunctionReadsOverrideOfValueNothingFulfills() async throws {
		let fixture = [
			"Marked.swift": Self.markedFile,
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
			    public init(bBuilder: Instantiator<B>, token: Token?) {
			        self.bBuilder = bBuilder
			        self.token = token
			    }
			    @Instantiated let bBuilder: Instantiator<B>
			    @Instantiated(onlyIfAvailable: true) let token: Token?
			    public var marker = ""
			}

			public final class Token: Marked {
			    public init() {}
			    public var marker = ""
			}
			""",
			"B.swift": """
			@Instantiable
			public final class B: Instantiable, Marked {
			    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
			    @Instantiated let aBuilder: SendableInstantiator<A>
			    public var marker = ""
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { [fixture] filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["sendable"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	/// The root's body would bind the configuration it hands `A`'s `@Sendable` function to `__safeDI_aBuilder__overrides`,
	/// the name of the function that builds the root's `aBuilder__overrides`: the walk, which names its local apart,
	/// writes the mock.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isWrittenByTheWalk_whenFunctionTakesNameOfLocalRootBindsForSendableFunctionOnCycle() async throws {
		let fixture = [
			"Marked.swift": Self.markedFile,
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Marked {
			    public init(aBuilder: SendableInstantiator<A>, aBuilder__overrides: Leaf) {
			        self.aBuilder = aBuilder
			        self.aBuilder__overrides = aBuilder__overrides
			    }
			    @Instantiated let aBuilder: SendableInstantiator<A>
			    @Instantiated let aBuilder__overrides: Leaf
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
			    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
			    @Instantiated let aBuilder: SendableInstantiator<A>
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
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { [fixture] filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["sendable"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
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

	/// `Root` and `Mid` each build `A` through an `ErasedInstantiator`, and `Mid`, between `A` and the call that closes the
	/// cycle on it, declares the `token` `A` receives: `A`’s function takes `token` and returns the erased type, as its
	/// override does, so no call wraps what it returns again.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenErasedInstantiatorClosesCycleOnFunctionThatTakesParameter() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(token: Token, aBuilder: ErasedInstantiator<(), AnyA>) {
				        self.token = token
				        self.aBuilder = aBuilder
				    }
				    @Instantiated let token: Token
				    @Instantiated(fulfilledByType: "A", erasedToConcreteExistential: true) let aBuilder: ErasedInstantiator<(), AnyA>
				    public var marker = ""
				}

				public final class AnyA {
				    public init(_ a: A) { self.a = a }
				    public let a: A
				}
				""",
				"A.swift": """
				@Instantiable
				public final class A: Instantiable, Marked {
				    public init(token: Token, midBuilder: Instantiator<Mid>) {
				        self.token = token
				        self.midBuilder = midBuilder
				    }
				    @Received let token: Token
				    @Instantiated let midBuilder: Instantiator<Mid>
				    public var marker = ""
				}
				""",
				"Mid.swift": """
				@Instantiable
				public final class Mid: Instantiable, Marked {
				    public init(token: Token, aBuilder: ErasedInstantiator<(), AnyA>) {
				        self.token = token
				        self.aBuilder = aBuilder
				    }
				    @Instantiated let token: Token
				    @Instantiated(fulfilledByType: "A", erasedToConcreteExistential: true) let aBuilder: ErasedInstantiator<(), AnyA>
				    public var marker = ""
				}
				""",
				"Token.swift": """
				@Instantiable
				public final class Token: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
			],
			probes: [
				// An `ErasedInstantiator` is not traversed, so each probe calls the builders itself.
				DifferentialValueProbe("Root.mock().aBuilder.instantiate()"),
				DifferentialValueProbe(name: "the second lap’s token is its mid’s", expression: "{ () -> Bool in let mid = Root.mock().aBuilder.instantiate().a.midBuilder.instantiate(); return mid.aBuilder.instantiate().a.token === mid.token }()"),
				DifferentialValueProbe(name: "overridden", expression: #"{ () -> (Token, Mid, AnyA) in let root = Root.mock(safeDIOverrides: .init(token: { marked(Token(), "token") }, aBuilder: .init(midBuilder: .init(token: { marked(Token(), "mid.token") }), { marked(A(token: $0, midBuilder: $1), "a") }))); let mid = root.aBuilder.instantiate().a.midBuilder.instantiate(); return (root.token, mid, mid.aBuilder.instantiate()) }()"#),
			],
			markers: ["token", "mid.token", "a"],
		)
	}

	/// `Root` builds `editor` by value, and `Preview`, which `Editor` builds, builds it again as a `LazilyInstantiated`:
	/// the lazy call closes the cycle on the place by value above it. `Preview` also declares the `theme` the editor’s
	/// `Toolbar` receives, which the walk hands the editor’s function at each call.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenLazyTwinClosesCycleOnPlaceByValueAndTypeBetweenDeclaresLabelTheCycleReceives() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(theme: Theme, editor: Editor) {
				        self.theme = theme
				        self.editor = editor
				    }
				    @Instantiated let theme: Theme
				    @Instantiated let editor: Editor
				    public var marker = ""
				}
				""",
				"Editor.swift": """
				@Instantiable
				public final class Editor: Instantiable, Marked {
				    public init(previewBuilder: Instantiator<Preview>, toolbar: Toolbar) {
				        self.previewBuilder = previewBuilder
				        self.toolbar = toolbar
				    }
				    @Instantiated let previewBuilder: Instantiator<Preview>
				    @Instantiated let toolbar: Toolbar
				    public var marker = ""
				}
				""",
				"Preview.swift": """
				@Instantiable
				public final class Preview: Instantiable, Marked {
				    public init(theme: Theme, editor: LazilyInstantiated<Editor>) {
				        self.theme = theme
				        self.editor = editor
				    }
				    @Instantiated let theme: Theme
				    @Instantiated let editor: LazilyInstantiated<Editor>
				    public var marker = ""
				}
				""",
				"Toolbar.swift": """
				@Instantiable
				public final class Toolbar: Instantiable, Marked {
				    public init(theme: Theme) { self.theme = theme }
				    @Received let theme: Theme
				    public var marker = ""
				}
				""",
				"Theme.swift": """
				@Instantiable
				public final class Theme: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "the preview’s editor’s toolbar holds the preview’s theme", expression: "{ () -> Bool in let preview = Root.mock().editor.previewBuilder.instantiate(); return preview.editor.instance.toolbar.theme === preview.theme }()"),
				DifferentialValueProbe(name: "overridden", expression: #"{ () -> (Root, Preview, Editor) in let root = Root.mock(safeDIOverrides: .init(theme: { marked(Theme(), "theme") }, editor: .init(previewBuilder: .init(theme: { marked(Theme(), "preview.theme") }, { marked(Preview(theme: $0, editor: $1), "preview") }), toolbar: { marked(Toolbar(theme: $0), "toolbar") }, { marked(Editor(previewBuilder: $0, toolbar: $1), "editor") }))); let preview = root.editor.previewBuilder.instantiate(); return (root, preview, preview.editor.instance) }()"#),
			],
			markers: ["theme", "preview.theme", "preview", "toolbar", "editor"],
		)
	}

	/// `Preview` builds `Root`’s `editor` again as a `LazilyInstantiated`, closing the cycle on the place by value, and
	/// declares the `theme` the editor’s `Toolbar` receives only if available: nothing above `Root`’s `editor` declares
	/// it, so the root’s call hands `nil` where the closing call hands the preview’s `theme`, and the function the two
	/// calls share was made from the root’s view alone. The walk writes the mock.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_isWrittenByTheWalk_whenLazyTwinClosesCycleOnPlaceByValueAndOnlyTheTwinsViewHasLabelTheCycleReceives() async throws {
		let fixture = [
			"Marked.swift": Self.markedFile,
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Marked {
			    public init(editor: Editor) { self.editor = editor }
			    @Instantiated let editor: Editor
			    public var marker = ""
			}
			""",
			"Editor.swift": """
			@Instantiable
			public final class Editor: Instantiable, Marked {
			    public init(previewBuilder: Instantiator<Preview>, toolbar: Toolbar) {
			        self.previewBuilder = previewBuilder
			        self.toolbar = toolbar
			    }
			    @Instantiated let previewBuilder: Instantiator<Preview>
			    @Instantiated let toolbar: Toolbar
			    public var marker = ""
			}
			""",
			"Preview.swift": """
			@Instantiable
			public final class Preview: Instantiable, Marked {
			    public init(theme: Theme, editor: LazilyInstantiated<Editor>) {
			        self.theme = theme
			        self.editor = editor
			    }
			    @Instantiated let theme: Theme
			    @Instantiated let editor: LazilyInstantiated<Editor>
			    public var marker = ""
			}
			""",
			"Toolbar.swift": """
			@Instantiable
			public final class Toolbar: Instantiable, Marked {
			    public init(theme: Theme?) { self.theme = theme }
			    @Received(onlyIfAvailable: true) let theme: Theme?
			    public var marker = ""
			}
			""",
			"Theme.swift": """
			@Instantiable
			public final class Theme: Instantiable, Marked {
			    public init() {}
			    public var marker = ""
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { [fixture] filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["onlyIfAvailableAnsweredApart"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	/// `Logger` receives `t3Builder` only if available, so `Home` and `T0` each build `logger` after `t3Builder`, whose
	/// function today’s mock hands `logger` as a parameter that every call passes `nil`: a function that takes no such
	/// parameter and builds each `T3` with `nil` builds the same values.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryCallPassesNilForLabelBuiltAfterTheCycle() async throws {
		try await expectWalksValues(
			fixture: [
				"Home.swift": """
				@Instantiable(generateMock: true)
				public final class Home: Instantiable, Marked {
				    public init(session: Session, logger: Logger, t3Builder: Instantiator<T3>) {
				        self.session = session
				        self.logger = logger
				        self.t3Builder = t3Builder
				    }
				    @Instantiated let session: Session
				    @Instantiated let logger: Logger
				    @Instantiated let t3Builder: Instantiator<T3>
				    public var marker = ""
				}
				""",
				"T3.swift": """
				@Instantiable
				public final class T3: Instantiable, Marked {
				    public init(session: Session?, logger: Logger?, t0Builder: Instantiator<T0>, t4Builder: Instantiator<T4>) {
				        self.session = session
				        self.logger = logger
				        self.t0Builder = t0Builder
				        self.t4Builder = t4Builder
				    }
				    @Received(onlyIfAvailable: true) let session: Session?
				    @Received(onlyIfAvailable: true) let logger: Logger?
				    @Instantiated let t0Builder: Instantiator<T0>
				    @Instantiated let t4Builder: Instantiator<T4>
				    public var marker = ""
				}
				""",
				"T0.swift": """
				@Instantiable
				public final class T0: Instantiable, Marked {
				    public init(session: Session, logger: Logger, t3Builder: Instantiator<T3>) {
				        self.session = session
				        self.logger = logger
				        self.t3Builder = t3Builder
				    }
				    @Instantiated let session: Session
				    @Instantiated let logger: Logger
				    @Instantiated let t3Builder: Instantiator<T3>
				    public var marker = ""
				}
				""",
				"T4.swift": """
				@Instantiable
				public final class T4: Instantiable, Marked {
				    public init(t3Builder: Instantiator<T3>) { self.t3Builder = t3Builder }
				    @Instantiated let t3Builder: Instantiator<T3>
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
				"Logger.swift": """
				@Instantiable
				public final class Logger: Instantiable, Marked {
				    public init(t3Builder: Instantiator<T3>?) { self.t3Builder = t3Builder }
				    @Received(onlyIfAvailable: true) let t3Builder: Instantiator<T3>?
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Home.mock()"),
				DifferentialValueProbe("Home.mock().t3Builder.instantiate()"),
				DifferentialValueProbe("Home.mock().t3Builder.instantiate().t0Builder.instantiate().t3Builder.instantiate()"),
				DifferentialValueProbe("Home.mock().t3Builder.instantiate().t4Builder.instantiate().t3Builder.instantiate()"),
				DifferentialValueProbe(name: "no lap’s T3 holds a logger", expression: "{ () -> [Bool] in let first = Home.mock().t3Builder.instantiate(); return [first.logger == nil, first.t0Builder.instantiate().t3Builder.instantiate().logger == nil, first.t4Builder.instantiate().t3Builder.instantiate().logger == nil] }()"),
			],
			markers: [],
		)
	}

	/// `First` holds `token` as a `LazilyInstantiated` and `Second` by value, and each builds, through an `Instantiator`,
	/// the `Reader` that receives it: one node of one label and type is built beneath both forms in one `mock()`, by two
	/// functions of one name that the mock names apart, and each `Reader` holds the token of the type that built it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenOneNodeIsBuiltByBuildersBeneathItsLabelHeldLazilyAndByValue() async throws {
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				@Instantiable(generateMock: true)
				public final class Root: Instantiable, Marked {
				    public init(first: First, second: Second) {
				        self.first = first
				        self.second = second
				    }
				    @Instantiated let first: First
				    @Instantiated let second: Second
				    public var marker = ""
				}
				""",
				"First.swift": """
				@Instantiable
				public final class First: Instantiable, Marked {
				    public init(token: LazilyInstantiated<Token>, readerBuilder: Instantiator<Reader>) {
				        self.token = token
				        self.readerBuilder = readerBuilder
				    }
				    @Instantiated let token: LazilyInstantiated<Token>
				    @Instantiated let readerBuilder: Instantiator<Reader>
				    public var marker = ""
				}
				""",
				"Second.swift": """
				@Instantiable
				public final class Second: Instantiable, Marked {
				    public init(token: Token, readerBuilder: Instantiator<Reader>) {
				        self.token = token
				        self.readerBuilder = readerBuilder
				    }
				    @Instantiated let token: Token
				    @Instantiated let readerBuilder: Instantiator<Reader>
				    public var marker = ""
				}
				""",
				"Reader.swift": """
				@Instantiable
				public final class Reader: Instantiable, Marked {
				    public init(token: Token) { self.token = token }
				    @Received let token: Token
				    public var marker = ""
				}
				""",
				"Token.swift": """
				@Instantiable
				public final class Token: Instantiable, Marked {
				    public init() {}
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "each reader holds the token of the type that built it", expression: "{ () -> [Bool] in let root = Root.mock(); return [root.first.readerBuilder.instantiate().token === root.first.token.instance, root.second.readerBuilder.instantiate().token === root.second.token, root.first.readerBuilder.instantiate().token !== root.second.readerBuilder.instantiate().token] }()"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(first: .init(token: { marked(Token(), "first.token") }, readerBuilder: { marked(Reader(token: $0), "first.reader") }), second: .init(token: { marked(Token(), "second.token") }, readerBuilder: { marked(Reader(token: $0), "second.reader") })))"#),
			],
			markers: ["first.token", "first.reader", "second.token", "second.reader"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeBuiltAlongEdgeConfigurationsLeaveOutTakesDefaultValuedParameter() async throws {
		// `Parent`’s configuration has no field for its child, so the walk builds each `Child` of the ring with its
		// initializer’s own default, a new `State` each time, and no override reaches one.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, state: State = State()) {
				        self.parentBuilder = parentBuilder
				        self.state = state
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    let state: State
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "each child takes a state of its own", expression: "[Root.mock().parentBuilder.instantiate()].map { $0.childBuilder.instantiate().state === $0.childBuilder.instantiate().state }"),
				DifferentialValueProbe(name: "each lap takes a state of its own", expression: "[Root.mock().parentBuilder.instantiate().childBuilder.instantiate()].map { $0.state === $0.parentBuilder.instantiate().childBuilder.instantiate().state }"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), "parent") })))"#),
			],
			markers: ["parent"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypesBeneathEdgeConfigurationsLeaveOutTakeDefaultValuedParameters() async throws {
		// `Leaf`, `Bud` and `Twig` are off the cycle and built only beneath `Child`, which the configurations leave out: the
		// walk builds each with its initializer’s own default, a new `State` for each one an instantiator builds.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, leafBuilder: Instantiator<Leaf>, twig: Twig) {
				        self.parentBuilder = parentBuilder
				        self.leafBuilder = leafBuilder
				        self.twig = twig
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    @Instantiated let leafBuilder: Instantiator<Leaf>
				    @Instantiated let twig: Twig
				    public var marker = ""
				}
				""",
				"Leaf.swift": """
				@Instantiable
				public final class Leaf: Instantiable, Marked {
				    public init(budBuilder: Instantiator<Bud>, state: State = State()) {
				        self.budBuilder = budBuilder
				        self.state = state
				    }

				    @Instantiated let budBuilder: Instantiator<Bud>
				    let state: State
				    public var marker = ""
				}

				@Instantiable
				public final class Bud: Instantiable, Marked {
				    public init(state: State = State()) {
				        self.state = state
				    }

				    let state: State
				    public var marker = ""
				}

				@Instantiable
				public final class Twig: Instantiable, Marked {
				    public init(state: State = State()) {
				        self.state = state
				    }

				    let state: State
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "each leaf takes a state of its own", expression: "[Root.mock().parentBuilder.instantiate().childBuilder.instantiate()].map { $0.leafBuilder.instantiate().state === $0.leafBuilder.instantiate().state }"),
				DifferentialValueProbe(name: "each bud takes a state of its own", expression: "[Root.mock().parentBuilder.instantiate().childBuilder.instantiate().leafBuilder.instantiate()].map { $0.budBuilder.instantiate().state === $0.budBuilder.instantiate().state }"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), "parent") })))"#),
			],
			markers: ["parent"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeBuiltAlongEdgeConfigurationsLeaveOutAndByRootTakesDefaultValuedParameter() async throws {
		// `Root` and `Parent` build one `childBuilder`. The root’s is built of the root’s configuration, whose one `State` every
		// `Child` a path from it closes on shares; the one `Parent` builds beneath the root’s `parentBuilder` is left out, and
		// takes a `State` of its own.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>, childBuilder: Instantiator<Child>) {
				        self.parentBuilder = parentBuilder
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, state: State = State()) {
				        self.parentBuilder = parentBuilder
				        self.state = state
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    let state: State
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "the root’s state", expression: "{ let state = State(); let root = Root.mock(safeDIOverrides: .init(childBuilder: .init(state: state))); return [root.childBuilder.instantiate().state === state, root.childBuilder.instantiate().parentBuilder.instantiate().childBuilder.instantiate().state === state, root.parentBuilder.instantiate().childBuilder.instantiate().state === state] }()"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), "parent") }), childBuilder: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), "child.parent") }))))"#),
			],
			markers: ["parent", "child.parent"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenCycleClosesOnTypeBuiltAlongEdgeConfigurationsLeaveOut() async throws {
		// `Child` and `Bridge` build each other beneath `Parent`, whose configuration has no field for its child, and
		// `Child`’s has none for its bridge. The `Child` a `Bridge` builds closes the cycle on the place of the `Child` above
		// it, which was entered with no configuration: the walk builds it with a new `State` too.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, bridgeBuilder: Instantiator<Bridge>, state: State = State()) {
				        self.parentBuilder = parentBuilder
				        self.bridgeBuilder = bridgeBuilder
				        self.state = state
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    @Instantiated let bridgeBuilder: Instantiator<Bridge>
				    let state: State
				    public var marker = ""
				}
				""",
				"Bridge.swift": """
				@Instantiable
				public final class Bridge: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "the child a bridge builds takes a state of its own", expression: "[Root.mock().parentBuilder.instantiate().childBuilder.instantiate()].map { $0.state === $0.bridgeBuilder.instantiate().childBuilder.instantiate().state }"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), "parent") })))"#),
			],
			markers: ["parent"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenRootBuildsTypeEdgeConfigurationsLeaveOutClosesOn() async throws {
		// `Root` builds the `Child` that `Parent`’s configuration has no field for, so the edge the configurations leave out
		// only ever closes the cycle on the root’s place: every `Child` reads the root’s configuration, and its one `State`.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, state: State = State()) {
				        self.parentBuilder = parentBuilder
				        self.state = state
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    let state: State
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "the root’s state", expression: "{ let state = State(); let child = Root.mock(safeDIOverrides: .init(childBuilder: .init(state: state))).childBuilder.instantiate(); return [child.state === state, child.parentBuilder.instantiate().childBuilder.instantiate().state === state] }()"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(childBuilder: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), "child.parent") }))))"#),
			],
			markers: ["child.parent"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeBeneathEdgeConfigurationsLeaveOutBuildsCyclesTypeThroughAnotherProperty() async throws {
		// `Child`, which the configurations leave out, builds `Parent` through `spareBuilder` too, a second property of the
		// type `Root`’s `parentBuilder` builds: the walk’s function for the spare `Parent` reads the overrides of the
		// `Parent` above it, so both hold that configuration’s `state` and its override builds both.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>, state: State = State()) {
				        self.childBuilder = childBuilder
				        self.state = state
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    let state: State
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, spareBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				        self.spareBuilder = spareBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    @Instantiated let spareBuilder: Instantiator<Parent>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "the spare parent holds the state of the parent above it", expression: "[Root.mock().parentBuilder.instantiate()].map { parent in parent.childBuilder.instantiate().spareBuilder.instantiate().state === parent.state }"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0, state: $1), "parent") })))"#),
				DifferentialValueProbe(name: "the spare parent is the overridden one too", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0, state: $1), "parent") }))).parentBuilder.instantiate().childBuilder.instantiate().spareBuilder.instantiate()"#),
			],
			markers: ["parent"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeBeneathEdgeConfigurationsLeaveOutHoldsCyclesTypeByValue() async throws {
		// `Holder`, beneath the `Child` the configurations leave out, holds a `Parent` by value, of the type `Root`’s
		// `parentBuilder` builds: the walk builds `Holder` with no override, and its `Parent` and that `Parent`’s `Twig`s
		// with the overrides of the `Parent` above, so every `Twig` holds that configuration’s one `State`.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>, twigBuilder: Instantiator<Twig>) {
				        self.childBuilder = childBuilder
				        self.twigBuilder = twigBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    @Instantiated let twigBuilder: Instantiator<Twig>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, holder: Holder) {
				        self.parentBuilder = parentBuilder
				        self.holder = holder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    @Instantiated let holder: Holder
				    public var marker = ""
				}

				@Instantiable
				public final class Holder: Instantiable, Marked {
				    public init(parent: Parent) {
				        self.parent = parent
				    }

				    @Instantiated let parent: Parent
				    public var marker = ""
				}

				@Instantiable
				public final class Twig: Instantiable, Marked {
				    public init(state: State = State()) {
				        self.state = state
				    }

				    let state: State
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "the twigs of the held parent hold one state", expression: "[Root.mock().parentBuilder.instantiate().childBuilder.instantiate().holder.parent].map { $0.twigBuilder.instantiate().state === $0.twigBuilder.instantiate().state }"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init(twigBuilder: .init({ marked(Twig(state: $0), "twig") }), { marked(Parent(childBuilder: $0, twigBuilder: $1), "parent") })))"#),
				DifferentialValueProbe(name: "the held parent is the overridden one too", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init(twigBuilder: .init({ marked(Twig(state: $0), "twig") }), { marked(Parent(childBuilder: $0, twigBuilder: $1), "parent") }))).parentBuilder.instantiate().childBuilder.instantiate().holder"#),
			],
			markers: ["parent", "twig"],
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeBeneathEdgeConfigurationsLeaveOutEntersAnotherCycle() async throws {
		// `Child`, which the configurations leave out, holds a `Ring` by value, and `Ring` and `Link` are a cycle of their
		// own beneath it: no `Ring` above was entered with a configuration, so the walk builds each `Ring` a `Link`
		// instantiates with its initializer’s own default, a new `State` each time.
		try await expectWalksValues(
			fixture: [
				"Root.swift": """
				public final class State {
				    public init() {}
				}

				@Instantiable(generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				}
				""",
				"Parent.swift": """
				@Instantiable
				public final class Parent: Instantiable, Marked {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				    public var marker = ""
				}
				""",
				"Child.swift": """
				@Instantiable
				public final class Child: Instantiable, Marked {
				    public init(parentBuilder: Instantiator<Parent>, ring: Ring) {
				        self.parentBuilder = parentBuilder
				        self.ring = ring
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				    @Instantiated let ring: Ring
				    public var marker = ""
				}
				""",
				"Ring.swift": """
				@Instantiable
				public final class Ring: Instantiable, Marked {
				    public init(linkBuilder: Instantiator<Link>, state: State = State()) {
				        self.linkBuilder = linkBuilder
				        self.state = state
				    }

				    @Instantiated let linkBuilder: Instantiator<Link>
				    let state: State
				    public var marker = ""
				}

				@Instantiable
				public final class Link: Instantiable, Marked {
				    public init(ringBuilder: Instantiator<Ring>) {
				        self.ringBuilder = ringBuilder
				    }

				    @Instantiated let ringBuilder: Instantiator<Ring>
				    public var marker = ""
				}
				""",
			],
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "each ring a link builds takes a state of its own", expression: "[Root.mock().parentBuilder.instantiate().childBuilder.instantiate().ring].map { ring in [ring.linkBuilder.instantiate()].map { [$0.ringBuilder.instantiate().state === ring.state, $0.ringBuilder.instantiate().state === $0.ringBuilder.instantiate().state] } }"),
				DifferentialValueProbe(name: "overridden", expression: #"Root.mock(safeDIOverrides: .init(parentBuilder: .init({ marked(Parent(childBuilder: $0), "parent") })))"#),
			],
			markers: ["parent"],
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
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectWalksValues(fixture: [String: String], probes: [DifferentialValueProbe], markers: [String]) async throws {
		var fixtureFiles = fixture
		fixtureFiles["Marked.swift"] = Self.markedFile
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixtureFiles, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
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
			try await NodeRecordsObservation.$observer.withValue(TaskLocalFunction { continuation.yield($0) }) {
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
