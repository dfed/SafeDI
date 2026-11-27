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

/// An internal mock root whose tree holds a loop of builders, laid out from the node records of its world
/// (`NodeRecords+Loops.swift`): each member's function begins by making again the members its tree receives, a loop the
/// root declares whose members are handed nothing keeps the walk's bytes, a loop at a level below it hands its members
/// the level's configuration (approved difference 16), and the values equal the walk's with an override at every member.
struct SafeDIToolNodeRecordsMockLoopTests: ~Copyable {
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

	/// A loop the mock root declares whose members are handed nothing keeps the walk's bytes.
	@Test
	mutating func mock_laysOutLoopAsTheWalkWritesIt_whenRootDeclaresLoopOfPlainBuilders() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: Instantiator<A>
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == walkOutput.mockFiles["Root+SafeDIMock.swift"])
	}

	/// A loop of `@Sendable` builders the mock root declares binds each member's local before the first member, as the walk does.
	@Test
	mutating func mock_laysOutLoopAsTheWalkWritesIt_whenRootDeclaresLoopOfSendableBuilders() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(aBuilder: SendableInstantiator<A>, bBuilder: SendableInstantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: SendableInstantiator<A>
			    @Instantiated let bBuilder: SendableInstantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: SendableInstantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: SendableInstantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: SendableInstantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: SendableInstantiator<A>
			}
			""",
		]
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == walkOutput.mockFiles["Root+SafeDIMock.swift"])
	}

	/// A loop at a level below the root: each member takes the level's configuration after its own and hands each member it makes again that member's field of it (approved difference 16).
	@Test
	mutating func mock_handsMembersTheirLevelsConfiguration_whenLoopIsAtLevelBelowRoot() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(holder: Holder) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let holder: Holder
			}
			""",
			"""
			@Instantiable
			public final class Holder: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			    @Instantiated let cBuilder: Instantiator<C>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>, leaf: Leaf) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: Instantiator<B>
			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>, cBuilder: Instantiator<C>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: Instantiator<A>
			    @Received let cBuilder: Instantiator<C>
			}
			""",
			"""
			@Instantiable
			public final class C: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: Instantiator<A>
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init() {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			}
			""",
		]
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            holder: Holder.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                holder: holder
		            )
		        }

		        var holder: Holder.SafeDIMockConfiguration { __safeDI_storage.holder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                holder: Holder.SafeDIMockConfiguration
		            ) {
		                self.holder = holder
		            }

		            let holder: Holder.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_aBuilder(safeDIOverrides: A.SafeDIMockConfiguration, __safeDI_Holder_loopConfiguration: Holder.SafeDIMockConfiguration) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.bBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_loopConfiguration)
		            }
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(bBuilder, leaf) } else { A(bBuilder: bBuilder, leaf: leaf) }
		        }
		        func __safeDI_bBuilder(safeDIOverrides: ((Instantiator<A>, Instantiator<C>) -> B)?, __safeDI_Holder_loopConfiguration: Holder.SafeDIMockConfiguration) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.aBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_loopConfiguration)
		            }
		            let cBuilder = Instantiator<C> {
		                __safeDI_cBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.cBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_loopConfiguration)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(aBuilder, cBuilder) } else { B(aBuilder: aBuilder, cBuilder: cBuilder) }
		        }
		        func __safeDI_cBuilder(safeDIOverrides: ((Instantiator<A>) -> C)?, __safeDI_Holder_loopConfiguration: Holder.SafeDIMockConfiguration) -> C {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.aBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_loopConfiguration)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(aBuilder) } else { C(aBuilder: aBuilder) }
		        }
		        func __safeDI_holder(safeDIOverrides: Holder.SafeDIMockConfiguration) -> Holder {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: safeDIOverrides.aBuilder, __safeDI_Holder_loopConfiguration: safeDIOverrides)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(safeDIOverrides: safeDIOverrides.bBuilder, __safeDI_Holder_loopConfiguration: safeDIOverrides)
		            }
		            let cBuilder = Instantiator<C> {
		                __safeDI_cBuilder(safeDIOverrides: safeDIOverrides.cBuilder, __safeDI_Holder_loopConfiguration: safeDIOverrides)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(aBuilder, bBuilder, cBuilder) } else { Holder(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder) }
		        }
		        let holder: Holder = __safeDI_holder(safeDIOverrides: safeDIOverrides.holder)
		        return Root(holder: holder)
		    }
		}
		#endif
		""")
	}

	/// A loop at the root with a configured member: each member that makes again a member taking overrides takes `mock()`'s, so the members' functions read them where the walk reads `mock()`'s parameter.
	@Test
	mutating func mock_handsMembersMocksOverrides_whenLoopAtRootHasConfiguredMember() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>, leaf: Leaf) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: Instantiator<B>
			    @Instantiated let leaf: Leaf
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: Instantiator<A>
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init() {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			}
			""",
		]
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            aBuilder: A.SafeDIMockConfiguration = .init(),
		            bBuilder: ((Instantiator<A>) -> B)? = nil
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                aBuilder: aBuilder,
		                bBuilder: bBuilder
		            )
		        }

		        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }
		        var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                aBuilder: A.SafeDIMockConfiguration,
		                bBuilder: ((Instantiator<A>) -> B)?
		            ) {
		                self.aBuilder = aBuilder
		                self.bBuilder = bBuilder
		            }

		            let aBuilder: A.SafeDIMockConfiguration
		            let bBuilder: ((Instantiator<A>) -> B)?
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_aBuilder(safeDIOverrides: A.SafeDIMockConfiguration, __safeDI_Root_loopConfiguration: SafeDIOverrides) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(__safeDI_Root_loopConfiguration: __safeDI_Root_loopConfiguration)
		            }
		            let leaf = if let safeDIBuilder = safeDIOverrides.leaf { safeDIBuilder() } else { Leaf() }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(bBuilder, leaf) } else { A(bBuilder: bBuilder, leaf: leaf) }
		        }
		        func __safeDI_bBuilder(__safeDI_Root_loopConfiguration: SafeDIOverrides) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: __safeDI_Root_loopConfiguration.aBuilder, __safeDI_Root_loopConfiguration: __safeDI_Root_loopConfiguration)
		            }
		            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
		        }
		        let aBuilder = Instantiator<A> {
		            __safeDI_aBuilder(safeDIOverrides: safeDIOverrides.aBuilder, __safeDI_Root_loopConfiguration: safeDIOverrides)
		        }
		        let bBuilder = Instantiator<B> {
		            __safeDI_bBuilder(__safeDI_Root_loopConfiguration: safeDIOverrides)
		        }
		        return Root(aBuilder: aBuilder, bBuilder: bBuilder)
		    }
		}
		#endif
		""")
	}

	/// A property whose builder function is named as the level's argument would be: the argument takes a trailing underscore.
	@Test
	mutating func mock_namesLevelArgumentApart_whenPropertyLabelMatchesItsName() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(holder: Holder) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let holder: Holder
			}
			""",
			"""
			@Instantiable
			public final class Holder: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, Holder_loopConfiguration: Instantiator<Leaf>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			    @Instantiated let Holder_loopConfiguration: Instantiator<Leaf>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: Instantiator<A>
			}
			""",
			"""
			@Instantiable
			public final class Leaf: Instantiable {
			    public init() {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			}
			""",
		]
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            holder: Holder.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                holder: holder
		            )
		        }

		        var holder: Holder.SafeDIMockConfiguration { __safeDI_storage.holder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                holder: Holder.SafeDIMockConfiguration
		            ) {
		                self.holder = holder
		            }

		            let holder: Holder.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_aBuilder(safeDIOverrides: ((Instantiator<B>) -> A)?, __safeDI_Holder_loopConfiguration_: Holder.SafeDIMockConfiguration) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration_.bBuilder, __safeDI_Holder_loopConfiguration_: __safeDI_Holder_loopConfiguration_)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
		        }
		        func __safeDI_bBuilder(safeDIOverrides: ((Instantiator<A>) -> B)?, __safeDI_Holder_loopConfiguration_: Holder.SafeDIMockConfiguration) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration_.aBuilder, __safeDI_Holder_loopConfiguration_: __safeDI_Holder_loopConfiguration_)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
		        }
		        func __safeDI_Holder_loopConfiguration(safeDIOverrides: (() -> Leaf)?) -> Leaf {
		            if let safeDIBuilder = safeDIOverrides { safeDIBuilder() } else { Leaf() }
		        }
		        func __safeDI_holder(safeDIOverrides: Holder.SafeDIMockConfiguration) -> Holder {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: safeDIOverrides.aBuilder, __safeDI_Holder_loopConfiguration_: safeDIOverrides)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(safeDIOverrides: safeDIOverrides.bBuilder, __safeDI_Holder_loopConfiguration_: safeDIOverrides)
		            }
		            let Holder_loopConfiguration = Instantiator<Leaf> {
		                __safeDI_Holder_loopConfiguration(safeDIOverrides: safeDIOverrides.Holder_loopConfiguration)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(aBuilder, bBuilder, Holder_loopConfiguration) } else { Holder(aBuilder: aBuilder, bBuilder: bBuilder, Holder_loopConfiguration: Holder_loopConfiguration) }
		        }
		        let holder: Holder = __safeDI_holder(safeDIOverrides: safeDIOverrides.holder)
		        return Root(holder: holder)
		    }
		}
		#endif
		""")
	}

	/// Two levels whose types spell one identifier (`Outer.Holder`, `Outer_Holder`): the level claimed second takes a trailing underscore.
	@Test
	mutating func mock_namesLevelArgumentsApart_whenNestedTypeAndTopLevelTypeShareIdentifier() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(outerHolder: Outer.Holder, flatHolder: Outer_Holder) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let outerHolder: Outer.Holder
			    @Instantiated let flatHolder: Outer_Holder
			}
			""",
			"""
			public enum Outer {}
			extension Outer {
			@Instantiable
			public final class Holder: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			}
			}
			""",
			"""
			@Instantiable
			public final class Outer_Holder: Instantiable {
			    public init(cBuilder: Instantiator<C>, dBuilder: Instantiator<D>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let cBuilder: Instantiator<C>
			    @Instantiated let dBuilder: Instantiator<D>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: Instantiator<A>
			}
			""",
			"""
			@Instantiable
			public final class C: Instantiable {
			    public init(dBuilder: Instantiator<D>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let dBuilder: Instantiator<D>
			}
			""",
			"""
			@Instantiable
			public final class D: Instantiable {
			    public init(cBuilder: Instantiator<C>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let cBuilder: Instantiator<C>
			}
			""",
		]
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		#expect(output.mockFiles["Root+SafeDIMock.swift"] == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            outerHolder: Outer.Holder.SafeDIMockConfiguration = .init(),
		            flatHolder: Outer_Holder.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                outerHolder: outerHolder,
		                flatHolder: flatHolder
		            )
		        }

		        var outerHolder: Outer.Holder.SafeDIMockConfiguration { __safeDI_storage.outerHolder }
		        var flatHolder: Outer_Holder.SafeDIMockConfiguration { __safeDI_storage.flatHolder }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                outerHolder: Outer.Holder.SafeDIMockConfiguration,
		                flatHolder: Outer_Holder.SafeDIMockConfiguration
		            ) {
		                self.outerHolder = outerHolder
		                self.flatHolder = flatHolder
		            }

		            let outerHolder: Outer.Holder.SafeDIMockConfiguration
		            let flatHolder: Outer_Holder.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_aBuilder(safeDIOverrides: ((Instantiator<B>) -> A)?, __safeDI_Outer_Holder_loopConfiguration: Outer.Holder.SafeDIMockConfiguration) -> A {
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(safeDIOverrides: __safeDI_Outer_Holder_loopConfiguration.bBuilder, __safeDI_Outer_Holder_loopConfiguration: __safeDI_Outer_Holder_loopConfiguration)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
		        }
		        func __safeDI_bBuilder(safeDIOverrides: ((Instantiator<A>) -> B)?, __safeDI_Outer_Holder_loopConfiguration: Outer.Holder.SafeDIMockConfiguration) -> B {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: __safeDI_Outer_Holder_loopConfiguration.aBuilder, __safeDI_Outer_Holder_loopConfiguration: __safeDI_Outer_Holder_loopConfiguration)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
		        }
		        func __safeDI_outerHolder(safeDIOverrides: Outer.Holder.SafeDIMockConfiguration) -> Outer.Holder {
		            let aBuilder = Instantiator<A> {
		                __safeDI_aBuilder(safeDIOverrides: safeDIOverrides.aBuilder, __safeDI_Outer_Holder_loopConfiguration: safeDIOverrides)
		            }
		            let bBuilder = Instantiator<B> {
		                __safeDI_bBuilder(safeDIOverrides: safeDIOverrides.bBuilder, __safeDI_Outer_Holder_loopConfiguration: safeDIOverrides)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(aBuilder, bBuilder) } else { Outer.Holder(aBuilder: aBuilder, bBuilder: bBuilder) }
		        }
		        let outerHolder: Outer.Holder = __safeDI_outerHolder(safeDIOverrides: safeDIOverrides.outerHolder)
		        func __safeDI_cBuilder(safeDIOverrides: ((Instantiator<D>) -> C)?, __safeDI_Outer_Holder_loopConfiguration_: Outer_Holder.SafeDIMockConfiguration) -> C {
		            let dBuilder = Instantiator<D> {
		                __safeDI_dBuilder(safeDIOverrides: __safeDI_Outer_Holder_loopConfiguration_.dBuilder, __safeDI_Outer_Holder_loopConfiguration_: __safeDI_Outer_Holder_loopConfiguration_)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(dBuilder) } else { C(dBuilder: dBuilder) }
		        }
		        func __safeDI_dBuilder(safeDIOverrides: ((Instantiator<C>) -> D)?, __safeDI_Outer_Holder_loopConfiguration_: Outer_Holder.SafeDIMockConfiguration) -> D {
		            let cBuilder = Instantiator<C> {
		                __safeDI_cBuilder(safeDIOverrides: __safeDI_Outer_Holder_loopConfiguration_.cBuilder, __safeDI_Outer_Holder_loopConfiguration_: __safeDI_Outer_Holder_loopConfiguration_)
		            }
		            return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(cBuilder) } else { D(cBuilder: cBuilder) }
		        }
		        func __safeDI_flatHolder(safeDIOverrides: Outer_Holder.SafeDIMockConfiguration) -> Outer_Holder {
		            let cBuilder = Instantiator<C> {
		                __safeDI_cBuilder(safeDIOverrides: safeDIOverrides.cBuilder, __safeDI_Outer_Holder_loopConfiguration_: safeDIOverrides)
		            }
		            let dBuilder = Instantiator<D> {
		                __safeDI_dBuilder(safeDIOverrides: safeDIOverrides.dBuilder, __safeDI_Outer_Holder_loopConfiguration_: safeDIOverrides)
		            }
		            return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(cBuilder, dBuilder) } else { Outer_Holder(cBuilder: cBuilder, dBuilder: dBuilder) }
		        }
		        let flatHolder: Outer_Holder = __safeDI_flatHolder(safeDIOverrides: safeDIOverrides.flatHolder)
		        return Root(outerHolder: outerHolder, flatHolder: flatHolder)
		    }
		}
		#endif
		""")
	}

	/// A loop of `@Sendable` builders below the root stays refused: its members' functions could capture no configuration that is not `Sendable`.
	@Test
	mutating func mock_refusesLoop_whenSendableMembersWouldTakeTheirLevelsConfiguration() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(holder: Holder) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let holder: Holder
			}
			""",
			"""
			@Instantiable
			public final class Holder: Instantiable {
			    public init(aBuilder: SendableInstantiator<A>, bBuilder: SendableInstantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: SendableInstantiator<A>
			    @Instantiated let bBuilder: SendableInstantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: SendableInstantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: SendableInstantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: SendableInstantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: SendableInstantiator<A>
			}
			""",
		]
		let (_, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["builderLoop"]])
	}

	/// A loop closed through a rename its level declares stays refused: the loop's step makes nothing again of the renamed member.
	@Test
	mutating func mock_refusesLoop_whenMemberIsReceivedUnderRenameItsLevelDeclares() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class Root: Instantiable {
			    public init(holder: Holder) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let holder: Holder
			}
			""",
			"""
			@Instantiable
			public final class Holder: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, otherBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Instantiated let aBuilder: Instantiator<A>
			    @Instantiated let bBuilder: Instantiator<B>
			    @Received(fulfilledByDependencyNamed: "aBuilder", ofType: Instantiator<A>.self) let otherBuilder: Instantiator<A>
			}
			""",
			"""
			@Instantiable
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(otherBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let otherBuilder: Instantiator<A>
			}
			""",
		]
		let (_, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["builderLoop"]])
	}

	/// Each member's override at a loop's level, set in turn and then all together, is read on every lap: the values
	/// equal the walk's after the loop is walked twice.
	@Test(arguments: ["level", "root"])
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsTheWalksValues_whenEveryMemberOfLoopIsOverriddenOnEveryLap(name: String) async throws {
		let fixture = try #require(Self.valueFixtures[name])
		let walkOutput = try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let (output, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: [], swiftFileContentByFilePath: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.isLaidOutFromNodeRecords) == [true])
		let (probes, markers) = try #require(Self.valueProbes[name])
		let comparison = try await DifferentialValueOracle.compare(
			feature: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixture, generatedFiles: #require(walkOutput.generatedFiles)),
			probes: probes,
			filesToDelete: &filesToDelete,
		)
		// Nothing is compared where compile verification is off.
		guard let comparison else { return }
		#expect(comparison.differences.isEmpty, "\(comparison.report)")
		// Every override was read: each marks the value its closure built.
		for marker in markers {
			#expect(comparison.featureDescription.contains("\"\(marker)\""), "No value is marked \(marker):\n\(comparison.featureDescription)")
		}
	}

	/// A member the mock root promotes only because another member's tree receives it stays refused: the walk binds no wrapper of it, which the root's body would bind unread.
	@Test
	mutating func mock_refusesLoop_whenMockRootPromotesMemberOnlyForItsLoop() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public final class A: Instantiable {
			    public init(bBuilder: Instantiator<B>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public final class B: Instantiable {
			    public init(aBuilder: Instantiator<A>) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }
			    @Received let aBuilder: Instantiator<A>
			}
			""",
		]
		let (_, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["builderLoop"]])
	}

	/// A member promoted for an optional receive stays refused: the walk binds it non-optional, which its rebinding would annotate optional.
	@Test
	mutating func mock_refusesLoop_whenMemberIsPromotedForOptionalReceive() async throws {
		let fixture = [
			"""
			@Instantiable(generateMock: true)
			public struct Screen: Instantiable {
			    public init(aBuilder: Instantiator<A>?) { self.aBuilder = aBuilder }
			    @Received let aBuilder: Instantiator<A>?
			}
			""",
			"""
			@Instantiable
			public struct A: Instantiable {
			    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
			    @Instantiated let bBuilder: Instantiator<B>
			}
			""",
			"""
			@Instantiable
			public struct B: Instantiable {
			    public init(aBuilder: Instantiator<A>?) { self.aBuilder = aBuilder }
			    @Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?
			}
			""",
		]
		let (_, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["builderLoop"]])
	}

	/// A member erased to another type stays refused: its rebinding would hand the erased wrapper its concrete type's function unerased.
	@Test
	mutating func mock_refusesLoop_whenMemberIsErasedToAnotherType() async throws {
		let fixture = [
			"""
			public final class AnyNode {
			    public init(_ node: Node) { self.node = node }
			    let node: Node
			}
			public struct AnyNodeFactory {
			    public init(_ builder: ErasedInstantiator<(), AnyNode>) { self.builder = builder }
			    let builder: ErasedInstantiator<(), AnyNode>
			}
			@Instantiable
			public final class Holder: Instantiable {
			    public init(nodeBuilder: ErasedInstantiator<(), AnyNode>) { self.nodeBuilder = nodeBuilder }
			    @Instantiated(fulfilledByType: "Node", erasedToConcreteExistential: true) let nodeBuilder: ErasedInstantiator<(), AnyNode>
			}
			""",
			"""
			@Instantiable(generateMock: true)
			public final class Node: Instantiable {
			    public init(childBuilder: AnyNodeFactory) { self.childBuilder = childBuilder }
			    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: ErasedInstantiator<(), AnyNode>.self, erasedToConcreteExistential: true) let childBuilder: AnyNodeFactory
			}
			""",
		]
		let (_, reports) = try await Self.layingOutMockRoots(filesToDelete: &filesToDelete) { filesToDelete in
			try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
		#expect(reports.filter(\.isMockRoot).map(\.everyRefusal) == [["builderLoop"]])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The fixtures of the value cells: a loop at a level below the root, and one at the root with a configured member.
	private static let valueFixtures: [String: [String: String]] = [
		"level": [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public struct Root: Instantiable {
			    public init(holder: Holder) {
			        self.holder = holder
			    }

			    @Instantiated public let holder: Holder
			}
			""",
			"Types.swift": """
			public protocol Marked {
			    var marker: String { get set }
			}

			func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
			    var value = value
			    value.marker = marker
			    return value
			}

			@Instantiable
			public struct Holder: Instantiable, Marked {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) {
			        self.aBuilder = aBuilder
			        self.bBuilder = bBuilder
			        self.cBuilder = cBuilder
			    }

			    @Instantiated public let aBuilder: Instantiator<A>
			    @Instantiated public let bBuilder: Instantiator<B>
			    @Instantiated public let cBuilder: Instantiator<C>

			    public var marker = "built"
			}

			@Instantiable
			public struct A: Instantiable, Marked {
			    public init(bBuilder: Instantiator<B>, leaf: Leaf) {
			        self.bBuilder = bBuilder
			        self.leaf = leaf
			    }

			    @Received public let bBuilder: Instantiator<B>
			    @Instantiated public let leaf: Leaf

			    public var marker = "built"
			}

			@Instantiable
			public struct B: Instantiable, Marked {
			    public init(aBuilder: Instantiator<A>, cBuilder: Instantiator<C>) {
			        self.aBuilder = aBuilder
			        self.cBuilder = cBuilder
			    }

			    @Received public let aBuilder: Instantiator<A>
			    @Received public let cBuilder: Instantiator<C>

			    public var marker = "built"
			}

			@Instantiable
			public struct C: Instantiable, Marked {
			    public init(aBuilder: Instantiator<A>) {
			        self.aBuilder = aBuilder
			    }

			    @Received public let aBuilder: Instantiator<A>

			    public var marker = "built"
			}

			@Instantiable
			public struct Leaf: Instantiable, Marked {
			    public init() {}

			    public var marker = "built"
			}
			""",
		],
		"root": [
			"Root.swift": """
			@Instantiable(generateMock: true)
			public struct Root: Instantiable {
			    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
			        self.aBuilder = aBuilder
			        self.bBuilder = bBuilder
			    }

			    @Instantiated public let aBuilder: Instantiator<A>
			    @Instantiated public let bBuilder: Instantiator<B>
			}
			""",
			"Types.swift": """
			public protocol Marked {
			    var marker: String { get set }
			}

			func marked<Value: Marked>(_ value: Value, _ marker: String) -> Value {
			    var value = value
			    value.marker = marker
			    return value
			}

			@Instantiable
			public struct A: Instantiable, Marked {
			    public init(bBuilder: Instantiator<B>, leaf: Leaf) {
			        self.bBuilder = bBuilder
			        self.leaf = leaf
			    }

			    @Received public let bBuilder: Instantiator<B>
			    @Instantiated public let leaf: Leaf

			    public var marker = "built"
			}

			@Instantiable
			public struct B: Instantiable, Marked {
			    public init(aBuilder: Instantiator<A>) {
			        self.aBuilder = aBuilder
			    }

			    @Received public let aBuilder: Instantiator<A>

			    public var marker = "built"
			}

			@Instantiable
			public struct Leaf: Instantiable, Marked {
			    public init() {}

			    public var marker = "built"
			}
			""",
		],
	]

	/// What each value cell evaluates, and the markers its overrides set.
	private static let valueProbes: [String: (probes: [DifferentialValueProbe], markers: [String])] = [
		"level": (
			[
				DifferentialValueProbe("Root.mock().holder.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "leaf overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") })))).holder.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "aBuilder overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init({ marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") })))).holder.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "bBuilder overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(holder: .init(bBuilder: { marked(B(aBuilder: $0, cBuilder: $1), \"bBuilder\") }))).holder.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "cBuilder overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(holder: .init(cBuilder: { marked(C(aBuilder: $0), \"cBuilder\") }))).holder.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "all overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") }, { marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") }), bBuilder: { marked(B(aBuilder: $0, cBuilder: $1), \"bBuilder\") }, cBuilder: { marked(C(aBuilder: $0), \"cBuilder\") }))).holder.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().holder.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "leaf overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") })))).holder.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "aBuilder overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init({ marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") })))).holder.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "bBuilder overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(holder: .init(bBuilder: { marked(B(aBuilder: $0, cBuilder: $1), \"bBuilder\") }))).holder.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "cBuilder overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(holder: .init(cBuilder: { marked(C(aBuilder: $0), \"cBuilder\") }))).holder.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe(name: "all overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") }, { marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") }), bBuilder: { marked(B(aBuilder: $0, cBuilder: $1), \"bBuilder\") }, cBuilder: { marked(C(aBuilder: $0), \"cBuilder\") }))).holder.aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().cBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().holder.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "leaf overridden, lap 3", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") })))).holder.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "aBuilder overridden, lap 3", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init({ marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") })))).holder.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "bBuilder overridden, lap 3", expression: "Root.mock(safeDIOverrides: .init(holder: .init(bBuilder: { marked(B(aBuilder: $0, cBuilder: $1), \"bBuilder\") }))).holder.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "cBuilder overridden, lap 3", expression: "Root.mock(safeDIOverrides: .init(holder: .init(cBuilder: { marked(C(aBuilder: $0), \"cBuilder\") }))).holder.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "all overridden, lap 3", expression: "Root.mock(safeDIOverrides: .init(holder: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") }, { marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") }), bBuilder: { marked(B(aBuilder: $0, cBuilder: $1), \"bBuilder\") }, cBuilder: { marked(C(aBuilder: $0), \"cBuilder\") }))).holder.bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
			],
			["leaf", "aBuilder", "bBuilder", "cBuilder"],
		),
		"root": (
			[
				DifferentialValueProbe("Root.mock().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "leaf overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "aBuilder overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init({ marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") }))).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "bBuilder overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(bBuilder: { marked(B(aBuilder: $0), \"bBuilder\") })).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe(name: "all overridden, lap 1", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") }, { marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") }), bBuilder: { marked(B(aBuilder: $0), \"bBuilder\") })).aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()"),
				DifferentialValueProbe("Root.mock().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "leaf overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") }))).bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "aBuilder overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init({ marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") }))).bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "bBuilder overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(bBuilder: { marked(B(aBuilder: $0), \"bBuilder\") })).bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
				DifferentialValueProbe(name: "all overridden, lap 2", expression: "Root.mock(safeDIOverrides: .init(aBuilder: .init(leaf: { marked(Leaf(), \"leaf\") }, { marked(A(bBuilder: $0, leaf: $1), \"aBuilder\") }), bBuilder: { marked(B(aBuilder: $0), \"bBuilder\") })).bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().leaf"),
			],
			["leaf", "aBuilder", "bBuilder"],
		),
	]

	/// What `body` returns with every internal mock root node records accept laid out from them, and the report of each
	/// root of the run.
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
		return (output, reports)
	}
}
