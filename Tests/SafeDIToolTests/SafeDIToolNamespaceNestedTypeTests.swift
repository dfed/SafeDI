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

/// A type an `@Instantiable` declaration spells by the name of a type nested in a type enclosing it – a namespace
/// `enum`, or the namespace an extension extends – or nested in the declaration's own type. The code SafeDI generates
/// outside that type (another type's tree, a mock's extension of the nested type, a seam's initializer) names it
/// qualified, as Swift resolves the name where the declaration spells it.
struct SafeDIToolNamespaceNestedTypeTests: ~Copyable {
	// MARK: Initialization

	init() throws {
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
	mutating func mock_qualifiesTypeDeclaredInEnclosingEnum_whenMockedTypesDefaultValuedParameterNamesIt() async throws {
		// `Child`'s mock is declared in `extension Feature.Child`, where `Mode`, declared in `Feature`, does not
		// resolve.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(child: Feature.Child) {
				        self.child = child
				    }

				    @Instantiated let child: Feature.Child
				}
				""",
				"""
				public enum Feature {
				    public enum Mode {
				        case fast
				        case slow
				    }

				    @Instantiable(generateMock: true)
				    public final class Child: Instantiable {
				        public init(mode: Mode = .fast) {
				            self.mode = mode
				        }

				        let mode: Mode
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    static func mock(
			        mode: Feature.Mode = .fast
			    ) -> Feature.Child {
			        return Feature.Child(mode: mode)
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let child = Feature.Child()
			        self.init(child: child)
			    }
			}
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_qualifiesTypeDeclaredInExtendedNamespace_whenConfiguredTypesDefaultValuedParameterNamesIt() async throws {
		// `Child` is declared in an extension of `Feature`, beside `Mode`. `Root`'s mock configures `Child` with
		// `Feature.Child.SafeDIMockConfiguration`, declared in `extension Feature.Child`, where `Mode` does not
		// resolve.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(child: Feature.Child) {
				        self.child = child
				    }

				    @Instantiated let child: Feature.Child
				}
				""",
				"""
				public enum Feature {}

				extension Feature {
				    public enum Mode {
				        case fast
				        case slow
				    }

				    @Instantiable
				    public final class Child: Instantiable {
				        public init(mode: Mode = .fast) {
				            self.mode = mode
				        }

				        let mode: Mode
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let child = Feature.Child()
			        self.init(child: child)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: Feature.Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.child = child
			        }

