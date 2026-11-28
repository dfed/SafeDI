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

/// An internal mock root whose children receive one label as two types, laid out from the node records of its world
/// (`NodeRecords+MockOverrideNotParentField.swift`). `mock()` binds each value under a name that carries its type, and
/// the function of each node that receives the label binds it again under the label, from the name of its type.
struct SafeDIToolNodeRecordsMockOverrideNotParentFieldTests: ~Copyable {
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
	mutating func mock_bindsLabelAgainInEachReceiversFunction_whenRootNamesTwoTypesOfOneLabelApart() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// Each value named apart is bound by `mock()` under its name, and read by that name in the first line of the
		// function of each node that receives its label: in a function handed its configuration, and in the one an
		// `Instantiator` of the root calls.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            thing_Thing: (() -> Thing)? = nil,
		            thing_Instantiator__Thing: (() -> Thing)? = nil,
		            leaf: Leaf.SafeDIMockConfiguration = .init(),
		            secondBuilder: ((Instantiator<Thing>) -> Second)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                thing_Thing: thing_Thing,
		                thing_Instantiator__Thing: thing_Instantiator__Thing,
		                leaf: leaf,
		                secondBuilder: secondBuilder
		            )
		        }

		        var thing_Thing: (() -> Thing)? { __safeDI_storage.thing_Thing }
		        var thing_Instantiator__Thing: (() -> Thing)? { __safeDI_storage.thing_Instantiator__Thing }
		        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
		        var secondBuilder: ((Instantiator<Thing>) -> Second)? { __safeDI_storage.secondBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                thing_Thing: (() -> Thing)?,
		                thing_Instantiator__Thing: (() -> Thing)?,
		                leaf: Leaf.SafeDIMockConfiguration,
		                secondBuilder: ((Instantiator<Thing>) -> Second)?
		            ) {
		                self.thing_Thing = thing_Thing
		                self.thing_Instantiator__Thing = thing_Instantiator__Thing
		                self.leaf = leaf
		                self.secondBuilder = secondBuilder
		            }

		            let thing_Thing: (() -> Thing)?
		            let thing_Instantiator__Thing: (() -> Thing)?
		            let leaf: Leaf.SafeDIMockConfiguration
		            let secondBuilder: ((Instantiator<Thing>) -> Second)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let thing_Thing = if let safeDIBuilder = safeDIOverrides.thing_Thing { safeDIBuilder() } else { Thing() }
		        func __safeDI_thing_Instantiator__Thing() -> Thing {
		            if let safeDIBuilder = safeDIOverrides.thing_Instantiator__Thing { safeDIBuilder() } else { Thing() }
		        }
		        let thing_Instantiator__Thing = Instantiator<Thing>(__safeDI_thing_Instantiator__Thing)
		        func __safeDI_first(safeDIOverrides: ((Thing) -> First)?) -> First {
		            let thing: Thing = thing_Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { First(thing: thing) }
		        }
		        func __safeDI_second(safeDIOverrides: ((Instantiator<Thing>) -> Second)?) -> Second {
		            let thing: Instantiator<Thing> = thing_Instantiator__Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { Second(thing: thing) }
		        }
		        func __safeDI_leaf(safeDIOverrides: Leaf.SafeDIMockConfiguration) -> Leaf {
		            let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		            let second: Second = __safeDI_second(safeDIOverrides: safeDIOverrides.second)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(first, second) } else { Leaf(first: first, second: second) }
		        }
		        let leaf: Leaf = __safeDI_leaf(safeDIOverrides: safeDIOverrides.leaf)
		        func __safeDI_secondBuilder() -> Second {
		            let thing: Instantiator<Thing> = thing_Instantiator__Thing
		            return if let safeDIBuilder = safeDIOverrides.secondBuilder { safeDIBuilder(thing) } else { Second(thing: thing) }
		        }
		        let secondBuilder = Instantiator<Second>(__safeDI_secondBuilder)
		        return Root(leaf: leaf, secondBuilder: secondBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryPlaceOfTreeNamedApartIsOverridden() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let overridden = """
		Root.mock(safeDIOverrides: .init(\
		thing_Thing: { marked(Thing(), "thing_Thing") }, \
		thing_Instantiator__Thing: { marked(Thing(), "thing_Instantiator__Thing") }, \
		leaf: .init(first: { marked(First(thing: $0), "leaf.first") }, second: { marked(Second(thing: $0), "leaf.second") }, { marked(Leaf(first: $0, second: $1), "leaf") }), \
		secondBuilder: { marked(Second(thing: $0), "secondBuilder") }))
		"""
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: Self.fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: Self.fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().leaf.second.thing.instantiate()"),
				DifferentialValueProbe("Root.mock().secondBuilder.instantiate().thing.instantiate()"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden value of the constant’s instantiator", expression: "\(overridden).leaf.second.thing.instantiate()"),
				DifferentialValueProbe(name: "overridden instantiator", expression: "\(overridden).secondBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden value of the instantiator’s instantiator", expression: "\(overridden).secondBuilder.instantiate().thing.instantiate()"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built.
		for marker in ["thing_Thing", "thing_Instantiator__Thing", "leaf.first", "leaf.second", "leaf", "secondBuilder"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutNodesBesideDeclarationOfTheLabel_whenNodeBelowRootBuildsLabelNamedApart() async throws {
		// `Inner` builds a third `thing` of its own, which its child receives: that declaration hides the names the root
		// binds apart from `User`, which reads `Inner`'s `thing`, as the walk hands it.
		let fixture = Self.fixture.merging(Self.fixtureOfLabelBuiltBelowRoot) { $1 }
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            thing_Thing: (() -> Thing)? = nil,
		            thing_Instantiator__Thing: (() -> Thing)? = nil,
		            leaf: Leaf.SafeDIMockConfiguration = .init(),
		            inner: Inner.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                thing_Thing: thing_Thing,
		                thing_Instantiator__Thing: thing_Instantiator__Thing,
		                leaf: leaf,
		                inner: inner
		            )
		        }

		        var thing_Thing: (() -> Thing)? { __safeDI_storage.thing_Thing }
		        var thing_Instantiator__Thing: (() -> Thing)? { __safeDI_storage.thing_Instantiator__Thing }
		        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
		        var inner: Inner.SafeDIMockConfiguration { __safeDI_storage.inner }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                thing_Thing: (() -> Thing)?,
		                thing_Instantiator__Thing: (() -> Thing)?,
		                leaf: Leaf.SafeDIMockConfiguration,
		                inner: Inner.SafeDIMockConfiguration
		            ) {
		                self.thing_Thing = thing_Thing
		                self.thing_Instantiator__Thing = thing_Instantiator__Thing
		                self.leaf = leaf
		                self.inner = inner
		            }

		            let thing_Thing: (() -> Thing)?
		            let thing_Instantiator__Thing: (() -> Thing)?
		            let leaf: Leaf.SafeDIMockConfiguration
		            let inner: Inner.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let thing_Thing = if let safeDIBuilder = safeDIOverrides.thing_Thing { safeDIBuilder() } else { Thing() }
		        func __safeDI_thing_Instantiator__Thing() -> Thing {
		            if let safeDIBuilder = safeDIOverrides.thing_Instantiator__Thing { safeDIBuilder() } else { Thing() }
		        }
		        let thing_Instantiator__Thing = Instantiator<Thing>(__safeDI_thing_Instantiator__Thing)
		        func __safeDI_first(safeDIOverrides: ((Thing) -> First)?) -> First {
		            let thing: Thing = thing_Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { First(thing: thing) }
		        }
		        func __safeDI_second(safeDIOverrides: ((Instantiator<Thing>) -> Second)?) -> Second {
		            let thing: Instantiator<Thing> = thing_Instantiator__Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { Second(thing: thing) }
		        }
		        func __safeDI_leaf(safeDIOverrides: Leaf.SafeDIMockConfiguration) -> Leaf {
		            let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		            let second: Second = __safeDI_second(safeDIOverrides: safeDIOverrides.second)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(first, second) } else { Leaf(first: first, second: second) }
		        }
		        let leaf: Leaf = __safeDI_leaf(safeDIOverrides: safeDIOverrides.leaf)
		        func __safeDI_inner(safeDIOverrides: Inner.SafeDIMockConfiguration) -> Inner {
		            let thing = if let safeDIBuilder = safeDIOverrides.thing { safeDIBuilder() } else { Other() }
		            let user = if let safeDIBuilder = safeDIOverrides.user { safeDIBuilder(thing) } else { User(thing: thing) }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(thing, user) } else { Inner(thing: thing, user: user) }
		        }
		        let inner: Inner = __safeDI_inner(safeDIOverrides: safeDIOverrides.inner)
		        return Root(leaf: leaf, inner: inner)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNamesInTheWalksOrderOnEveryRun_whenRootNamesTwentyValuesApart() async throws {
		// Ten labels, each received as a value and as an `Instantiator`: twenty children the root names apart, whose
		// names the records look up by label and type and never list.
		let labels = (0..<10).map { "value\($0)" }
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(leaf: Leaf) {
			        self.leaf = leaf
			    }

			    @Instantiated let leaf: Leaf
			}

			@Instantiable
			public final class Leaf: Instantiable {
			    public init(first: First, second: Second) {
			        self.first = first
			        self.second = second
			    }

			    @Instantiated let first: First
			    @Instantiated let second: Second
			}

			@Instantiable
			public final class First: Instantiable {
			    public init(\(labels.indices.map { "\(labels[$0]): Thing\($0)" }.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(labels.indices.map { "    @Received let \(labels[$0]): Thing\($0)" }.joined(separator: "\n"))
			}

			@Instantiable
			public final class Second: Instantiable {
			    public init(\(labels.indices.map { "\(labels[$0]): Instantiator<Thing\($0)>" }.joined(separator: ", "))) {
			\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
			    }

			\(labels.indices.map { "    @Received let \(labels[$0]): Instantiator<Thing\($0)>" }.joined(separator: "\n"))
			}

			\(labels.indices.map { "@Instantiable\npublic final class Thing\($0): Instantiable {\n    public init() {}\n}" }.joined(separator: "\n\n"))
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		var runs = [String]()
		for _ in 0..<2 {
			let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
				try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
			}
			#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
			try runs.append(#require(output.mockFiles["Root+SafeDIMock.swift"]))
		}
		#expect(runs[0] == runs[1])
		// The values `mock()`'s body binds, in order: each line of its own indentation that binds a name.
		func namesBound(in mock: String) -> [String] {
			mock.split(separator: "\n").compactMap { line in
				line.hasPrefix("        let ") ? line.dropFirst("        let ".count).prefix { $0 != " " && $0 != ":" }.description : nil
			}
		}
		let expectedNames = labels.indices.map { "\(labels[$0])_Thing\($0)" } + labels.indices.map { "\(labels[$0])_Instantiator__Thing\($0)" } + ["leaf"]
		#expect(namesBound(in: runs[0]) == expectedNames)
		#expect(try namesBound(in: #require(walkOutput.mockFiles["Root+SafeDIMock.swift"])) == expectedNames)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNameAgainInReceiversFunction_whenTypeReceivesLabelNamedApartOnlyIfAvailable() async throws {
		// `Third` receives `thing` only if available as the type `mock()` names `thing_Thing`, and nothing above any place
		// of it pins the label, so every place reads that name: its function binds the label again from it.
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixtureOfReceiveOnlyIfAvailable, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [[]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            thing_Thing: (() -> Thing)? = nil,
		            thing_Instantiator__Thing: (() -> Thing)? = nil,
		            leaf: Leaf.SafeDIMockConfiguration = .init(),
		            third: Third.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                thing_Thing: thing_Thing,
		                thing_Instantiator__Thing: thing_Instantiator__Thing,
		                leaf: leaf,
		                third: third
		            )
		        }

		        var thing_Thing: (() -> Thing)? { __safeDI_storage.thing_Thing }
		        var thing_Instantiator__Thing: (() -> Thing)? { __safeDI_storage.thing_Instantiator__Thing }
		        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
		        var third: Third.SafeDIMockConfiguration { __safeDI_storage.third }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                thing_Thing: (() -> Thing)?,
		                thing_Instantiator__Thing: (() -> Thing)?,
		                leaf: Leaf.SafeDIMockConfiguration,
		                third: Third.SafeDIMockConfiguration
		            ) {
		                self.thing_Thing = thing_Thing
		                self.thing_Instantiator__Thing = thing_Instantiator__Thing
		                self.leaf = leaf
		                self.third = third
		            }

		            let thing_Thing: (() -> Thing)?
		            let thing_Instantiator__Thing: (() -> Thing)?
		            let leaf: Leaf.SafeDIMockConfiguration
		            let third: Third.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let thing_Thing = if let safeDIBuilder = safeDIOverrides.thing_Thing { safeDIBuilder() } else { Thing() }
		        func __safeDI_thing_Instantiator__Thing() -> Thing {
		            if let safeDIBuilder = safeDIOverrides.thing_Instantiator__Thing { safeDIBuilder() } else { Thing() }
		        }
		        let thing_Instantiator__Thing = Instantiator<Thing>(__safeDI_thing_Instantiator__Thing)
		        func __safeDI_first(safeDIOverrides: ((Thing) -> First)?) -> First {
		            let thing: Thing = thing_Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { First(thing: thing) }
		        }
		        func __safeDI_second(safeDIOverrides: ((Instantiator<Thing>) -> Second)?) -> Second {
		            let thing: Instantiator<Thing> = thing_Instantiator__Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { Second(thing: thing) }
		        }
		        func __safeDI_leaf(safeDIOverrides: Leaf.SafeDIMockConfiguration) -> Leaf {
		            let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		            let second: Second = __safeDI_second(safeDIOverrides: safeDIOverrides.second)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(first, second) } else { Leaf(first: first, second: second) }
		        }
		        let leaf: Leaf = __safeDI_leaf(safeDIOverrides: safeDIOverrides.leaf)
		        func __safeDI_third(safeDIOverrides: Third.SafeDIMockConfiguration) -> Third {
		            let thing: Thing? = thing_Thing
		            let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(thing, first) } else { Third(thing: thing, first: first) }
		        }
		        let third: Third = __safeDI_third(safeDIOverrides: safeDIOverrides.third)
		        return Root(leaf: leaf, third: third)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesNilInReceiversFunction_whenRequiredReceiveBeneathTypePinsLabelItReceivesOnlyIfAvailable() async throws {
		// `Third` receives `thing` only if available as an `Instantiator`, and `First`, which it builds, requires the
		// value: wherever `Third` is built, the label is pinned to the value. `Holder` builds it beside no declaration of
		// the label, so its function is passed `nil` and binds no name again.
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: Self.fixtureOfReceivePinnedWhereverBuilt, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [[]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            thing_Thing: (() -> Thing)? = nil,
		            thing_Instantiator__Thing: (() -> Thing)? = nil,
		            leaf: Leaf.SafeDIMockConfiguration = .init(),
		            holder: Holder.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                thing_Thing: thing_Thing,
		                thing_Instantiator__Thing: thing_Instantiator__Thing,
		                leaf: leaf,
		                holder: holder
		            )
		        }

		        var thing_Thing: (() -> Thing)? { __safeDI_storage.thing_Thing }
		        var thing_Instantiator__Thing: (() -> Thing)? { __safeDI_storage.thing_Instantiator__Thing }
		        var leaf: Leaf.SafeDIMockConfiguration { __safeDI_storage.leaf }
		        var holder: Holder.SafeDIMockConfiguration { __safeDI_storage.holder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                thing_Thing: (() -> Thing)?,
		                thing_Instantiator__Thing: (() -> Thing)?,
		                leaf: Leaf.SafeDIMockConfiguration,
		                holder: Holder.SafeDIMockConfiguration
		            ) {
		                self.thing_Thing = thing_Thing
		                self.thing_Instantiator__Thing = thing_Instantiator__Thing
		                self.leaf = leaf
		                self.holder = holder
		            }

		            let thing_Thing: (() -> Thing)?
		            let thing_Instantiator__Thing: (() -> Thing)?
		            let leaf: Leaf.SafeDIMockConfiguration
		            let holder: Holder.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let thing_Thing = if let safeDIBuilder = safeDIOverrides.thing_Thing { safeDIBuilder() } else { Thing() }
		        func __safeDI_thing_Instantiator__Thing() -> Thing {
		            if let safeDIBuilder = safeDIOverrides.thing_Instantiator__Thing { safeDIBuilder() } else { Thing() }
		        }
		        let thing_Instantiator__Thing = Instantiator<Thing>(__safeDI_thing_Instantiator__Thing)
		        func __safeDI_first(safeDIOverrides: ((Thing) -> First)?) -> First {
		            let thing: Thing = thing_Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { First(thing: thing) }
		        }
		        func __safeDI_second(safeDIOverrides: ((Instantiator<Thing>) -> Second)?) -> Second {
		            let thing: Instantiator<Thing> = thing_Instantiator__Thing
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(thing) } else { Second(thing: thing) }
		        }
		        func __safeDI_leaf(safeDIOverrides: Leaf.SafeDIMockConfiguration) -> Leaf {
		            let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		            let second: Second = __safeDI_second(safeDIOverrides: safeDIOverrides.second)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(first, second) } else { Leaf(first: first, second: second) }
		        }
		        let leaf: Leaf = __safeDI_leaf(safeDIOverrides: safeDIOverrides.leaf)
		        func __safeDI_third(safeDIOverrides: Third.SafeDIMockConfiguration) -> Third {
		            let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(nil, first) } else { Third(thing: nil, first: first) }
		        }
		        func __safeDI_holder(safeDIOverrides: Holder.SafeDIMockConfiguration) -> Holder {
		            let third: Third = __safeDI_third(safeDIOverrides: safeDIOverrides.third)
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(third) } else { Holder(third: third) }
		        }
		        let holder: Holder = __safeDI_holder(safeDIOverrides: safeDIOverrides.holder)
		        return Root(leaf: leaf, holder: holder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	/// Where a type that receives a label named apart only if available is built.
	enum ReceivePlace: CaseIterable {
		/// It reads the form `mock()` names apart, and nothing pins the label.
		case readsName
		/// A required receive beneath it pins the label, and it is built beside no declaration of the label: `nil`.
		case pinnedBesideNoDeclaration
		/// A required receive beneath it pins the label, and the root builds it after the child it promotes for the form
		/// it reads, which it is handed, as the walk hands it a sibling built before it.
		case pinnedBesidePromotedChild
	}

	@Test(arguments: ReceivePlace.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeReceivesLabelNamedApartOnlyIfAvailable(place: ReceivePlace) async throws {
		let fixture = switch place {
		case .readsName: Self.fixtureOfReceiveOnlyIfAvailable
		case .pinnedBesideNoDeclaration: Self.fixtureOfReceivePinnedWhereverBuilt
		case .pinnedBesidePromotedChild: Self.fixtureOfReceiveOnlyIfAvailable.merging(Self.fixtureOfReceivePinnedWhereverBuilt.filter { $0.key == "Third.swift" }) { $1 }
		}
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let overridden = """
		Root.mock(safeDIOverrides: .init(\
		thing_Thing: { marked(Thing(), "thing_Thing") }, \
		thing_Instantiator__Thing: { marked(Thing(), "thing_Instantiator__Thing") }))
		"""
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden value of the constant’s instantiator", expression: "\(overridden).leaf.second.thing.instantiate()"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built.
		for marker in ["thing_Thing", "thing_Instantiator__Thing"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTheWalksStatements_whenPinnedReceiveIsBuiltBesidePromotedChildAndBesideNoDeclaration() async throws {
		// The root builds `Third` after the child it promotes for the form `Third` reads, and `Holder` builds it beside no
		// declaration of the label: the one is handed the name and the other `nil`. One function serves both, so the
		// world is refused, and the walk writes it.
		let fixture = Self.fixtureOfReceivePinnedWhereverBuilt.merging([
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Marked {
			    public init(leaf: Leaf, third: Third, holder: Holder) {
			        self.leaf = leaf
			        self.third = third
			        self.holder = holder
			    }

			    @Instantiated let leaf: Leaf
			    @Instantiated let third: Third
			    @Instantiated let holder: Holder
			    public var marker = "built"
			}
			""",
		]) { $1 }
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.refusal) == ["onlyIfAvailableAnsweredApart"])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTheWalksStatements_whenRequiredReceiveAbovePlacePinsLabelNamedApart() async throws {
		// `Lower` receives `thing` only if available as an `Instantiator`, and `Upper`, which builds it, requires the
		// value: the label is pinned at that place, not for the type, so whether `Lower` reads the name or `nil` is its
		// place’s. One function serves every place, so the world is refused, and the walk writes it.
		let fixture = Self.fixture.merging([
			"Root.swift": """
			@Instantiable(generateMock: true)
			public final class Root: Instantiable, Marked {
			    public init(leaf: Leaf, upper: Upper) {
			        self.leaf = leaf
			        self.upper = upper
			    }

			    @Instantiated let leaf: Leaf
			    @Instantiated let upper: Upper
			    public var marker = "built"
			}
			""",
			"Upper.swift": """
			@Instantiable
			public final class Upper: Instantiable, Marked {
			    public init(thing: Thing, lower: Lower) {
			        self.thing = thing
			        self.lower = lower
			    }

			    @Received let thing: Thing
			    @Instantiated let lower: Lower
			    public var marker = "built"
			}
			""",
			"Lower.swift": """
			@Instantiable
			public final class Lower: Instantiable, Marked {
			    public init(thing: Instantiator<Thing>?) {
			        self.thing = thing
			    }

			    @Received(onlyIfAvailable: true) let thing: Instantiator<Thing>?
			    public var marker = "built"
			}
			""",
		]) { $1 }
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["mockOverrideNotParentField"]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [false])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// `fixture` with a root that builds `Third` in the second child’s place: `Third` receives `thing` only if available
	/// as the value and builds `First`, which requires the value.
	private static let fixtureOfReceiveOnlyIfAvailable: [String: String] = fixture.merging([
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable, Marked {
		    public init(leaf: Leaf, third: Third) {
		        self.leaf = leaf
		        self.third = third
		    }

		    @Instantiated let leaf: Leaf
		    @Instantiated let third: Third
		    public var marker = "built"
		}
		""",
		"Third.swift": """
		@Instantiable
		public final class Third: Instantiable, Marked {
		    public init(thing: Thing?, first: First) {
		        self.thing = thing
		        self.first = first
		    }

		    @Received(onlyIfAvailable: true) let thing: Thing?
		    @Instantiated let first: First
		    public var marker = "built"
		}
		""",
	]) { $1 }

	/// `fixtureOfReceiveOnlyIfAvailable` with a `Third` that receives `thing` only if available as an `Instantiator`,
	/// which `First`’s required receive of the value beneath it pins, built by `Holder`, which the root builds.
	private static let fixtureOfReceivePinnedWhereverBuilt: [String: String] = fixtureOfReceiveOnlyIfAvailable.merging([
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable, Marked {
		    public init(leaf: Leaf, holder: Holder) {
		        self.leaf = leaf
		        self.holder = holder
		    }

		    @Instantiated let leaf: Leaf
		    @Instantiated let holder: Holder
		    public var marker = "built"
		}
		""",
		"Holder.swift": """
		@Instantiable
		public final class Holder: Instantiable, Marked {
		    public init(third: Third) {
		        self.third = third
		    }

		    @Instantiated let third: Third
		    public var marker = "built"
		}
		""",
		"Third.swift": """
		@Instantiable
		public final class Third: Instantiable, Marked {
		    public init(thing: Instantiator<Thing>?, first: First) {
		        self.thing = thing
		        self.first = first
		    }

		    @Received(onlyIfAvailable: true) let thing: Instantiator<Thing>?
		    @Instantiated let first: First
		    public var marker = "built"
		}
		""",
	]) { $1 }

	/// A root whose leaf builds two children that each receive `thing`, one as a value and one as an `Instantiator`, so
	/// `mock()` names the two apart. The root also builds the second child through an `Instantiator`. Each class carries
	/// a marker an override’s closure sets.
	private static let fixture: [String: String] = [
		"Marked.swift": """
		public protocol Marked: AnyObject {
		    var marker: String { get set }
		}

		public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
		    value.marker = marker
		    return value
		}
		""",
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable, Marked {
		    public init(leaf: Leaf, secondBuilder: Instantiator<Second>) {
		        self.leaf = leaf
		        self.secondBuilder = secondBuilder
		    }

		    @Instantiated let leaf: Leaf
		    @Instantiated let secondBuilder: Instantiator<Second>
		    public var marker = "built"
		}
		""",
		"Leaf.swift": """
		@Instantiable
		public final class Leaf: Instantiable, Marked {
		    public init(first: First, second: Second) {
		        self.first = first
		        self.second = second
		    }

		    @Instantiated let first: First
		    @Instantiated let second: Second
		    public var marker = "built"
		}
		""",
		"First.swift": """
		@Instantiable
		public final class First: Instantiable, Marked {
		    public init(thing: Thing) {
		        self.thing = thing
		    }

		    @Received let thing: Thing
		    public var marker = "built"
		}
		""",
		"Second.swift": """
		@Instantiable
		public final class Second: Instantiable, Marked {
		    public init(thing: Instantiator<Thing>) {
		        self.thing = thing
		    }

		    @Received let thing: Instantiator<Thing>
		    public var marker = "built"
		}
		""",
		"Thing.swift": """
		@Instantiable
		public final class Thing: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}
		""",
	]

	/// The files that make `fixture` a root that also builds `Inner`, which builds a `thing` of a third type for its child.
	private static let fixtureOfLabelBuiltBelowRoot: [String: String] = [
		"Root.swift": """
		@Instantiable(generateMock: true)
		public final class Root: Instantiable, Marked {
		    public init(leaf: Leaf, inner: Inner) {
		        self.leaf = leaf
		        self.inner = inner
		    }

		    @Instantiated let leaf: Leaf
		    @Instantiated let inner: Inner
		    public var marker = "built"
		}
		""",
		"Inner.swift": """
		@Instantiable
		public final class Inner: Instantiable, Marked {
		    public init(thing: Other, user: User) {
		        self.thing = thing
		        self.user = user
		    }

		    @Instantiated let thing: Other
		    @Instantiated let user: User
		    public var marker = "built"
		}
		""",
		"Other.swift": """
		@Instantiable
		public final class Other: Instantiable, Marked {
		    public init() {}

		    public var marker = "built"
		}
		""",
		"User.swift": """
		@Instantiable
		public final class User: Instantiable, Marked {
		    public init(thing: Other) {
		        self.thing = thing
		    }

		    @Received let thing: Other
		    public var marker = "built"
		}
		""",
	]

	/// What `body` returns with every internal mock root node records accept laid out from them, and the report of each
	/// mock root of the run, in the order of the roots' names.
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
