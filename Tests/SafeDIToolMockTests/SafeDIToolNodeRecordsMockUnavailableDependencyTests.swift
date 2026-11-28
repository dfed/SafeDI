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

/// An internal mock root whose type instantiates, only if available, a property no declaration fulfills, laid out from
/// the node records of its world (`NodeRecords+MockUnavailableDependency.swift`). `mock()` takes one override of the
/// property, a value, and binds the property from it where production binds it to `nil`.
struct SafeDIToolNodeRecordsMockUnavailableDependencyTests: ~Copyable {
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
	mutating func mock_bindsPropertyFromItsOverride_whenMockedTypeInstantiatesTypeOnlyIfAvailableThatNoDeclarationFulfills() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// The property is bound in `mock()`'s body, from `mock()`'s own parameter, and the child that receives it only if
		// available reads the binding in its function, which is declared once for the constant and the `Instantiator`.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            child: Child.SafeDIMockConfiguration = .init(),
		            childBuilder: Child.SafeDIMockConfiguration = .init(),
		            missing: Missing? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child,
		                childBuilder: childBuilder
		            )
		            self.missing = missing
		        }

		        var child: Child.SafeDIMockConfiguration { __safeDI_storage.child }
		        var childBuilder: Child.SafeDIMockConfiguration { __safeDI_storage.childBuilder }
		        let missing: Missing?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: Child.SafeDIMockConfiguration,
		                childBuilder: Child.SafeDIMockConfiguration
		            ) {
		                self.child = child
		                self.childBuilder = childBuilder
		            }

		            let child: Child.SafeDIMockConfiguration
		            let childBuilder: Child.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let missing: Missing? = safeDIOverrides.missing
		        func __safeDI_child(safeDIOverrides: Child.SafeDIMockConfiguration) -> Child {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(missing, leaf) } else { Child(missing: missing, leaf: leaf) }
		        }
		        let child: Child = __safeDI_child(safeDIOverrides: safeDIOverrides.child)
		        let childBuilder = Instantiator<Child> {
		            __safeDI_child(safeDIOverrides: safeDIOverrides.childBuilder)
		        }
		        return Root(missing: missing, child: child, childBuilder: childBuilder)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenOverrideOfUnavailableDependencyAndEveryPlaceIsOverridden() async throws {
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixture], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		func child(_ place: String) -> String {
			".init(leaf: { marked(Leaf(), \"\(place).leaf\") }, { marked(Child(missing: $0, leaf: $1), \"\(place)\") })"
		}
		let overridden = "Root.mock(safeDIOverrides: .init(child: \(child("child")), childBuilder: \(child("childBuilder")), missing: marked(Stub(), \"missing\")))"
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: ["Root.swift": Self.fixture], generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: ["Root.swift": Self.fixture], generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().childBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden instantiator", expression: "\(overridden).childBuilder.instantiate()"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built, and the property's is the value handed in.
		for marker in ["missing", "child", "child.leaf", "childBuilder", "childBuilder.leaf"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsOverrideBoundBeforeNodes_whenTypeBeneathRootDeclaresUnavailableDependency() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixtureOfPropertyDeclaredBeneathRoot], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// `Child` declares `missing` two types beneath the root. `mock()` binds the override before its nodes, and
		// `Child`'s function reads that binding, as it reads `absent`, the root's own: neither is handed down.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            mid: Mid.SafeDIMockConfiguration = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            absent: Absent? = nil,
		            missing: Missing? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                mid: mid,
		                midBuilder: midBuilder
		            )
		            self.absent = absent
		            self.missing = missing
		        }

		        var mid: Mid.SafeDIMockConfiguration { __safeDI_storage.mid }
		        var midBuilder: Mid.SafeDIMockConfiguration { __safeDI_storage.midBuilder }
		        let absent: Absent?
		        let missing: Missing?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                mid: Mid.SafeDIMockConfiguration,
		                midBuilder: Mid.SafeDIMockConfiguration
		            ) {
		                self.mid = mid
		                self.midBuilder = midBuilder
		            }

		            let mid: Mid.SafeDIMockConfiguration
		            let midBuilder: Mid.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let absent: Absent? = safeDIOverrides.absent
		        let missing: Missing? = safeDIOverrides.missing
		        func __safeDI_mid(safeDIOverrides: Mid.SafeDIMockConfiguration) -> Mid {
		            let child: Child = __safeDI_child(safeDIOverrides: safeDIOverrides.child)
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(child, leaf) } else { Mid(child: child, leaf: leaf) }
		        }
		        func __safeDI_child(safeDIOverrides: Child.SafeDIMockConfiguration) -> Child {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(missing, absent, leaf) } else { Child(missing: missing, absent: absent, leaf: leaf) }
		        }
		        let mid: Mid = __safeDI_mid(safeDIOverrides: safeDIOverrides.mid)
		        let midBuilder = Instantiator<Mid> {
		            __safeDI_mid(safeDIOverrides: safeDIOverrides.midBuilder)
		        }
		        return Root(mid: mid, midBuilder: midBuilder, absent: absent)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenTypeBeneathRootDeclaresUnavailableDependencyAndEveryPlaceIsOverridden() async throws {
		let fixture = ["Root.swift": Self.fixtureOfPropertyDeclaredBeneathRoot]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		func mid(_ place: String) -> String {
			"""
			.init(\
			child: .init(leaf: { marked(Leaf(), "\(place).child.leaf") }, { marked(Child(missing: $0, absent: $1, leaf: $2), "\(place).child") }), \
			leaf: { marked(Leaf(), "\(place).leaf") }, \
			{ marked(Mid(child: $0, leaf: $1), "\(place)") })
			"""
		}
		let overridden = "Root.mock(safeDIOverrides: .init(mid: \(mid("mid")), midBuilder: \(mid("midBuilder")), absent: marked(Stub(), \"absent\"), missing: marked(Stub(), \"missing\")))"
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().midBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden instantiator", expression: "\(overridden).midBuilder.instantiate()"),
				DifferentialValueProbe(name: "only the override of the property beneath the root", expression: "Root.mock(safeDIOverrides: .init(missing: marked(Stub(), \"missing alone\")))"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built, and each property's is the value handed in.
		for marker in ["absent", "missing", "missing alone", "mid", "mid.leaf", "mid.child", "mid.child.leaf", "midBuilder", "midBuilder.leaf", "midBuilder.child", "midBuilder.child.leaf"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_readsOneBinding_whenRootAndAnotherTypeBothBuildTypeThatDeclaresUnavailableDependency() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixtureOfTypeBuiltByRootAndBeneathIt], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// `Child` is built by the root and by `Mid`. Its one function reads the binding `mock()` makes before its nodes,
		// whichever body calls it.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            child: Child.SafeDIMockConfiguration = .init(),
		            mid: Mid.SafeDIMockConfiguration = .init(),
		            midBuilder: Mid.SafeDIMockConfiguration = .init(),
		            absent: Absent? = nil,
		            missing: Missing? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child,
		                mid: mid,
		                midBuilder: midBuilder
		            )
		            self.absent = absent
		            self.missing = missing
		        }

		        var child: Child.SafeDIMockConfiguration { __safeDI_storage.child }
		        var mid: Mid.SafeDIMockConfiguration { __safeDI_storage.mid }
		        var midBuilder: Mid.SafeDIMockConfiguration { __safeDI_storage.midBuilder }
		        let absent: Absent?
		        let missing: Missing?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: Child.SafeDIMockConfiguration,
		                mid: Mid.SafeDIMockConfiguration,
		                midBuilder: Mid.SafeDIMockConfiguration
		            ) {
		                self.child = child
		                self.mid = mid
		                self.midBuilder = midBuilder
		            }

		            let child: Child.SafeDIMockConfiguration
		            let mid: Mid.SafeDIMockConfiguration
		            let midBuilder: Mid.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let absent: Absent? = safeDIOverrides.absent
		        let missing: Missing? = safeDIOverrides.missing
		        func __safeDI_child(safeDIOverrides: Child.SafeDIMockConfiguration) -> Child {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(missing, absent, leaf) } else { Child(missing: missing, absent: absent, leaf: leaf) }
		        }
		        let child: Child = __safeDI_child(safeDIOverrides: safeDIOverrides.child)
		        func __safeDI_mid(safeDIOverrides: Mid.SafeDIMockConfiguration) -> Mid {
		            let child: Child = __safeDI_child(safeDIOverrides: safeDIOverrides.child)
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(child, leaf) } else { Mid(child: child, leaf: leaf) }
		        }
		        let mid: Mid = __safeDI_mid(safeDIOverrides: safeDIOverrides.mid)
		        let midBuilder = Instantiator<Mid> {
		            __safeDI_mid(safeDIOverrides: safeDIOverrides.midBuilder)
		        }
		        return Root(mid: mid, midBuilder: midBuilder, absent: absent, child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenRootAndAnotherTypeBothBuildTypeThatDeclaresUnavailableDependency() async throws {
		let fixture = ["Root.swift": Self.fixtureOfTypeBuiltByRootAndBeneathIt]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		func child(_ place: String) -> String {
			".init(leaf: { marked(Leaf(), \"\(place).leaf\") }, { marked(Child(missing: $0, absent: $1, leaf: $2), \"\(place)\") })"
		}
		func mid(_ place: String) -> String {
			".init(child: \(child("\(place).child")), leaf: { marked(Leaf(), \"\(place).leaf\") }, { marked(Mid(child: $0, leaf: $1), \"\(place)\") })"
		}
		let overridden = "Root.mock(safeDIOverrides: .init(child: \(child("child")), mid: \(mid("mid")), midBuilder: \(mid("midBuilder")), absent: marked(Stub(), \"absent\"), missing: marked(Stub(), \"missing\")))"
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe("Root.mock().midBuilder.instantiate()"),
				DifferentialValueProbe(name: "overridden root", expression: overridden),
				DifferentialValueProbe(name: "overridden instantiator", expression: "\(overridden).midBuilder.instantiate()"),
				DifferentialValueProbe(name: "only the override of the property", expression: "Root.mock(safeDIOverrides: .init(missing: marked(Stub(), \"missing alone\")))"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built, and each property's is the value handed in.
		for marker in ["absent", "missing", "missing alone", "child", "child.leaf", "mid", "mid.leaf", "mid.child", "mid.child.leaf", "midBuilder", "midBuilder.leaf", "midBuilder.child", "midBuilder.child.leaf"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsEachLabelToItsOverride_whenOverridesOfTwoUnavailableDependenciesAreNamedApart() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixtureOfOverridesNamedApart], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// Two types declare `missing`, of two types, so `mock()` names the overrides apart, and each type's function binds
		// its label to the name of its own.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            first: First.SafeDIMockConfiguration = .init(),
		            second: Second.SafeDIMockConfiguration = .init(),
		            missing_Missing: Missing? = nil,
		            missing_Other: Other? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                first: first,
		                second: second
		            )
		            self.missing_Missing = missing_Missing
		            self.missing_Other = missing_Other
		        }

		        var first: First.SafeDIMockConfiguration { __safeDI_storage.first }
		        var second: Second.SafeDIMockConfiguration { __safeDI_storage.second }
		        let missing_Missing: Missing?
		        let missing_Other: Other?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                first: First.SafeDIMockConfiguration,
		                second: Second.SafeDIMockConfiguration
		            ) {
		                self.first = first
		                self.second = second
		            }

		            let first: First.SafeDIMockConfiguration
		            let second: Second.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let missing_Missing: Missing? = safeDIOverrides.missing_Missing
		        let missing_Other: Other? = safeDIOverrides.missing_Other
		        func __safeDI_first(safeDIOverrides: First.SafeDIMockConfiguration) -> First {
		            let missing: Missing? = missing_Missing
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(missing, leaf) } else { First(missing: missing, leaf: leaf) }
		        }
		        let first: First = __safeDI_first(safeDIOverrides: safeDIOverrides.first)
		        func __safeDI_second(safeDIOverrides: Second.SafeDIMockConfiguration) -> Second {
		            let missing: Other? = missing_Other
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(missing, leaf) } else { Second(missing: missing, leaf: leaf) }
		        }
		        let second: Second = __safeDI_second(safeDIOverrides: safeDIOverrides.second)
		        return Root(first: first, second: second)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenOverridesOfTwoUnavailableDependenciesAreNamedApart() async throws {
		let fixture = ["Root.swift": Self.fixtureOfOverridesNamedApart]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(
					name: "overridden root",
					expression: "Root.mock(safeDIOverrides: .init(missing_Missing: marked(Stub(), \"missing of first\"), missing_Other: marked(Stub(), \"missing of second\")))",
				),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built, and each property's is the value handed in.
		for marker in ["missing of first", "missing of second"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_writesNoLineForProperty_whenRootAndTypeBeneathItDeclareSameUnavailableDependency() async throws {
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: ["Root.swift": Self.fixtureOfPropertyRootAndChildDeclare], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		// The root and `Child` declare `missing`, one declaration of the world. `mock()` binds its override before the nodes,
		// which is the root's own property, and `Child`'s function reads it.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            child: Child.SafeDIMockConfiguration = .init(),
		            missing: Missing? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                child: child
		            )
		            self.missing = missing
		        }

		        var child: Child.SafeDIMockConfiguration { __safeDI_storage.child }
		        let missing: Missing?

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                child: Child.SafeDIMockConfiguration
		            ) {
		                self.child = child
		            }

		            let child: Child.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        let missing: Missing? = safeDIOverrides.missing
		        func __safeDI_child(safeDIOverrides: Child.SafeDIMockConfiguration) -> Child {
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(missing, leaf) } else { Child(missing: missing, leaf: leaf) }
		        }
		        let child: Child = __safeDI_child(safeDIOverrides: safeDIOverrides.child)
		        return Root(missing: missing, child: child)
		    }
		}
		#endif
		""", "Unexpected output \(output.mockFiles["Root+SafeDIMock.swift"] ?? "")")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenRootAndTypeBeneathItDeclareSameUnavailableDependency() async throws {
		let fixture = ["Root.swift": Self.fixtureOfPropertyRootAndChildDeclare]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, _) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		// The two write other text, so the comparison is of two programs.
		#expect(output.mockFiles["Root+SafeDIMock.swift"] != walkOutput.mockFiles["Root+SafeDIMock.swift"])
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: [
				DifferentialValueProbe("Root.mock()"),
				DifferentialValueProbe(name: "overridden root", expression: "Root.mock(safeDIOverrides: .init(missing: marked(Stub(), \"missing\")))"),
			],
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks a value its closure built, and each property's is the value handed in.
		for marker in ["missing"] {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNilAsTheWalkWritesIt_whenOnlySendableFunctionBuildsTypeThatDeclaresUnavailableDependency() async throws {
		// `mock()` takes no override of a property declared only inside a `@Sendable` function, so the record is
		// production's, and the text the walk's.
		let fixture = ["Root.swift": Self.fixtureOfPropertyDeclaredInSendableFunction]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.generatedFiles == walkOutput.generatedFiles)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutFromNodeRecords_whenTypeThatDeclaresUnavailableDependencyIsNamedApartOnLazyCycle() async throws {
		// The acceptance case of the kind that lays out a cycle's closer: `Node` declares `token`, which nothing fulfills,
		// is built again through its own `Instantiator`, and is named apart from the `node` a sibling receives. The function
		// the cycle closes on takes no parameter for `node`, its own label, and the call that closes the cycle names it as
		// it is named apart, so the records lay the mock out in the slot form; `SafeDIToolNodeRecordsMockCycleWalkTests`
		// compares its values with the walk's.
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Host: Instantiable {
			    public init(node: Node, peer: Peer) {
			        self.node = node
			        self.peer = peer
			    }

			    @Instantiated let node: Node
			    @Received let peer: Peer
			}

			@Instantiable
			public final class Node: Instantiable {
			    public init(loopBuilder: Instantiator<Loop>, token: Token?) {
			        self.loopBuilder = loopBuilder
			        self.token = token
			    }

			    @Instantiated let loopBuilder: Instantiator<Loop>
			    @Instantiated(onlyIfAvailable: true) let token: Token?
			}

			@Instantiable
			public final class Loop: Instantiable {
			    public init(node: Node) {
			        self.node = node
			    }

			    @Instantiated let node: Node
			}

			@Instantiable
			public final class Peer: Instantiable {
			    public init(node: Other) {
			        self.node = node
			    }

			    @Received let node: Other
			}

			@Instantiable
			public final class Other: Instantiable {
			    public init() {}
			}

			public final class Token {}
			""",
		]
		let (_, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}

		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [[]])
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root that instantiates `missing` only if available, which nothing fulfills, and builds a child, in place and
	/// through an `Instantiator`, that receives it only if available. Each class carries a marker an override sets.
	private static let fixture = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}

	public protocol Missing {}

	public final class Stub: Missing, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(missing: Missing?, child: Child, childBuilder: Instantiator<Child>) {
	        self.missing = missing
	        self.child = child
	        self.childBuilder = childBuilder
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Missing?
	    @Instantiated let child: Child
	    @Instantiated let childBuilder: Instantiator<Child>
	}

	@Instantiable
	public final class Child: Instantiable, Marked {
	    public init(missing: Missing?, leaf: Leaf) {
	        self.missing = missing
	        self.leaf = leaf
	    }

	    @Received(onlyIfAvailable: true) let missing: Missing?
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Leaf: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}
	"""

	/// A root that builds two types, each of which instantiates `missing` only if available, of two types nothing fulfills.
	private static let fixtureOfOverridesNamedApart = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}

	public protocol Missing {}
	public protocol Other {}

	public final class Stub: Missing, Other, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(first: First, second: Second) {
	        self.first = first
	        self.second = second
	    }

	    @Instantiated let first: First
	    @Instantiated let second: Second
	}

	@Instantiable
	public final class First: Instantiable, Marked {
	    public init(missing: Missing?, leaf: Leaf) {
	        self.missing = missing
	        self.leaf = leaf
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Missing?
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Second: Instantiable, Marked {
	    public init(missing: Other?, leaf: Leaf) {
	        self.missing = missing
	        self.leaf = leaf
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Other?
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Leaf: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}
	"""

	/// A root that instantiates `missing` only if available and builds a type that instantiates it only if available too.
	private static let fixtureOfPropertyRootAndChildDeclare = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}

	public protocol Missing {}
	public protocol Other {}

	public final class Stub: Missing, Other, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(missing: Missing?, child: Child) {
	        self.missing = missing
	        self.child = child
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Missing?
	    @Instantiated let child: Child
	}

	@Instantiable
	public final class Child: Instantiable, Marked {
	    public init(missing: Missing?, leaf: Leaf) {
	        self.missing = missing
	        self.leaf = leaf
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Missing?
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Leaf: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}
	"""

	/// A root that builds, through a `SendableInstantiator`, a type that instantiates `missing` only if available.
	private static let fixtureOfPropertyDeclaredInSendableFunction = """
	public protocol Missing: Sendable {}

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(childBuilder: SendableInstantiator<Child>) {
	        self.childBuilder = childBuilder
	    }

	    @Instantiated let childBuilder: SendableInstantiator<Child>
	}

	@Instantiable
	public struct Child: Instantiable {
	    public init(missing: Missing?, leaf: Leaf) {
	        self.missing = missing
	        self.leaf = leaf
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Missing?
	    @Instantiated let leaf: Leaf
	}

	@Instantiable
	public struct Leaf: Instantiable {
	    public init() {}
	}
	"""

	/// A root that instantiates `absent` only if available and builds, in place and through an `Instantiator`, a type
	/// whose child instantiates `missing` only if available and receives `absent`. Nothing fulfills either.
	private static let fixtureOfPropertyDeclaredBeneathRoot = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}

	public protocol Missing {}
	public protocol Absent {}

	public final class Stub: Missing, Absent, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(mid: Mid, midBuilder: Instantiator<Mid>, absent: Absent?) {
	        self.mid = mid
	        self.midBuilder = midBuilder
	        self.absent = absent
	    }

	    @Instantiated let mid: Mid
	    @Instantiated let midBuilder: Instantiator<Mid>
	    @Instantiated(onlyIfAvailable: true) let absent: Absent?
	}

	@Instantiable
	public final class Mid: Instantiable, Marked {
	    public init(child: Child, leaf: Leaf) {
	        self.child = child
	        self.leaf = leaf
	    }

	    @Instantiated let child: Child
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Child: Instantiable, Marked {
	    public init(missing: Missing?, absent: Absent?, leaf: Leaf) {
	        self.missing = missing
	        self.absent = absent
	        self.leaf = leaf
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Missing?
	    @Received(onlyIfAvailable: true) let absent: Absent?
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Leaf: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}
	"""

	/// `fixtureOfPropertyDeclaredBeneathRoot` with a root that also builds the child itself.
	private static let fixtureOfTypeBuiltByRootAndBeneathIt = """
	public protocol Marked: AnyObject {
	    var marker: String { get set }
	}

	public func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
	    value.marker = marker
	    return value
	}

	public protocol Missing {}
	public protocol Absent {}

	public final class Stub: Missing, Absent, Marked {
	    public init() {}

	    public var marker = "built"
	}

	@Instantiable(generateMock: true)
	public final class Root: Instantiable {
	    public init(mid: Mid, midBuilder: Instantiator<Mid>, absent: Absent?, child: Child) {
	        self.child = child
	        self.mid = mid
	        self.midBuilder = midBuilder
	        self.absent = absent
	    }

	    @Instantiated let child: Child
	    @Instantiated let mid: Mid
	    @Instantiated let midBuilder: Instantiator<Mid>
	    @Instantiated(onlyIfAvailable: true) let absent: Absent?
	}

	@Instantiable
	public final class Mid: Instantiable, Marked {
	    public init(child: Child, leaf: Leaf) {
	        self.child = child
	        self.leaf = leaf
	    }

	    @Instantiated let child: Child
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Child: Instantiable, Marked {
	    public init(missing: Missing?, absent: Absent?, leaf: Leaf) {
	        self.missing = missing
	        self.absent = absent
	        self.leaf = leaf
	    }

	    @Instantiated(onlyIfAvailable: true) let missing: Missing?
	    @Received(onlyIfAvailable: true) let absent: Absent?
	    @Instantiated let leaf: Leaf
	    public var marker = "built"
	}

	@Instantiable
	public final class Leaf: Instantiable, Marked {
	    public init() {}

	    public var marker = "built"
	}
	"""

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