			        let child: Feature.Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_child() -> Feature.Child {
			            return if let safeDIBuilder = safeDIOverrides.child.safeDIBuilder { safeDIBuilder(safeDIOverrides.child.mode) } else { Feature.Child(mode: safeDIOverrides.child.mode) }
			        }
			        let child: Feature.Child = __safeDI_child()
			        return Root(child: child)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            mode: Feature.Mode = .fast,
			            _ safeDIBuilder: ((Feature.Mode) -> Feature.Child)? = nil
			        ) {
			            self.mode = mode
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let mode: Feature.Mode
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Feature.Mode) -> Feature.Child)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeDeclaredInExtendedNamespace_whenForwardedPropertiesNameIt() async throws {
		// `Root`'s tree builds `Child` in a builder function that takes `Child`'s forwarded properties, declared in
		// `extension Root`, where `Mode` does not resolve.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(childBuilder: Instantiator<Feature.Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Feature.Child>
				}
				""",
				"""
				public enum Feature {}

				extension Feature {
				    public enum Mode {
				        case fast
				        case slow
				    }

				    @Instantiable(generateMock: true)
				    public final class Child: Instantiable {
				        public init(mode: Mode, fallback: Mode?) {
				            self.mode = mode
				            self.fallback = fallback
				        }

				        @Forwarded let mode: Mode
				        @Forwarded let fallback: Mode?
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    static func mock(
			        fallback: Feature.Mode?,
			        mode: Feature.Mode
			    ) -> Feature.Child {
			        return Feature.Child(mode: mode, fallback: fallback)
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_childBuilder(fallback: Feature.Mode?, mode: Feature.Mode) -> Feature.Child {
			            Feature.Child(mode: mode, fallback: fallback)
			        }
			        let childBuilder = Instantiator<Feature.Child> {
			            __safeDI_childBuilder(fallback: $0.fallback, mode: $0.mode)
			        }
			        self.init(childBuilder: childBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            childBuilder: ((Feature.Mode, Feature.Mode?) -> Feature.Child)? = nil
			        ) {
			            self.childBuilder = childBuilder
			        }

			        let childBuilder: ((Feature.Mode, Feature.Mode?) -> Feature.Child)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_childBuilder(fallback: Feature.Mode?, mode: Feature.Mode) -> Feature.Child {
			            if let safeDIBuilder = safeDIOverrides.childBuilder { safeDIBuilder(mode, fallback) } else { Feature.Child(mode: mode, fallback: fallback) }
			        }
			        let childBuilder = Instantiator<Feature.Child> {
			            __safeDI_childBuilder(fallback: $0.fallback, mode: $0.mode)
			        }
			        return Root(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeDeclaredInEnclosingEnum_whenReceivedPropertyNamesIt() async throws {
		// `Parent` forwards and `Child` receives `mode: Mode`, each `Feature.Mode` where it is written: `Root`'s
		// builder function and both mocks take it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Feature.Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Feature.Parent>
				}
				""",
				"""
				public enum Feature {
				    public enum Mode {
				        case fast
				        case slow
				    }

				    @Instantiable(generateMock: true)
				    public final class Parent: Instantiable {
				        public init(mode: Mode, child: Child) {
				            self.mode = mode
				            self.child = child
				        }

				        @Forwarded let mode: Mode
				        @Instantiated let child: Child
				    }

				    @Instantiable(generateMock: true)
				    public final class Child: Instantiable {
				        public init(mode: Mode) {
				            self.mode = mode
				        }

				        @Received let mode: Mode
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    static func mock(
			        mode: Feature.Mode
			    ) -> Feature.Child {
			        return Feature.Child(mode: mode)
			    }
			}
			#endif

			#if DEBUG
			extension Feature.Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            child: ((Feature.Mode) -> Feature.Child)? = nil
			        ) {
			            self.child = child
			        }

			        let child: ((Feature.Mode) -> Feature.Child)?
			    }

			    static func mock(
			        mode: Feature.Mode,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Feature.Parent {
			        let child = if let safeDIBuilder = safeDIOverrides.child { safeDIBuilder(mode) } else { Feature.Child(mode: mode) }
			        return Feature.Parent(mode: mode, child: child)
			    }
			}
			#endif

			#if DEBUG
			extension Feature.Parent {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            child: ((Feature.Mode) -> Feature.Child)? = nil,
			            _ safeDIBuilder: ((Feature.Mode, Feature.Child) -> Feature.Parent)? = nil
			        ) {
			            self.child = child
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let child: ((Feature.Mode) -> Feature.Child)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Feature.Mode, Feature.Child) -> Feature.Parent)?
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_parentBuilder(mode: Feature.Mode) -> Feature.Parent {
			            let child = Feature.Child(mode: mode)
			            return Feature.Parent(mode: mode, child: child)
			        }
			        let parentBuilder = Instantiator<Feature.Parent> {
			            __safeDI_parentBuilder(mode: $0)
			        }
			        self.init(parentBuilder: parentBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            parentBuilder: Feature.Parent.SafeDIMockConfiguration = .init()
			        ) {
			            self.parentBuilder = parentBuilder
			        }

			        let parentBuilder: Feature.Parent.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_parentBuilder(mode: Feature.Mode) -> Feature.Parent {
			            let child = if let safeDIBuilder = safeDIOverrides.parentBuilder.child { safeDIBuilder(mode) } else { Feature.Child(mode: mode) }
			            return if let safeDIBuilder = safeDIOverrides.parentBuilder.safeDIBuilder { safeDIBuilder(mode, child) } else { Feature.Parent(mode: mode, child: child) }
			        }
			        let parentBuilder = Instantiator<Feature.Parent> {
			            __safeDI_parentBuilder(mode: $0)
			        }
			        return Root(parentBuilder: parentBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeNestedInInstantiableType_whenForwardedPropertyNamesIt() async throws {
		// `Mode` and `Style` are nested in `Child` itself, and resolve in its own extension, but not in `Root`'s
		// builder function for `Child`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(childBuilder: Instantiator<Feature.Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Feature.Child>
				}
				""",
				"""
				public enum Feature {
				    @Instantiable
				    public final class Child: Instantiable {
				        public enum Mode {
				            case fast
				            case slow
				        }

				        public enum Style {
				            case plain
				        }

				        public init(mode: Mode, style: Style = .plain) {
				            self.mode = mode
				            self.style = style
				        }

				        @Forwarded let mode: Mode
				        let style: Style
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_childBuilder(mode: Feature.Child.Mode) -> Feature.Child {
			            Feature.Child(mode: mode)
			        }
			        let childBuilder = Instantiator<Feature.Child> {
			            __safeDI_childBuilder(mode: $0)
			        }
			        self.init(childBuilder: childBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            childBuilder: Feature.Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.childBuilder = childBuilder
			        }

			        let childBuilder: Feature.Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_childBuilder(mode: Feature.Child.Mode) -> Feature.Child {
			            if let safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder { safeDIBuilder(mode, safeDIOverrides.childBuilder.style) } else { Feature.Child(mode: mode, style: safeDIOverrides.childBuilder.style) }
			        }
			        let childBuilder = Instantiator<Feature.Child> {
			            __safeDI_childBuilder(mode: $0)
			        }
			        return Root(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            style: Feature.Child.Style = .plain,
			            _ safeDIBuilder: ((Feature.Child.Mode, Feature.Child.Style) -> Feature.Child)? = nil
			        ) {
			            self.style = style
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let style: Feature.Child.Style
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Feature.Child.Mode, Feature.Child.Style) -> Feature.Child)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeDeclaredInEnclosingEnum_whenErasedInstantiatedPropertyNamesIt() async throws {
		// `Parent` instantiates `Impl` erased to `AnyService`, a plain type nested in `Feature`, which `Root`'s tree
		// and mock construct outside `Feature`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(parent: Feature.Parent) {
				        self.parent = parent
				    }

				    @Instantiated let parent: Feature.Parent
				}
				""",
				"""
				public enum Feature {
				    public struct AnyService {
				        public init(_ service: Impl) {
				            self.service = service
				        }

				        let service: Impl
				    }

				    @Instantiable
				    public final class Impl: Instantiable {
				        public init() {}
				    }

				    @Instantiable
				    public final class Parent: Instantiable {
				        public init(service: AnyService) {
				            self.service = service
				        }

				        @Instantiated(fulfilledByType: "Impl", erasedToConcreteExistential: true) let service: AnyService
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_parent() -> Feature.Parent {
			            let service = Feature.AnyService(Feature.Impl())
			            return Feature.Parent(service: service)
			        }
			        let parent: Feature.Parent = __safeDI_parent()
			        self.init(parent: parent)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            parent: Feature.Parent.SafeDIMockConfiguration = .init()
			        ) {
			            self.parent = parent
			        }

			        let parent: Feature.Parent.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_parent() -> Feature.Parent {
			            let service = if let safeDIBuilder = safeDIOverrides.parent.service { safeDIBuilder() } else { Feature.AnyService(Feature.Impl()) }
			            return if let safeDIBuilder = safeDIOverrides.parent.safeDIBuilder { safeDIBuilder(service) } else { Feature.Parent(service: service) }
			        }
			        let parent: Feature.Parent = __safeDI_parent()
			        return Root(parent: parent)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Parent {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            service: (() -> Feature.AnyService)? = nil,
			            _ safeDIBuilder: ((Feature.AnyService) -> Feature.Parent)? = nil
			        ) {
			            self.service = service
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let service: (() -> Feature.AnyService)?
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Feature.AnyService) -> Feature.Parent)?
			    }
			}
			#endif

			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_qualifiesTypeDeclaredInEnclosingEnum_whenDefaultValuedParametersNameItInsideOtherTypes() async throws {
		// Each default-valued parameter names `Mode` inside another type: an array, a set, an optional, a closure, a
		// dictionary, a tuple, and a generic type nested in `Feature`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(child: Feature.Child) {
				        self.child = child
				    }

				    @Instantiated let child: Feature.Child
				}
				""",
				"""
				public enum Feature {
				    public enum Mode: Hashable {
				        case fast
				        case slow
				    }

				    public struct Box<Value> {
				        let value: Value
				    }

				    @Instantiable(generateMock: true)
				    public final class Child: Instantiable {
				        public init(
				            modes: [Mode] = [],
				            set: Set<Mode> = [],
				            optional: Mode? = nil,
				            onChange: @escaping (Mode) -> Void = { _ in },
				            map: [Mode: Mode] = [:],
				            tuple: (Mode, Int) = (.fast, 1),
				            box: Box<Mode>? = nil
				        ) {
				            self.modes = modes
				            self.set = set
				            self.optional = optional
				            self.onChange = onChange
				            self.map = map
				            self.tuple = tuple
				            self.box = box
				        }

				        let modes: [Mode]
				        let set: Set<Mode>
				        let optional: Mode?
				        let onChange: (Mode) -> Void
				        let map: [Mode: Mode]
				        let tuple: (Mode, Int)
				        let box: Box<Mode>?
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    static func mock(
			        modes: [Feature.Mode] = [],
			        set: Set<Feature.Mode> = [],
			        optional: Feature.Mode? = nil,
			        onChange: @escaping (Feature.Mode) -> Void = { _ in },
			        map: [Feature.Mode: Feature.Mode] = [:],
			        tuple: (Feature.Mode, Int) = (.fast, 1),
			        box: Feature.Box<Feature.Mode>? = nil
			    ) -> Feature.Child {
			        return Feature.Child(modes: modes, set: set, optional: optional, onChange: onChange, map: map, tuple: tuple, box: box)
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let child = Feature.Child()
			        self.init(child: child)
			    }
			}
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesNestedType_whenTopLevelTypeOfSameNameExists() async throws {
		// Within `Feature.Child`, `Mode` is `Feature.Mode`, which shadows the top-level `Mode` that generated code
		// outside `Feature` would otherwise name.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Mode {
				    case top
				}

				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(childBuilder: Instantiator<Feature.Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Feature.Child>
				}
				""",
				"""
				public enum Feature {
				    public enum Mode {
				        case fast
				        case slow
				    }

				    @Instantiable(generateMock: true)
				    public final class Child: Instantiable {
				        public init(mode: Mode, other: Mode = .fast) {
				            self.mode = mode
				            self.other = other
				        }

				        @Forwarded let mode: Mode
				        let other: Mode
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    static func mock(
			        mode: Feature.Mode,
			        other: Feature.Mode = .fast
			    ) -> Feature.Child {
			        return Feature.Child(mode: mode, other: other)
			    }
			}
			#endif

			#if DEBUG
			extension Feature.Child {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            other: Feature.Mode = .fast,
			            _ safeDIBuilder: ((Feature.Mode, Feature.Mode) -> Feature.Child)? = nil
			        ) {
			            self.other = other
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let other: Feature.Mode
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Feature.Mode, Feature.Mode) -> Feature.Child)?
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_childBuilder(mode: Feature.Mode) -> Feature.Child {
			            Feature.Child(mode: mode)
			        }
			        let childBuilder = Instantiator<Feature.Child> {
			            __safeDI_childBuilder(mode: $0)
			        }
			        self.init(childBuilder: childBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            childBuilder: Feature.Child.SafeDIMockConfiguration = .init()
			        ) {
			            self.childBuilder = childBuilder
			        }

			        let childBuilder: Feature.Child.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_childBuilder(mode: Feature.Mode) -> Feature.Child {
			            if let safeDIBuilder = safeDIOverrides.childBuilder.safeDIBuilder { safeDIBuilder(mode, safeDIOverrides.childBuilder.other) } else { Feature.Child(mode: mode, other: safeDIOverrides.childBuilder.other) }
			        }
			        let childBuilder = Instantiator<Feature.Child> {
			            __safeDI_childBuilder(mode: $0)
			        }
			        return Root(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTopLevelType_whenInstantiateMethodNamesTypeOfSameNameAsTypeNestedInExtendedTypesEnclosingType() async throws {
		// An extension is written at file scope, so `instantiate(…)` names the top-level `Mode`, not `Feature.Mode`,
		// while `Style`, nested in the extended type, is qualified.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Mode {
				    case top
				}

				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Parent>
				}

				@Instantiable(generateMock: true)
				public final class Parent: Instantiable {
				    public init(mode: Mode, gadget: Feature.Gadget) {
				        self.mode = mode
				        self.gadget = gadget
				    }

				    @Forwarded let mode: Mode
				    @Instantiated let gadget: Feature.Gadget
				}
				""",
				"""
				public enum Feature {
				    public enum Mode {
				        case fast
				    }

				    public struct Gadget {
				        public enum Style {
				            case plain
				        }

				        let mode: Mode
				        let style: Style
				    }
				}

				@Instantiable(generateMock: true)
				extension Feature.Gadget: Instantiable {
				    public static func instantiate(mode: Mode, style: Style = .plain) -> Feature.Gadget {
				        Feature.Gadget(mode: .fast, style: style)
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Feature+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Gadget {
			    static func mock(
			        style: Feature.Gadget.Style = .plain,
			        mode: Mode
			    ) -> Feature.Gadget {
			        return Feature.Gadget.instantiate(mode: mode, style: style)
			    }
			}
			#endif

			#if DEBUG
			extension Feature.Gadget {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            style: Feature.Gadget.Style = .plain,
			            _ safeDIBuilder: ((Mode, Feature.Gadget.Style) -> Feature.Gadget)? = nil
			        ) {
			            self.style = style
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let style: Feature.Gadget.Style
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Mode, Feature.Gadget.Style) -> Feature.Gadget)?
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_parentBuilder(mode: Mode) -> Parent {
			            let gadget: Feature.Gadget = Feature.Gadget.instantiate(mode: mode)
			            return Parent(mode: mode, gadget: gadget)
			        }
			        let parentBuilder = Instantiator<Parent> {
			            __safeDI_parentBuilder(mode: $0)
			        }
			        self.init(parentBuilder: parentBuilder)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            gadget: Feature.Gadget.SafeDIMockConfiguration = .init()
			        ) {
			            self.gadget = gadget
			        }

			        let gadget: Feature.Gadget.SafeDIMockConfiguration
			    }

			    static func mock(
			        mode: Mode,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_gadget() -> Feature.Gadget {
			            return if let safeDIBuilder = safeDIOverrides.gadget.safeDIBuilder { safeDIBuilder(mode, safeDIOverrides.gadget.style) } else { Feature.Gadget.instantiate(mode: mode, style: safeDIOverrides.gadget.style) }
			        }
			        let gadget: Feature.Gadget = __safeDI_gadget()
			        return Parent(mode: mode, gadget: gadget)
			    }
			}
			#endif

			#if DEBUG
			extension Parent {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            gadget: Feature.Gadget.SafeDIMockConfiguration = .init(),
			            _ safeDIBuilder: ((Mode, Feature.Gadget) -> Parent)? = nil
			        ) {
			            self.gadget = gadget
			            self.safeDIBuilder = safeDIBuilder
			        }

			        let gadget: Feature.Gadget.SafeDIMockConfiguration
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        let safeDIBuilder: ((Mode, Feature.Gadget) -> Parent)?
			    }
			}
			#endif

			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            parentBuilder: Parent.SafeDIMockConfiguration = .init()
			        ) {
			            self.parentBuilder = parentBuilder
			        }

			        let parentBuilder: Parent.SafeDIMockConfiguration
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_parentBuilder(mode: Mode) -> Parent {
			            func __safeDI_gadget() -> Feature.Gadget {
			                return if let safeDIBuilder = safeDIOverrides.parentBuilder.gadget.safeDIBuilder { safeDIBuilder(mode, safeDIOverrides.parentBuilder.gadget.style) } else { Feature.Gadget.instantiate(mode: mode, style: safeDIOverrides.parentBuilder.gadget.style) }
			            }
			            let gadget: Feature.Gadget = __safeDI_gadget()
			            return if let safeDIBuilder = safeDIOverrides.parentBuilder.safeDIBuilder { safeDIBuilder(mode, gadget) } else { Parent(mode: mode, gadget: gadget) }
			        }
			        let parentBuilder = Instantiator<Parent> {
			            __safeDI_parentBuilder(mode: $0)
			        }
			        return Root(parentBuilder: parentBuilder)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsTopLevelType_whenInstantiateMethodOfExtensionNamesTypeOfSameNameAsInstantiableNestedInEnclosingType() async throws {
		// An extension is written at file scope, so `instantiate(…)` names the top-level `Service`, not the
		// `@Instantiable` `Feature.Service` nested in the extended type's enclosing type.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: Service, gadget: Feature.Gadget) {
				        self.service = service
				        self.gadget = gadget
				    }

				    @Instantiated let service: Service
				    @Instantiated let gadget: Feature.Gadget
				}

				@Instantiable
				public final class Service: Instantiable {
				    public init() {}
				}
				""",
				"""
				public enum Feature {
				    @Instantiable
				    public final class Service: Instantiable {
				        public init() {}
				    }

				    public struct Gadget {
				        let service: Feature.Service?
				        let topLevelService: Any
				    }
				}

				@Instantiable
				extension Feature.Gadget: Instantiable {
				    public static func instantiate(service: Service) -> Feature.Gadget {
				        Feature.Gadget(service: nil, topLevelService: service)
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service = Service()
			        let gadget: Feature.Gadget = Feature.Gadget.instantiate(service: service)
			        self.init(service: service, gadget: gadget)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeDeclaredInEnclosingEnum_whenPublicMocksReceivedPropertyNamesIt() async throws {
		// `Child`'s public mock takes the `mode` its tree receives, and `Parent`'s builder function takes it in
		// `Root`'s tree.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(parentBuilder: Instantiator<Feature.Parent>) {
				        self.parentBuilder = parentBuilder
				    }

				    @Instantiated let parentBuilder: Instantiator<Feature.Parent>
				}
				""",
				"""
				public enum Feature {
				    public enum Mode: Sendable {
				        case fast
				        case slow
				    }

				    @Instantiable
				    public final class Parent: Instantiable {
				        public init(mode: Mode, child: Child) {
				            self.mode = mode
				            self.child = child
				        }

				        @Forwarded let mode: Mode
				        @Instantiated let child: Child
				    }

				    @Instantiable(generateMock: .public)
				    public final class Child: Instantiable {
				        public init(mode: Mode, other: Mode = .fast) {
				            self.mode = mode
				            self.other = other
				        }

				        @Received let mode: Mode
				        let other: Mode
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    public static func mock(
			        other: Feature.Mode? = nil,
			        mode: Feature.Mode
			    ) -> Feature.Child {
			        let other = other ?? (.fast)
			        return Feature.Child(mode: mode, other: other)
			    }
			}

			extension Feature.Child {
			    public enum __safeDI_Feature_Child_mock_CAE37D51BE9A7B32 {}
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_parentBuilder(mode: Feature.Mode) -> Feature.Parent {
			            let child = Feature.Child(mode: mode)
			            return Feature.Parent(mode: mode, child: child)
			        }
			        let parentBuilder = Instantiator<Feature.Parent> {
			            __safeDI_parentBuilder(mode: $0)
			        }
			        self.init(parentBuilder: parentBuilder)
			    }
			}
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_qualifiesTypeDeclaredInEnclosingEnum_whenSeamsTreeReceivesIt() async throws {
		// `Screen`'s generated initializer takes the `mode` its tree receives, in `extension Feature.Screen`, where
		// `Mode` does not resolve.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				public enum Feature {
				    public enum Mode: Sendable {
				        case fast
				        case slow
				    }

				    @Instantiable(generateDependencyTree: true)
				    public struct Screen: Instantiable {
				        public init(child: Child) {
				            self.child = child
				        }

				        @Instantiated let child: Child
				    }

				    @Instantiable
				    public struct Child: Instantiable {
				        public init(mode: Mode) {
				            self.mode = mode
				        }

				        @Received let mode: Mode
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Screen+SafeDI.swift": generatedFileHeader + """
			extension Feature.Screen {
			    public init(mode __safeDI_mode: @autoclosure @escaping () -> Feature.Mode) {
			        let mode = LazilyInstantiated<Feature.Mode>(__safeDI_mode)
			        let child = Feature.Child(mode: mode.instance)
			        self.init(child: child)
			    }
			}

			extension Feature.Screen {
			    public enum __safeDI_Feature_Screen_FB56998D446A1ACE {}
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsTree_whenReceiverNamesTypeNestedInItUnqualifiedAndForwarderQualified() async throws {
		// `Child` forwards `value: Grandchild.NestedType`, which `Grandchild` receives as `value: NestedType`: one
		// type, which SafeDI used to report as unfulfillable.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(childBuilder: Instantiator<Child>) {
				        self.childBuilder = childBuilder
				    }

				    @Instantiated let childBuilder: Instantiator<Child>
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(value: Grandchild.NestedType, grandchild: Grandchild) {
				        self.value = value
				        self.grandchild = grandchild
				    }

				    @Forwarded let value: Grandchild.NestedType
				    @Instantiated let grandchild: Grandchild
				}
				""",
				"""
				@Instantiable
				public final class Grandchild: Instantiable {
				    public struct NestedType {}

				    public init(value: NestedType) {
				        self.value = value
				    }

				    @Received let value: NestedType
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        func __safeDI_childBuilder(value: Grandchild.NestedType) -> Child {
			            let grandchild = Grandchild(value: value)
			            return Child(value: value, grandchild: grandchild)
			        }
			        let childBuilder = Instantiator<Child> {
			            __safeDI_childBuilder(value: $0)
			        }
			        self.init(childBuilder: childBuilder)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fulfillsQualifiedReceive_whenNestedTypeFulfillsProtocolDeclaredBesideItAndSpelledUnqualified() async throws {
		// `Service` lists `ServiceProtocol`, declared beside it in `Feature`, unqualified: `Root` receives it as
		// `Feature.ServiceProtocol` and `Consumer` as `ServiceProtocol`, one type, which SafeDI used to report as
		// unfulfillable.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public final class Root: Instantiable {
				    public init(service: Feature.ServiceProtocol, consumer: Feature.Consumer) {
				        self.service = service
				        self.consumer = consumer
				    }

				    @Instantiated let service: Feature.ServiceProtocol
				    @Instantiated let consumer: Feature.Consumer
				}
				""",
				"""
				public enum Feature {
				    public protocol ServiceProtocol {}

				    @Instantiable(fulfillingAdditionalTypes: [ServiceProtocol.self])
				    public final class Service: Instantiable, ServiceProtocol {
				        public init() {}
				    }

				    @Instantiable
				    public final class Consumer: Instantiable {
				        public init(service: ServiceProtocol) {
				            self.service = service
				        }

				        @Received let service: ServiceProtocol
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service: Feature.ServiceProtocol = Feature.Service()
			        let consumer = Feature.Consumer(service: service)
			        self.init(service: service, consumer: consumer)
			    }
			}
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            service: (() -> Feature.ServiceProtocol)? = nil,
			            consumer: ((Feature.ServiceProtocol) -> Feature.Consumer)? = nil
			        ) {
			            self.service = service
			            self.consumer = consumer
			        }

			        let service: (() -> Feature.ServiceProtocol)?
			        let consumer: ((Feature.ServiceProtocol) -> Feature.Consumer)?
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let service: Feature.ServiceProtocol = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Feature.Service() }
			        let consumer = if let safeDIBuilder = safeDIOverrides.consumer { safeDIBuilder(service) } else { Feature.Consumer(service: service) }
			        return Root(service: service, consumer: consumer)
			    }
			}
			#endif
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_fulfillsQualifiedReceive_whenNestedTypeFulfillsCompositionOfProtocolsDeclaredBesideItAndSpelledUnqualified() async throws {
		// `Service` lists the composition of `Logging` and `Tracing`, declared beside it in `Feature`, unqualified: no
		// option of a composition nests it in `Feature`, so it is kept, and each protocol in it is qualified. `Root`
		// receives it qualified and `Consumer` unqualified, one type.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(service: any Feature.Logging & Feature.Tracing, consumer: Feature.Consumer) {
				        self.service = service
				        self.consumer = consumer
				    }

				    @Instantiated let service: any Feature.Logging & Feature.Tracing
				    @Instantiated let consumer: Feature.Consumer
				}
				""",
				"""
				public enum Feature {
				    public protocol Logging {}
				    public protocol Tracing {}

				    @Instantiable(fulfillingAdditionalTypes: [(Logging & Tracing).self])
				    public final class Service: Instantiable, Logging, Tracing {
				        public init() {}
				    }

				    @Instantiable
				    public final class Consumer: Instantiable {
				        public init(service: any Logging & Tracing) {
				            self.service = service
				        }

				        @Received let service: any Logging & Tracing
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let service: any (Feature.Logging & Feature.Tracing) = Feature.Service()
			        let consumer = Feature.Consumer(service: service)
			        self.init(service: service, consumer: consumer)
			    }
			}
			""",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_qualifiesTypeDeclaredInEnclosingEnum_whenItsRawIdentifierNameHoldsPeriod() async throws {
		// A declaration's key joins its names with periods, so `Mode.Kind`'s key reads as a type `Kind` nested in
		// `Feature.Mode`. `Child`'s mock is declared in `extension Feature.Child`, where `Mode.Kind`, declared in
		// `Feature`, does not resolve.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true)
				public final class Root: Instantiable {
				    public init(child: Feature.Child) {
				        self.child = child
				    }

				    @Instantiated let child: Feature.Child
				}
				""",
				"""
				public enum Feature {
				    public enum `Mode.Kind` {
				        case fast
				        case slow
				    }

				    @Instantiable(generateMock: true)
				    public final class Child: Instantiable {
				        public init(mode: `Mode.Kind` = .fast) {
				            self.mode = mode
				        }

				        let mode: `Mode.Kind`
				    }
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.generatedFiles == [
			"Child+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Feature.Child {
			    static func mock(
			        mode: Feature.`Mode.Kind` = .fast
			    ) -> Feature.Child {
			        return Feature.Child(mode: mode)
			    }
			}
			#endif
			""",
			"Root+SafeDI.swift": generatedFileHeader + """
			extension Root {
			    public convenience init() {
			        let child = Feature.Child()
			        self.init(child: child)
			    }
			}
			""",
			"SafeDIMockConfiguration.swift": generatedFileHeader,
		])
	}

	// MARK: Tests – across modules

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_keepsTopLevelType_whenModulesOwnNamespaceShadowsDependencysNamespaceThatNestsTypeOfSameName(integration: MultiModuleIntegration) async throws {
		// `App` declares its own `Constants`, which shadows `Core`'s throughout `App`, so `Mode` inside `App`'s
		// `Constants.Child` is `App`'s top-level `Mode`, not `Core`'s `Constants.Mode`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.coreDeclaringConstantsWithNestedMode,
				ModuleFixture(
					name: "App",
					packageName: "pkg",
					swiftFileContentByFilePath: [
						"Constants.swift": """
						import Core
						import SafeDI

						public enum Mode {
						    case fromApp
						}

						public enum Constants {
						    @Instantiable(generateMock: true)
						    public final class Child: Instantiable {
						        public init(mode: Mode = .fromApp) {
						            self.mode = mode
						        }

						        let mode: Mode
						    }
						}
						""",
						"Root.swift": Self.rootInstantiatingConstantsChild,
					],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		Self.expectAppGeneratedFiles(of: output, under: integration, childMock: """
		#if DEBUG
		extension Constants.Child {
		    static func mock(
		        mode: Mode = .fromApp
		    ) -> Constants.Child {
		        return Constants.Child(mode: mode)
		    }
		}
		#endif
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_qualifiesTypeNestedInDependencysNamespace_whenModuleExtendsThatNamespace(integration: MultiModuleIntegration) async throws {
		// `App` extends `Core`'s `Constants` rather than declaring its own, so `Mode` inside `Constants.Child` is
		// `Core`'s `Constants.Mode`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				Self.coreDeclaringConstantsWithNestedMode,
				ModuleFixture(
					name: "App",
					packageName: "pkg",
					swiftFileContentByFilePath: [
						"Constants.swift": """
						import Core
						import SafeDI

						extension Constants {
						    @Instantiable(generateMock: true)
						    public final class Child: Instantiable {
						        public init(mode: Mode = .fromCore) {
						            self.mode = mode
						        }

						        let mode: Mode
						    }
						}
						""",
						"Root.swift": Self.rootInstantiatingConstantsChild,
					],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		Self.expectAppGeneratedFiles(of: output, under: integration, childMock: """
		#if DEBUG
		extension Constants.Child {
		    static func mock(
		        mode: Constants.Mode = .fromCore
		    ) -> Constants.Child {
		        return Constants.Child(mode: mode)
		    }
		}
		#endif
		""")
		try expectEveryModuleCompiled(output)
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_qualifiesTopLevelTypeOfModuleByModulesName_whenDeclarationIsNestedInTypeSpelledWithThatModulesName(integration: MultiModuleIntegration) async throws {
		// `Child` is nested in `Core.Namespace`, so `Core.Mode` is an option for `Mode`, and names `Core`'s top-level
		// `Mode`, though no nested declaration is named `Mode`.
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(
					name: "Core",
					packageName: "pkg",
					swiftFileContentByFilePath: [
						"Core.swift": """
						import SafeDI

						public enum Mode {
						    case fromCore
						}

						public enum Namespace {}

						@Instantiable
						public final class Service: Instantiable {
						    public init(mode: Mode = .fromCore) {
						        self.mode = mode
						    }

						    let mode: Mode
						}
						""",
					],
				),
				ModuleFixture(
					name: "App",
					packageName: "pkg",
					swiftFileContentByFilePath: [
						"Namespace.swift": """
						import Core
						import SafeDI

						extension Core.Namespace {
						    @Instantiable(generateMock: true)
						    public final class Child: Instantiable {
						        public init(mode: Mode = .fromCore) {
						            self.mode = mode
						        }

						        let mode: Mode
						    }
						}
						""",
						"Root.swift": """
						import Core
						import SafeDI

						@Instantiable(isRoot: true)
						public final class Root: Instantiable {
						    public init(child: Core.Namespace.Child) {
						        self.child = child
						    }

						    @Instantiated let child: Core.Namespace.Child
						}
						""",
					],
					dependencies: ["Core"],
				),
			],
			integration: integration,
			filesToDelete: &filesToDelete,
		)

		let imports = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""
		let rootTree = """
		extension Root {
		    public convenience init() {
		        let child = Core.Namespace.Child()
		        self.init(child: child)
		    }
		}
		"""
		let childMock = """
		#if DEBUG
		extension Core.Namespace.Child {
		    static func mock(
		        mode: Core.Mode = .fromCore
		    ) -> Core.Namespace.Child {
		        return Core.Namespace.Child(mode: mode)
		    }
		}
		#endif
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + imports + rootTree + "\n\n" + childMock])
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles == [
				"Namespace+SafeDIMock.swift": generatedFileHeader + imports + childMock,
				"Root+SafeDI.swift": generatedFileHeader + imports + rootTree,
				"SafeDIMockConfiguration.swift": generatedFileHeader + imports,
			])
		}
		try expectEveryModuleCompiled(output)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A `Core` module declaring a namespace `Constants` with a nested `Mode`, and an `@Instantiable` nested in it, so
	/// that a `.safedi` of `Core` keeps the declaration of `Constants.Mode`.
	private static let coreDeclaringConstantsWithNestedMode = ModuleFixture(
		name: "Core",
		packageName: "pkg",
		swiftFileContentByFilePath: [
			"Constants.swift": """
			import SafeDI

			public enum Constants {
			    public enum Mode {
			        case fromCore
			    }
			}

			extension Constants {
			    @Instantiable
			    public final class Service: Instantiable {
			        public init() {}
			    }
			}
			""",
		],
	)

	/// A root of `App` that instantiates `Constants.Child`.
	private static let rootInstantiatingConstantsChild = """
	import Core
	import SafeDI

	@Instantiable(isRoot: true)
	public final class Root: Instantiable {
	    public init(child: Constants.Child) {
	        self.child = child
	    }

	    @Instantiated let child: Constants.Child
	}
	"""

	/// Expects `App` to have generated `Root`'s tree and `childMock`, the mock of `Constants.Child`, under `integration`.
	private static func expectAppGeneratedFiles(of output: MultiModuleTestOutput, under integration: MultiModuleIntegration, childMock: String, sourceLocation: SourceLocation = #_sourceLocation) {
		let imports = """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif


		"""
		let rootTree = """
		extension Root {
		    public convenience init() {
		        let child = Constants.Child()
		        self.init(child: child)
		    }
		}
		"""
		switch integration {
		case .moduleInfo:
			#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + imports + rootTree + "\n\n" + childMock], sourceLocation: sourceLocation)
		case .swiftPackagePlugin:
			#expect(output.modules["App"]?.generatedFiles == [
				"Constants+SafeDIMock.swift": generatedFileHeader + imports + childMock,
				"Root+SafeDI.swift": generatedFileHeader + imports + rootTree,
				"SafeDIMockConfiguration.swift": generatedFileHeader + imports,
			], sourceLocation: sourceLocation)
		}
	}

	/// Expects every module to have compiled, when compile verification runs.
	private func expectEveryModuleCompiled(_ output: MultiModuleTestOutput, sourceLocation: SourceLocation = #_sourceLocation) throws {
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation, sourceLocation: sourceLocation)
		#expect(compilation.modules.map(\.moduleName) == output.moduleNames, sourceLocation: sourceLocation)
		#expect(compilation.failure == nil, sourceLocation: sourceLocation)
	}
}
