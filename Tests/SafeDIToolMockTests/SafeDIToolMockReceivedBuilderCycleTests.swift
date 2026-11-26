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

/// A mock builds a loop of instantiators that receive one another as production does: each builder function on the loop
/// starts by wrapping again the functions of the members its tree receives inside the loop, and reads its own override,
/// so a type built through a wrapper made again is built by the same override. A mock that promotes a received
/// instantiator whose tree receives another instantiator back builds both as a loop at the mock root.
struct SafeDIToolMockReceivedBuilderCycleTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – A root's mock

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsEachOtherBuilderInsideEachFunction_whenRootsBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                bBuilder: bBuilder
			            )
			        }

			        var aBuilder: ((Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }
			        var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: ((Instantiator<B>) -> A)?,
			                bBuilder: ((Instantiator<A>) -> B)?
			            ) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			            }

			            let aBuilder: ((Instantiator<B>) -> A)?
			            let bBuilder: ((Instantiator<A>) -> B)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder(__safeDI_A_configuration: ((Instantiator<B>) -> A)?) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder(__safeDI_B_configuration: ((Instantiator<A>) -> B)?) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        return Root(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_emitsEachLoopAsItsOwnUnit_whenRootBuildsTwoLoopsOfBuildersOneAfterTheOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let dBuilder: Instantiator<D>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
			Self.type("C", "@Received let dBuilder: Instantiator<D>"),
			Self.type("D", "@Received let cBuilder: Instantiator<C>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>) -> B)? = nil,
			            cBuilder: ((Instantiator<D>) -> C)? = nil,
			            dBuilder: ((Instantiator<C>) -> D)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                bBuilder: bBuilder,
			                cBuilder: cBuilder,
			                dBuilder: dBuilder
			            )
			        }

			        var aBuilder: ((Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }
			        var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }
			        var cBuilder: ((Instantiator<D>) -> C)? { __safeDI_storage.cBuilder }
			        var dBuilder: ((Instantiator<C>) -> D)? { __safeDI_storage.dBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: ((Instantiator<B>) -> A)?,
			                bBuilder: ((Instantiator<A>) -> B)?,
			                cBuilder: ((Instantiator<D>) -> C)?,
			                dBuilder: ((Instantiator<C>) -> D)?
			            ) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			                self.cBuilder = cBuilder
			                self.dBuilder = dBuilder
			            }

			            let aBuilder: ((Instantiator<B>) -> A)?
			            let bBuilder: ((Instantiator<A>) -> B)?
			            let cBuilder: ((Instantiator<D>) -> C)?
			            let dBuilder: ((Instantiator<C>) -> D)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder(__safeDI_A_configuration: ((Instantiator<B>) -> A)?) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder(__safeDI_B_configuration: ((Instantiator<A>) -> B)?) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        func __safeDI_cBuilder(__safeDI_C_configuration: ((Instantiator<D>) -> C)?) -> C {
			            let dBuilder = Instantiator<D> {
			                __safeDI_dBuilder(__safeDI_D_configuration: safeDIOverrides.dBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_C_configuration { safeDIBuilder(dBuilder) } else { C(dBuilder: dBuilder) }
			        }
			        func __safeDI_dBuilder(__safeDI_D_configuration: ((Instantiator<C>) -> D)?) -> D {
			            let cBuilder = Instantiator<C> {
			                __safeDI_cBuilder(__safeDI_C_configuration: safeDIOverrides.cBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_D_configuration { safeDIBuilder(cBuilder) } else { D(cBuilder: cBuilder) }
			        }
			        let cBuilder = Instantiator<C> {
			            __safeDI_cBuilder(__safeDI_C_configuration: safeDIOverrides.cBuilder)
			        }
			        let dBuilder = Instantiator<D> {
			            __safeDI_dBuilder(__safeDI_D_configuration: safeDIOverrides.dBuilder)
			        }
			        return Root(aBuilder: aBuilder, bBuilder: bBuilder, cBuilder: cBuilder, dBuilder: dBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_growsByTheSameLinesForEachScreen_whenRootsErasedScreenBuildersOpenOneAnother() async throws {
		// Each screen's builder function wraps again only the three builders its screen receives, so the root's mock holds a
		// fixed number of lines for each screen, as production does.
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.screensOpeningOneAnother(screenCount: 24), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            s0Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s1Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s2Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s3Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s4Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s5Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s6Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s7Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s8Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s9Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s10Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s11Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s12Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s13Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s14Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s15Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s16Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s17Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s18Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s19Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s20Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s21Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s22Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil,
			            s23Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                s0Builder: s0Builder,
			                s1Builder: s1Builder,
			                s2Builder: s2Builder,
			                s3Builder: s3Builder,
			                s4Builder: s4Builder,
			                s5Builder: s5Builder,
			                s6Builder: s6Builder,
			                s7Builder: s7Builder,
			                s8Builder: s8Builder,
			                s9Builder: s9Builder,
			                s10Builder: s10Builder,
			                s11Builder: s11Builder,
			                s12Builder: s12Builder,
			                s13Builder: s13Builder,
			                s14Builder: s14Builder,
			                s15Builder: s15Builder,
			                s16Builder: s16Builder,
			                s17Builder: s17Builder,
			                s18Builder: s18Builder,
			                s19Builder: s19Builder,
			                s20Builder: s20Builder,
			                s21Builder: s21Builder,
			                s22Builder: s22Builder,
			                s23Builder: s23Builder
			            )
			        }

			        var s0Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s0Builder }
			        var s1Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s1Builder }
			        var s2Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s2Builder }
			        var s3Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s3Builder }
			        var s4Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s4Builder }
			        var s5Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s5Builder }
			        var s6Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s6Builder }
			        var s7Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s7Builder }
			        var s8Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s8Builder }
			        var s9Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s9Builder }
			        var s10Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s10Builder }
			        var s11Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s11Builder }
			        var s12Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s12Builder }
			        var s13Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s13Builder }
			        var s14Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s14Builder }
			        var s15Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s15Builder }
			        var s16Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s16Builder }
			        var s17Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s17Builder }
			        var s18Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s18Builder }
			        var s19Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s19Builder }
			        var s20Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s20Builder }
			        var s21Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s21Builder }
			        var s22Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s22Builder }
			        var s23Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)? { __safeDI_storage.s23Builder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                s0Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s1Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s2Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s3Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s4Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s5Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s6Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s7Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s8Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s9Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s10Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s11Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s12Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s13Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s14Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s15Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s16Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s17Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s18Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s19Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s20Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s21Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s22Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?,
			                s23Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            ) {
			                self.s0Builder = s0Builder
			                self.s1Builder = s1Builder
			                self.s2Builder = s2Builder
			                self.s3Builder = s3Builder
			                self.s4Builder = s4Builder
			                self.s5Builder = s5Builder
			                self.s6Builder = s6Builder
			                self.s7Builder = s7Builder
			                self.s8Builder = s8Builder
			                self.s9Builder = s9Builder
			                self.s10Builder = s10Builder
			                self.s11Builder = s11Builder
			                self.s12Builder = s12Builder
			                self.s13Builder = s13Builder
			                self.s14Builder = s14Builder
			                self.s15Builder = s15Builder
			                self.s16Builder = s16Builder
			                self.s17Builder = s17Builder
			                self.s18Builder = s18Builder
			                self.s19Builder = s19Builder
			                self.s20Builder = s20Builder
			                self.s21Builder = s21Builder
			                self.s22Builder = s22Builder
			                self.s23Builder = s23Builder
			            }

			            let s0Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s1Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s2Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s3Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s4Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s5Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s6Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s7Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s8Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s9Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s10Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s11Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s12Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s13Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s14Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s15Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s16Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s17Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s18Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s19Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s20Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s21Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s22Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			            let s23Builder: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_s0Builder(__safeDI_S0_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s1Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s1Builder(__safeDI_S1_configuration: safeDIOverrides.s1Builder)
			            }
			            let s2Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s2Builder(__safeDI_S2_configuration: safeDIOverrides.s2Builder)
			            }
			            let s5Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s5Builder(__safeDI_S5_configuration: safeDIOverrides.s5Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S0_configuration { safeDIBuilder(s1Builder, s2Builder, s5Builder) } else { S0(s1Builder: s1Builder, s2Builder: s2Builder, s5Builder: s5Builder) }
			        }
			        func __safeDI_s1Builder(__safeDI_S1_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s2Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s2Builder(__safeDI_S2_configuration: safeDIOverrides.s2Builder)
			            }
			            let s3Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s3Builder(__safeDI_S3_configuration: safeDIOverrides.s3Builder)
			            }
			            let s6Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s6Builder(__safeDI_S6_configuration: safeDIOverrides.s6Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S1_configuration { safeDIBuilder(s2Builder, s3Builder, s6Builder) } else { S1(s2Builder: s2Builder, s3Builder: s3Builder, s6Builder: s6Builder) }
			        }
			        func __safeDI_s2Builder(__safeDI_S2_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s3Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s3Builder(__safeDI_S3_configuration: safeDIOverrides.s3Builder)
			            }
			            let s4Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s4Builder(__safeDI_S4_configuration: safeDIOverrides.s4Builder)
			            }
			            let s7Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s7Builder(__safeDI_S7_configuration: safeDIOverrides.s7Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S2_configuration { safeDIBuilder(s3Builder, s4Builder, s7Builder) } else { S2(s3Builder: s3Builder, s4Builder: s4Builder, s7Builder: s7Builder) }
			        }
			        func __safeDI_s3Builder(__safeDI_S3_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s4Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s4Builder(__safeDI_S4_configuration: safeDIOverrides.s4Builder)
			            }
			            let s5Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s5Builder(__safeDI_S5_configuration: safeDIOverrides.s5Builder)
			            }
			            let s8Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s8Builder(__safeDI_S8_configuration: safeDIOverrides.s8Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S3_configuration { safeDIBuilder(s4Builder, s5Builder, s8Builder) } else { S3(s4Builder: s4Builder, s5Builder: s5Builder, s8Builder: s8Builder) }
			        }
			        func __safeDI_s4Builder(__safeDI_S4_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s5Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s5Builder(__safeDI_S5_configuration: safeDIOverrides.s5Builder)
			            }
			            let s6Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s6Builder(__safeDI_S6_configuration: safeDIOverrides.s6Builder)
			            }
			            let s9Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s9Builder(__safeDI_S9_configuration: safeDIOverrides.s9Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S4_configuration { safeDIBuilder(s5Builder, s6Builder, s9Builder) } else { S4(s5Builder: s5Builder, s6Builder: s6Builder, s9Builder: s9Builder) }
			        }
			        func __safeDI_s5Builder(__safeDI_S5_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s6Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s6Builder(__safeDI_S6_configuration: safeDIOverrides.s6Builder)
			            }
			            let s7Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s7Builder(__safeDI_S7_configuration: safeDIOverrides.s7Builder)
			            }
			            let s10Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s10Builder(__safeDI_S10_configuration: safeDIOverrides.s10Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S5_configuration { safeDIBuilder(s6Builder, s7Builder, s10Builder) } else { S5(s6Builder: s6Builder, s7Builder: s7Builder, s10Builder: s10Builder) }
			        }
			        func __safeDI_s6Builder(__safeDI_S6_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s7Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s7Builder(__safeDI_S7_configuration: safeDIOverrides.s7Builder)
			            }
			            let s8Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s8Builder(__safeDI_S8_configuration: safeDIOverrides.s8Builder)
			            }
			            let s11Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s11Builder(__safeDI_S11_configuration: safeDIOverrides.s11Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S6_configuration { safeDIBuilder(s7Builder, s8Builder, s11Builder) } else { S6(s7Builder: s7Builder, s8Builder: s8Builder, s11Builder: s11Builder) }
			        }
			        func __safeDI_s7Builder(__safeDI_S7_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s8Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s8Builder(__safeDI_S8_configuration: safeDIOverrides.s8Builder)
			            }
			            let s9Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s9Builder(__safeDI_S9_configuration: safeDIOverrides.s9Builder)
			            }
			            let s12Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s12Builder(__safeDI_S12_configuration: safeDIOverrides.s12Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S7_configuration { safeDIBuilder(s8Builder, s9Builder, s12Builder) } else { S7(s8Builder: s8Builder, s9Builder: s9Builder, s12Builder: s12Builder) }
			        }
			        func __safeDI_s8Builder(__safeDI_S8_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s9Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s9Builder(__safeDI_S9_configuration: safeDIOverrides.s9Builder)
			            }
			            let s10Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s10Builder(__safeDI_S10_configuration: safeDIOverrides.s10Builder)
			            }
			            let s13Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s13Builder(__safeDI_S13_configuration: safeDIOverrides.s13Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S8_configuration { safeDIBuilder(s9Builder, s10Builder, s13Builder) } else { S8(s9Builder: s9Builder, s10Builder: s10Builder, s13Builder: s13Builder) }
			        }
			        func __safeDI_s9Builder(__safeDI_S9_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s10Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s10Builder(__safeDI_S10_configuration: safeDIOverrides.s10Builder)
			            }
			            let s11Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s11Builder(__safeDI_S11_configuration: safeDIOverrides.s11Builder)
			            }
			            let s14Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s14Builder(__safeDI_S14_configuration: safeDIOverrides.s14Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S9_configuration { safeDIBuilder(s10Builder, s11Builder, s14Builder) } else { S9(s10Builder: s10Builder, s11Builder: s11Builder, s14Builder: s14Builder) }
			        }
			        func __safeDI_s10Builder(__safeDI_S10_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s11Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s11Builder(__safeDI_S11_configuration: safeDIOverrides.s11Builder)
			            }
			            let s12Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s12Builder(__safeDI_S12_configuration: safeDIOverrides.s12Builder)
			            }
			            let s15Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s15Builder(__safeDI_S15_configuration: safeDIOverrides.s15Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S10_configuration { safeDIBuilder(s11Builder, s12Builder, s15Builder) } else { S10(s11Builder: s11Builder, s12Builder: s12Builder, s15Builder: s15Builder) }
			        }
			        func __safeDI_s11Builder(__safeDI_S11_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s12Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s12Builder(__safeDI_S12_configuration: safeDIOverrides.s12Builder)
			            }
			            let s13Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s13Builder(__safeDI_S13_configuration: safeDIOverrides.s13Builder)
			            }
			            let s16Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s16Builder(__safeDI_S16_configuration: safeDIOverrides.s16Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S11_configuration { safeDIBuilder(s12Builder, s13Builder, s16Builder) } else { S11(s12Builder: s12Builder, s13Builder: s13Builder, s16Builder: s16Builder) }
			        }
			        func __safeDI_s12Builder(__safeDI_S12_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s13Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s13Builder(__safeDI_S13_configuration: safeDIOverrides.s13Builder)
			            }
			            let s14Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s14Builder(__safeDI_S14_configuration: safeDIOverrides.s14Builder)
			            }
			            let s17Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s17Builder(__safeDI_S17_configuration: safeDIOverrides.s17Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S12_configuration { safeDIBuilder(s13Builder, s14Builder, s17Builder) } else { S12(s13Builder: s13Builder, s14Builder: s14Builder, s17Builder: s17Builder) }
			        }
			        func __safeDI_s13Builder(__safeDI_S13_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s14Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s14Builder(__safeDI_S14_configuration: safeDIOverrides.s14Builder)
			            }
			            let s15Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s15Builder(__safeDI_S15_configuration: safeDIOverrides.s15Builder)
			            }
			            let s18Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s18Builder(__safeDI_S18_configuration: safeDIOverrides.s18Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S13_configuration { safeDIBuilder(s14Builder, s15Builder, s18Builder) } else { S13(s14Builder: s14Builder, s15Builder: s15Builder, s18Builder: s18Builder) }
			        }
			        func __safeDI_s14Builder(__safeDI_S14_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s15Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s15Builder(__safeDI_S15_configuration: safeDIOverrides.s15Builder)
			            }
			            let s16Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s16Builder(__safeDI_S16_configuration: safeDIOverrides.s16Builder)
			            }
			            let s19Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s19Builder(__safeDI_S19_configuration: safeDIOverrides.s19Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S14_configuration { safeDIBuilder(s15Builder, s16Builder, s19Builder) } else { S14(s15Builder: s15Builder, s16Builder: s16Builder, s19Builder: s19Builder) }
			        }
			        func __safeDI_s15Builder(__safeDI_S15_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s16Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s16Builder(__safeDI_S16_configuration: safeDIOverrides.s16Builder)
			            }
			            let s17Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s17Builder(__safeDI_S17_configuration: safeDIOverrides.s17Builder)
			            }
			            let s20Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s20Builder(__safeDI_S20_configuration: safeDIOverrides.s20Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S15_configuration { safeDIBuilder(s16Builder, s17Builder, s20Builder) } else { S15(s16Builder: s16Builder, s17Builder: s17Builder, s20Builder: s20Builder) }
			        }
			        func __safeDI_s16Builder(__safeDI_S16_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s17Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s17Builder(__safeDI_S17_configuration: safeDIOverrides.s17Builder)
			            }
			            let s18Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s18Builder(__safeDI_S18_configuration: safeDIOverrides.s18Builder)
			            }
			            let s21Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s21Builder(__safeDI_S21_configuration: safeDIOverrides.s21Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S16_configuration { safeDIBuilder(s17Builder, s18Builder, s21Builder) } else { S16(s17Builder: s17Builder, s18Builder: s18Builder, s21Builder: s21Builder) }
			        }
			        func __safeDI_s17Builder(__safeDI_S17_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s18Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s18Builder(__safeDI_S18_configuration: safeDIOverrides.s18Builder)
			            }
			            let s19Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s19Builder(__safeDI_S19_configuration: safeDIOverrides.s19Builder)
			            }
			            let s22Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s22Builder(__safeDI_S22_configuration: safeDIOverrides.s22Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S17_configuration { safeDIBuilder(s18Builder, s19Builder, s22Builder) } else { S17(s18Builder: s18Builder, s19Builder: s19Builder, s22Builder: s22Builder) }
			        }
			        func __safeDI_s18Builder(__safeDI_S18_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s19Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s19Builder(__safeDI_S19_configuration: safeDIOverrides.s19Builder)
			            }
			            let s20Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s20Builder(__safeDI_S20_configuration: safeDIOverrides.s20Builder)
			            }
			            let s23Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s23Builder(__safeDI_S23_configuration: safeDIOverrides.s23Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S18_configuration { safeDIBuilder(s19Builder, s20Builder, s23Builder) } else { S18(s19Builder: s19Builder, s20Builder: s20Builder, s23Builder: s23Builder) }
			        }
			        func __safeDI_s19Builder(__safeDI_S19_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s20Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s20Builder(__safeDI_S20_configuration: safeDIOverrides.s20Builder)
			            }
			            let s21Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s21Builder(__safeDI_S21_configuration: safeDIOverrides.s21Builder)
			            }
			            let s0Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s0Builder(__safeDI_S0_configuration: safeDIOverrides.s0Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S19_configuration { safeDIBuilder(s20Builder, s21Builder, s0Builder) } else { S19(s20Builder: s20Builder, s21Builder: s21Builder, s0Builder: s0Builder) }
			        }
			        func __safeDI_s20Builder(__safeDI_S20_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s21Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s21Builder(__safeDI_S21_configuration: safeDIOverrides.s21Builder)
			            }
			            let s22Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s22Builder(__safeDI_S22_configuration: safeDIOverrides.s22Builder)
			            }
			            let s1Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s1Builder(__safeDI_S1_configuration: safeDIOverrides.s1Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S20_configuration { safeDIBuilder(s21Builder, s22Builder, s1Builder) } else { S20(s21Builder: s21Builder, s22Builder: s22Builder, s1Builder: s1Builder) }
			        }
			        func __safeDI_s21Builder(__safeDI_S21_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s22Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s22Builder(__safeDI_S22_configuration: safeDIOverrides.s22Builder)
			            }
			            let s23Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s23Builder(__safeDI_S23_configuration: safeDIOverrides.s23Builder)
			            }
			            let s2Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s2Builder(__safeDI_S2_configuration: safeDIOverrides.s2Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S21_configuration { safeDIBuilder(s22Builder, s23Builder, s2Builder) } else { S21(s22Builder: s22Builder, s23Builder: s23Builder, s2Builder: s2Builder) }
			        }
			        func __safeDI_s22Builder(__safeDI_S22_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s23Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s23Builder(__safeDI_S23_configuration: safeDIOverrides.s23Builder)
			            }
			            let s0Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s0Builder(__safeDI_S0_configuration: safeDIOverrides.s0Builder)
			            }
			            let s3Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s3Builder(__safeDI_S3_configuration: safeDIOverrides.s3Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S22_configuration { safeDIBuilder(s23Builder, s0Builder, s3Builder) } else { S22(s23Builder: s23Builder, s0Builder: s0Builder, s3Builder: s3Builder) }
			        }
			        func __safeDI_s23Builder(__safeDI_S23_configuration: ((ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>, ErasedInstantiator<(), any Screen>) -> any Screen)?) -> any Screen {
			            let s0Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s0Builder(__safeDI_S0_configuration: safeDIOverrides.s0Builder)
			            }
			            let s1Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s1Builder(__safeDI_S1_configuration: safeDIOverrides.s1Builder)
			            }
			            let s4Builder = ErasedInstantiator<(), any Screen> {
			                __safeDI_s4Builder(__safeDI_S4_configuration: safeDIOverrides.s4Builder)
			            }
			            return if let safeDIBuilder = __safeDI_S23_configuration { safeDIBuilder(s0Builder, s1Builder, s4Builder) } else { S23(s0Builder: s0Builder, s1Builder: s1Builder, s4Builder: s4Builder) }
			        }
			        let s0Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s0Builder(__safeDI_S0_configuration: safeDIOverrides.s0Builder)
			        }
			        let s1Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s1Builder(__safeDI_S1_configuration: safeDIOverrides.s1Builder)
			        }
			        let s2Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s2Builder(__safeDI_S2_configuration: safeDIOverrides.s2Builder)
			        }
			        let s3Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s3Builder(__safeDI_S3_configuration: safeDIOverrides.s3Builder)
			        }
			        let s4Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s4Builder(__safeDI_S4_configuration: safeDIOverrides.s4Builder)
			        }
			        let s5Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s5Builder(__safeDI_S5_configuration: safeDIOverrides.s5Builder)
			        }
			        let s6Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s6Builder(__safeDI_S6_configuration: safeDIOverrides.s6Builder)
			        }
			        let s7Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s7Builder(__safeDI_S7_configuration: safeDIOverrides.s7Builder)
			        }
			        let s8Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s8Builder(__safeDI_S8_configuration: safeDIOverrides.s8Builder)
			        }
			        let s9Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s9Builder(__safeDI_S9_configuration: safeDIOverrides.s9Builder)
			        }
			        let s10Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s10Builder(__safeDI_S10_configuration: safeDIOverrides.s10Builder)
			        }
			        let s11Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s11Builder(__safeDI_S11_configuration: safeDIOverrides.s11Builder)
			        }
			        let s12Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s12Builder(__safeDI_S12_configuration: safeDIOverrides.s12Builder)
			        }
			        let s13Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s13Builder(__safeDI_S13_configuration: safeDIOverrides.s13Builder)
			        }
			        let s14Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s14Builder(__safeDI_S14_configuration: safeDIOverrides.s14Builder)
			        }
			        let s15Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s15Builder(__safeDI_S15_configuration: safeDIOverrides.s15Builder)
			        }
			        let s16Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s16Builder(__safeDI_S16_configuration: safeDIOverrides.s16Builder)
			        }
			        let s17Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s17Builder(__safeDI_S17_configuration: safeDIOverrides.s17Builder)
			        }
			        let s18Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s18Builder(__safeDI_S18_configuration: safeDIOverrides.s18Builder)
			        }
			        let s19Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s19Builder(__safeDI_S19_configuration: safeDIOverrides.s19Builder)
			        }
			        let s20Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s20Builder(__safeDI_S20_configuration: safeDIOverrides.s20Builder)
			        }
			        let s21Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s21Builder(__safeDI_S21_configuration: safeDIOverrides.s21Builder)
			        }
			        let s22Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s22Builder(__safeDI_S22_configuration: safeDIOverrides.s22Builder)
			        }
			        let s23Builder = ErasedInstantiator<(), any Screen> {
			            __safeDI_s23Builder(__safeDI_S23_configuration: safeDIOverrides.s23Builder)
			        }
			        return Root(s0Builder: s0Builder, s1Builder: s1Builder, s2Builder: s2Builder, s3Builder: s3Builder, s4Builder: s4Builder, s5Builder: s5Builder, s6Builder: s6Builder, s7Builder: s7Builder, s8Builder: s8Builder, s9Builder: s9Builder, s10Builder: s10Builder, s11Builder: s11Builder, s12Builder: s12Builder, s13Builder: s13Builder, s14Builder: s14Builder, s15Builder: s15Builder, s16Builder: s16Builder, s17Builder: s17Builder, s18Builder: s18Builder, s19Builder: s19Builder, s20Builder: s20Builder, s21Builder: s21Builder, s22Builder: s22Builder, s23Builder: s23Builder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWhatProductionBuilds_whenLoopMemberFunctionTakesCycleParameter() async throws {
		let fixture = Self.loopMemberTakingCycleParameterFixture
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWithOverride_whenTypeIsBuiltThroughWrapperMadeAgainInsideLoop() async throws {
		// Each `B` the probe builds is built through the wrapper of `bBuilder` that `__safeDI_aBuilder` makes again, so the
		// override counts two builds.
		let fixture = [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		let fixtureFiles = Self.fixtureFiles(fixture)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: output.dependencyTreeFiles),
			probes: [DifferentialValueProbe(
				name: "builds through the override",
				expression: """
				{ () -> Int in
				    var builds = 0
				    let root = Root.mock(safeDIOverrides: .init(bBuilder: { aBuilder in
				        builds += 1
				        return B(aBuilder: aBuilder)
				    }))
				    _ = root.aBuilder.instantiate().bBuilder.instantiate().aBuilder.instantiate().bBuilder.instantiate()
				    return builds
				}()
				""",
				knownRightExpression: "2",
			)],
			filesToDelete: &filesToDelete,
		)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilderInsideItsOwnFunction_whenItsTypeRenamesItBesideAnOnlyIfAvailableReceiveOfABuilderWaitingOnItThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.builderRenamedByItsTypeBesideBuilderWaitingOnItThroughValueFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)? = nil,
			            t3: T3.SafeDIMockConfiguration = .init(),
			            t2Builder: ((T3?) -> T2)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                t4Builder: t4Builder,
			                t3: t3,
			                t2Builder: t2Builder
			            )
			        }

			        var t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)? { __safeDI_storage.t4Builder }
			        var t3: T3.SafeDIMockConfiguration { __safeDI_storage.t3 }
			        var t2Builder: ((T3?) -> T2)? { __safeDI_storage.t2Builder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?,
			                t3: T3.SafeDIMockConfiguration,
			                t2Builder: ((T3?) -> T2)?
			            ) {
			                self.t4Builder = t4Builder
			                self.t3 = t3
			                self.t2Builder = t2Builder
			            }

			            let t4Builder: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?
			            let t3: T3.SafeDIMockConfiguration
			            let t2Builder: ((T3?) -> T2)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_t4Builder(__safeDI_T4_configuration: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?) -> T4 {
			            let t4Builder = Instantiator<T4> {
			                __safeDI_t4Builder(__safeDI_T4_configuration: safeDIOverrides.t4Builder)
			            }
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: Instantiator<T4> = t4Builder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_T4_configuration { safeDIBuilder(t4BuilderAlias, nil) } else { T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil) }
			        }
			        let t4Builder = Instantiator<T4> {
			            __safeDI_t4Builder(__safeDI_T4_configuration: safeDIOverrides.t4Builder)
			        }
			        func __safeDI_t4(__safeDI_T4_configuration: ((Instantiator<T4>, Instantiator<T2>?) -> T4)?) -> T4 {
			            #sourceLocation(file: "\(output.fixtures["T4.swift"])", line: 8)
			            let t4BuilderAlias: Instantiator<T4> = t4Builder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_T4_configuration { safeDIBuilder(t4BuilderAlias, nil) } else { T4(t4BuilderAlias: t4BuilderAlias, t2Builder: nil) }
			        }
			        func __safeDI_t3(__safeDI_T3_configuration: T3.SafeDIMockConfiguration) -> T3 {
			            let t4: T4 = __safeDI_t4(__safeDI_T4_configuration: __safeDI_T3_configuration.t4)
			            return if let safeDIBuilder = __safeDI_T3_configuration.safeDIBuilder { safeDIBuilder(t4) } else { T3(t4: t4) }
			        }
			        let t3: T3 = __safeDI_t3(__safeDI_T3_configuration: safeDIOverrides.t3)
			        func __safeDI_t2Builder(__safeDI_T2_configuration: ((T3?) -> T2)?) -> T2 {
			            if let safeDIBuilder = __safeDI_T2_configuration { safeDIBuilder(t3) } else { T2(t3: t3) }
			        }
			        let t2Builder = Instantiator<T2> {
			            __safeDI_t2Builder(__safeDI_T2_configuration: safeDIOverrides.t2Builder)
			        }
			        return Root(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWhatProductionBuilds_whenBuildersTypeRenamesItBesideAnOnlyIfAvailableReceiveOfABuilderWaitingOnItThroughAValue() async throws {
		let fixture = Self.builderRenamedByItsTypeBesideBuilderWaitingOnItThroughValueFixture
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWhatProductionBuilds_whenOneMemberOfTwoBuilderLoopReceivesOnlyIfAvailableABuilderWaitingOnTheLoopThroughAValue() async throws {
		let fixture = Self.twoBuilderLoopBesideReceiveWaitingOnItThroughValueFixture
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesBuilderToTypeItBuilds_whenThatTypeReceivesItOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: Self.typeReceivingItsBuilderOnlyIfAvailableBesideReceiveLeftNilThroughValueFixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)? = nil,
			            t3: ((Instantiator<T4>) -> T3)? = nil,
			            t2Builder: ((T3?) -> T2)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                t4Builder: t4Builder,
			                t3: t3,
			                t2Builder: t2Builder
			            )
			        }

			        var t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)? { __safeDI_storage.t4Builder }
			        var t3: ((Instantiator<T4>) -> T3)? { __safeDI_storage.t3 }
			        var t2Builder: ((T3?) -> T2)? { __safeDI_storage.t2Builder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)?,
			                t3: ((Instantiator<T4>) -> T3)?,
			                t2Builder: ((T3?) -> T2)?
			            ) {
			                self.t4Builder = t4Builder
			                self.t3 = t3
			                self.t2Builder = t2Builder
			            }

			            let t4Builder: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)?
			            let t3: ((Instantiator<T4>) -> T3)?
			            let t2Builder: ((T3?) -> T2)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_t4Builder(__safeDI_T4_configuration: ((Instantiator<T4>?, Instantiator<T2>?) -> T4)?) -> T4 {
			            let t4Builder = Instantiator<T4> {
			                __safeDI_t4Builder(__safeDI_T4_configuration: safeDIOverrides.t4Builder)
			            }
			            return if let safeDIBuilder = __safeDI_T4_configuration { safeDIBuilder(t4Builder, nil) } else { T4(t4Builder: t4Builder, t2Builder: nil) }
			        }
			        let t4Builder = Instantiator<T4> {
			            __safeDI_t4Builder(__safeDI_T4_configuration: safeDIOverrides.t4Builder)
			        }
			        let t3 = if let safeDIBuilder = safeDIOverrides.t3 { safeDIBuilder(t4Builder) } else { T3(t4Builder: t4Builder) }
			        func __safeDI_t2Builder(__safeDI_T2_configuration: ((T3?) -> T2)?) -> T2 {
			            if let safeDIBuilder = __safeDI_T2_configuration { safeDIBuilder(t3) } else { T2(t3: t3) }
			        }
			        let t2Builder = Instantiator<T2> {
			            __safeDI_t2Builder(__safeDI_T2_configuration: safeDIOverrides.t2Builder)
			        }
			        return Root(t2Builder: t2Builder, t4Builder: t4Builder, t3: t3)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsWhatProductionBuilds_whenTypeReceivesItsBuilderOnlyIfAvailableBesideAReceiveLeftNilThroughAValue() async throws {
		let fixture = Self.typeReceivingItsBuilderOnlyIfAvailableBesideReceiveLeftNilThroughValueFixture
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	// MARK: Tests – Promotion

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_promotesBothBuildersAsLoopAndBindsOnlyTheOneItsTypeReceives_whenPromotedBuildersTreeRequiresMockedTypesBuilder() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<A>) -> B)? = nil,
			            aBuilder: ((Instantiator<B>) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                aBuilder: aBuilder
			            )
			        }

			        var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }
			        var aBuilder: ((Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: ((Instantiator<A>) -> B)?,
			                aBuilder: ((Instantiator<B>) -> A)?
			            ) {
			                self.bBuilder = bBuilder
			                self.aBuilder = aBuilder
			            }

			            let bBuilder: ((Instantiator<A>) -> B)?
			            let aBuilder: ((Instantiator<B>) -> A)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsEveryPromotedMember_whenMockedTypeAlsoReceivesBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: true)", "@Received let aBuilder: Instantiator<A>", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<A>, Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                bBuilder: bBuilder
			            )
			        }

			        var aBuilder: ((Instantiator<A>, Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }
			        var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: ((Instantiator<A>, Instantiator<B>) -> A)?,
			                bBuilder: ((Instantiator<A>) -> B)?
			            ) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			            }

			            let aBuilder: ((Instantiator<A>, Instantiator<B>) -> A)?
			            let bBuilder: ((Instantiator<A>) -> B)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_aBuilder(__safeDI_A_configuration: ((Instantiator<A>, Instantiator<B>) -> A)?) -> A {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(aBuilder, bBuilder) } else { A(aBuilder: aBuilder, bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder(__safeDI_B_configuration: ((Instantiator<A>) -> B)?) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        return A(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilderInsideItsOwnFunction_whenMockedTypeReceivesBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Received let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screenBuilder: ((Instantiator<Screen>) -> Screen)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screenBuilder: screenBuilder
			            )
			        }

			        var screenBuilder: ((Instantiator<Screen>) -> Screen)? { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                screenBuilder: ((Instantiator<Screen>) -> Screen)?
			            ) {
			                self.screenBuilder = screenBuilder
			            }

			            let screenBuilder: ((Instantiator<Screen>) -> Screen)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_screenBuilder(__safeDI_Screen_configuration: ((Instantiator<Screen>) -> Screen)?) -> Screen {
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(__safeDI_Screen_configuration: safeDIOverrides.screenBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_Screen_configuration { safeDIBuilder(screenBuilder) } else { Screen(screenBuilder: screenBuilder) }
			        }
			        let screenBuilder = Instantiator<Screen> {
			            __safeDI_screenBuilder(__safeDI_Screen_configuration: safeDIOverrides.screenBuilder)
			        }
			        return Screen(screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsUnderSiblingDisambiguatedName_whenPromotedMemberSharesItsLabelWithMockedTypesProperty() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Instantiated let x: X", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let x: Instantiator<X>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            x_Instantiator__X: ((Instantiator<B>) -> X)? = nil,
			            x_X: ((Instantiator<B>) -> X)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                x_Instantiator__X: x_Instantiator__X,
			                x_X: x_X
			            )
			        }

			        var bBuilder: ((Instantiator<X>) -> B)? { __safeDI_storage.bBuilder }
			        var x_Instantiator__X: ((Instantiator<B>) -> X)? { __safeDI_storage.x_Instantiator__X }
			        var x_X: ((Instantiator<B>) -> X)? { __safeDI_storage.x_X }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: ((Instantiator<X>) -> B)?,
			                x_Instantiator__X: ((Instantiator<B>) -> X)?,
			                x_X: ((Instantiator<B>) -> X)?
			            ) {
			                self.bBuilder = bBuilder
			                self.x_Instantiator__X = x_Instantiator__X
			                self.x_X = x_X
			            }

			            let bBuilder: ((Instantiator<X>) -> B)?
			            let x_Instantiator__X: ((Instantiator<B>) -> X)?
			            let x_X: ((Instantiator<B>) -> X)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_bBuilder() -> B {
			            let x_Instantiator__X = Instantiator<X>(__safeDI_x_Instantiator__X)
			            let x: Instantiator<X> = x_Instantiator__X
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(x) } else { B(x: x) }
			        }
			        func __safeDI_x_Instantiator__X() -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.x_Instantiator__X { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        let x_X = if let safeDIBuilder = safeDIOverrides.x_X { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        return Screen(x: x_X, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedSendableTwins_whenPromotedSendableBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: true)", "@Received let bBuilder: SendableInstantiator<B>", conformances: ", Sendable"),
			Self.type("B", "@Received let aBuilder: SendableInstantiator<A>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: (@Sendable (SendableInstantiator<A>) -> B)? = nil,
			            aBuilder: (@Sendable (SendableInstantiator<B>) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                aBuilder: aBuilder
			            )
			        }

			        var bBuilder: (@Sendable (SendableInstantiator<A>) -> B)? { __safeDI_storage.bBuilder }
			        var aBuilder: (@Sendable (SendableInstantiator<B>) -> A)? { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                bBuilder: (@Sendable (SendableInstantiator<A>) -> B)?,
			                aBuilder: (@Sendable (SendableInstantiator<B>) -> A)?
			            ) {
			                self.bBuilder = bBuilder
			                self.aBuilder = aBuilder
			            }

			            let bBuilder: (@Sendable (SendableInstantiator<A>) -> B)?
			            let aBuilder: (@Sendable (SendableInstantiator<B>) -> A)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let __safeDI_bBuilder__safeDIBuilder = safeDIOverrides.bBuilder
			        let __safeDI_aBuilder__safeDIBuilder = safeDIOverrides.aBuilder
			        @Sendable nonisolated func __safeDI_bBuilder() -> B {
			            let aBuilder = SendableInstantiator<A>(__safeDI_aBuilder)
			            return if let safeDIBuilder = __safeDI_bBuilder__safeDIBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        @Sendable nonisolated func __safeDI_aBuilder() -> A {
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = __safeDI_aBuilder__safeDIBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedRenameOfMember_whenMockedTypeRenamesBuilderWhoseTreeReceivesTheRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Received(fulfilledByDependencyNamed: \"nodeBuilder\", ofType: Instantiator<Node>.self) let middleBuilder: Instantiator<Node>"),
			Self.type("Node", "@Received(fulfilledByDependencyNamed: \"middleBuilder\", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder
			            )
			        }

			        var nodeBuilder: ((Instantiator<Node>) -> Node)? { __safeDI_storage.nodeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: ((Instantiator<Node>) -> Node)?
			            ) {
			                self.nodeBuilder = nodeBuilder
			            }

			            let nodeBuilder: ((Instantiator<Node>) -> Node)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_nodeBuilder(__safeDI_Node_configuration: ((Instantiator<Node>) -> Node)?) -> Node {
			            let middleBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			            }
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 7)
			            let childBuilder: Instantiator<Node> = middleBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Node_configuration { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			        }
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 7)
			        let middleBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Screen(middleBuilder: middleBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNoPromotedMemberOnlyItsLoopReads_whenPromotedMembersTreeReceivesBuilderMockedTypeInstantiates() async throws {
		// `X`, which `B` requires, receives `bBuilder` back, so `xBuilder` is promoted onto a loop with `A`'s own `bBuilder`,
		// and only `__safeDI_bBuilder`'s rebinding reads it.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: Instantiator<X>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let xBuilder: Instantiator<X>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            xBuilder: ((Instantiator<B>) -> X)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                xBuilder: xBuilder
			            )
			        }

			        var bBuilder: ((Instantiator<X>) -> B)? { __safeDI_storage.bBuilder }
			        var xBuilder: ((Instantiator<B>) -> X)? { __safeDI_storage.xBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: ((Instantiator<X>) -> B)?,
			                xBuilder: ((Instantiator<B>) -> X)?
			            ) {
			                self.bBuilder = bBuilder
			                self.xBuilder = xBuilder
			            }

			            let bBuilder: ((Instantiator<X>) -> B)?
			            let xBuilder: ((Instantiator<B>) -> X)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(xBuilder) } else { B(xBuilder: xBuilder) }
			        }
			        func __safeDI_xBuilder() -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.xBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNoPromotedMemberOnlyItsLoopReads_whenPromotedMembersTreeReceivesBuilderMockedTypeInstantiatesThroughRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: Instantiator<X>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received(fulfilledByDependencyNamed: \"xBuilder\", ofType: Instantiator<X>.self) let xAlias: Instantiator<X>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            xBuilder: ((Instantiator<B>) -> X)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                xBuilder: xBuilder
			            )
			        }

			        var bBuilder: ((Instantiator<X>) -> B)? { __safeDI_storage.bBuilder }
			        var xBuilder: ((Instantiator<B>) -> X)? { __safeDI_storage.xBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: ((Instantiator<X>) -> B)?,
			                xBuilder: ((Instantiator<B>) -> X)?
			            ) {
			                self.bBuilder = bBuilder
			                self.xBuilder = xBuilder
			            }

			            let bBuilder: ((Instantiator<X>) -> B)?
			            let xBuilder: ((Instantiator<B>) -> X)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let xBuilder = Instantiator<X>(__safeDI_xBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 7)
			            let xAlias: Instantiator<X> = xBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(xAlias) } else { B(xAlias: xAlias) }
			        }
			        func __safeDI_xBuilder() -> X {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = safeDIOverrides.xBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsNoPromotedMemberOnlyItsLoopReads_whenPromotedMembersTreeReceivesSendableBuilderMockedTypeInstantiates() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: SendableInstantiator<X>", "@Instantiated let bBuilder: SendableInstantiator<B>"),
			Self.type("B", "@Received let xBuilder: SendableInstantiator<X>", conformances: ", Sendable"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: SendableInstantiator<B>", conformances: ", Sendable"),
			Self.type("X", "@Received let bBuilder: SendableInstantiator<B>", conformances: ", Sendable"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: (@Sendable (SendableInstantiator<X>) -> B)? = nil,
			            xBuilder: (@Sendable (SendableInstantiator<B>) -> X)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                xBuilder: xBuilder
			            )
			        }

			        var bBuilder: (@Sendable (SendableInstantiator<X>) -> B)? { __safeDI_storage.bBuilder }
			        var xBuilder: (@Sendable (SendableInstantiator<B>) -> X)? { __safeDI_storage.xBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                bBuilder: (@Sendable (SendableInstantiator<X>) -> B)?,
			                xBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
			            ) {
			                self.bBuilder = bBuilder
			                self.xBuilder = xBuilder
			            }

			            let bBuilder: (@Sendable (SendableInstantiator<X>) -> B)?
			            let xBuilder: (@Sendable (SendableInstantiator<B>) -> X)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let __safeDI_bBuilder__safeDIBuilder = safeDIOverrides.bBuilder
			        let __safeDI_xBuilder__safeDIBuilder = safeDIOverrides.xBuilder
			        @Sendable nonisolated func __safeDI_bBuilder() -> B {
			            let xBuilder = SendableInstantiator<X>(__safeDI_xBuilder)
			            return if let safeDIBuilder = __safeDI_bBuilder__safeDIBuilder { safeDIBuilder(xBuilder) } else { B(xBuilder: xBuilder) }
			        }
			        @Sendable nonisolated func __safeDI_xBuilder() -> X {
			            let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			            return if let safeDIBuilder = __safeDI_xBuilder__safeDIBuilder { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = SendableInstantiator<B>(__safeDI_bBuilder)
			        return A(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_bindsPromotedMember_whenMockedTypesValueChildReceivesItBesideBuilderItsLoopReads() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let xBuilder: Instantiator<X>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let xBuilder: Instantiator<X>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let c: C"),
			Self.type("C", "@Received let xBuilder: Instantiator<X>"),
			Self.type("X", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: ((Instantiator<X>) -> B)? = nil,
			            xBuilder: ((Instantiator<B>) -> X)? = nil,
			            c: ((Instantiator<X>) -> C)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                xBuilder: xBuilder,
			                c: c
			            )
			        }

			        var bBuilder: ((Instantiator<X>) -> B)? { __safeDI_storage.bBuilder }
			        var xBuilder: ((Instantiator<B>) -> X)? { __safeDI_storage.xBuilder }
			        var c: ((Instantiator<X>) -> C)? { __safeDI_storage.c }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: ((Instantiator<X>) -> B)?,
			                xBuilder: ((Instantiator<B>) -> X)?,
			                c: ((Instantiator<X>) -> C)?
			            ) {
			                self.bBuilder = bBuilder
			                self.xBuilder = xBuilder
			                self.c = c
			            }

			            let bBuilder: ((Instantiator<X>) -> B)?
			            let xBuilder: ((Instantiator<B>) -> X)?
			            let c: ((Instantiator<X>) -> C)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder(__safeDI_B_configuration: ((Instantiator<X>) -> B)?) -> B {
			            let xBuilder = Instantiator<X> {
			                __safeDI_xBuilder(__safeDI_X_configuration: safeDIOverrides.xBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(xBuilder) } else { B(xBuilder: xBuilder) }
			        }
			        func __safeDI_xBuilder(__safeDI_X_configuration: ((Instantiator<B>) -> X)?) -> X {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_X_configuration { safeDIBuilder(bBuilder) } else { X(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        let xBuilder = Instantiator<X> {
			            __safeDI_xBuilder(__safeDI_X_configuration: safeDIOverrides.xBuilder)
			        }
			        let c = if let safeDIBuilder = safeDIOverrides.c { safeDIBuilder(xBuilder) } else { C(xBuilder: xBuilder) }
			        return A(bBuilder: bBuilder, c: c)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – Receives only if available

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesDefaultNilEntry_whenTypeInMockedTypesTreeReceivesItsBuilderOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let aBuilder: Instantiator<A>"),
			Self.type("A", attributes: "(generateMock: true)", "@Instantiated let b: B"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            b: ((Instantiator<A>?) -> B)? = nil,
			            aBuilder: Instantiator<A>? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                b: b
			            )
			            self.aBuilder = aBuilder
			        }

			        var b: ((Instantiator<A>?) -> B)? { __safeDI_storage.b }
			        let aBuilder: Instantiator<A>?

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                b: ((Instantiator<A>?) -> B)?
			            ) {
			                self.b = b
			            }

			            let b: ((Instantiator<A>?) -> B)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        let aBuilder: Instantiator<A>? = safeDIOverrides.aBuilder
			        let b = if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        return A(b: b)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_passesEachPromotedBuilderTheOther_whenPromotedBuildersReceiveEachOtherOnlyIfAvailable() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(generateMock: true)", "@Received let aBuilder: Instantiator<A>", "@Received let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received(onlyIfAvailable: true) let bBuilder: Instantiator<B>?"),
			Self.type("B", "@Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<B>?) -> A)? = nil,
			            bBuilder: ((Instantiator<A>?) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                bBuilder: bBuilder
			            )
			        }

			        var aBuilder: ((Instantiator<B>?) -> A)? { __safeDI_storage.aBuilder }
			        var bBuilder: ((Instantiator<A>?) -> B)? { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: ((Instantiator<B>?) -> A)?,
			                bBuilder: ((Instantiator<A>?) -> B)?
			            ) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			            }

			            let aBuilder: ((Instantiator<B>?) -> A)?
			            let bBuilder: ((Instantiator<A>?) -> B)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder(__safeDI_A_configuration: ((Instantiator<B>?) -> A)?) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder(__safeDI_B_configuration: ((Instantiator<A>?) -> B)?) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        return Root(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_throwsSendableCaptureError_whenTypeInsideSendableBuilderReceivesBuilderThatIsNotSendableOnlyIfAvailableInsideTreeItBuilds() async {
		// The root's mock reports the error production does.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Inner.swift"]):7:5: error: @Received property `t4Builder: Instantiator<T4>?` cannot be received inside a `@Sendable` function in chain: Root -> T4 -> Inner. SafeDI builds `innerBuilder: SendableInstantiator<Inner>` on `T4` in a `@Sendable` function, which cannot capture `t4Builder: Instantiator<T4>` on `Root`, because `Instantiator<T4>` is not `Sendable`. Declare `t4Builder` on `Root`, and this property, as `SendableInstantiator<T4>` to fix. `SendableInstantiator<T4>` builds `T4` in a `@Sendable` function, so what the tree of `T4` receives from outside that function must be `Sendable` too.
				\(fixtures["Root.swift"]):7:5: note: `t4Builder: Instantiator<T4>` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(swiftFileContent: [
				Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let t4Builder: Instantiator<T4>"),
				Self.type("T4", "@Instantiated let innerBuilder: SendableInstantiator<Inner>"),
				Self.type("Inner", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?"),
			], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		}
	}

	// MARK: Tests – Builders whose functions take cycle parameters

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_declaresReceivedFunction_whenLoopMemberFunctionTakesCycleParameter() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIMockConfiguration
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(session: session)
			            }
			            func __safeDI_stepBuilder() -> Step {
			                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(screenBuilder) } else { Detail(screenBuilder: screenBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			        }
			        func __safeDI_screenBuilder_received() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			        return Root(session: session, screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_wrapsLoopMemberCycleArgumentInsideReceivedFunction_whenCycleParameterIsMemberOfSameLoop() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Other", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Detail", "@Received let otherBuilder: Instantiator<Other>"),
			Self.type("Screen", "@Instantiated let detail: Detail", "@Instantiated let stepBuilder: Instantiator<Step>"),
			Self.type("Step", "@Instantiated let otherBuilder: Instantiator<Other>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let otherBuilder: Instantiator<Other>", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            otherBuilder: ((Instantiator<Screen>) -> Other)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                otherBuilder: otherBuilder,
			                screenBuilder: screenBuilder
			            )
			        }

			        var otherBuilder: ((Instantiator<Screen>) -> Other)? { __safeDI_storage.otherBuilder }
			        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                otherBuilder: ((Instantiator<Screen>) -> Other)?,
			                screenBuilder: Screen.SafeDIMockConfiguration
			            ) {
			                self.otherBuilder = otherBuilder
			                self.screenBuilder = screenBuilder
			            }

			            let otherBuilder: ((Instantiator<Screen>) -> Other)?
			            let screenBuilder: Screen.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_otherBuilder() -> Other {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			            return if let safeDIBuilder = safeDIOverrides.otherBuilder { safeDIBuilder(screenBuilder) } else { Other(screenBuilder: screenBuilder) }
			        }
			        func __safeDI_screenBuilder(otherBuilder: Instantiator<Other>) -> Screen {
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(otherBuilder) } else { Detail(otherBuilder: otherBuilder) }
			            func __safeDI_stepBuilder() -> Step {
			                func __safeDI_otherBuilder() -> Other {
			                    let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			                    return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.otherBuilder { safeDIBuilder(screenBuilder) } else { Other(screenBuilder: screenBuilder) }
			                }
			                func __safeDI_screenBuilder_received() -> Screen {
			                    let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                    return __safeDI_screenBuilder(otherBuilder: otherBuilder)
			                }
			                let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			                let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(otherBuilder, screenBuilder) } else { Step(otherBuilder: otherBuilder, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(detail, stepBuilder) } else { Screen(detail: detail, stepBuilder: stepBuilder) }
			        }
			        func __safeDI_screenBuilder_received() -> Screen {
			            let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			            return __safeDI_screenBuilder(otherBuilder: otherBuilder)
			        }
			        let otherBuilder = Instantiator<Other>(__safeDI_otherBuilder)
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received)
			        return Root(otherBuilder: otherBuilder, screenBuilder: screenBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesReceivedFunctionApart_whenSiblingsBuilderFunctionHasItsName() async throws {
		// `Root` declares `screenBuilder_received`, whose builder function is `__safeDI_screenBuilder_received`, so the
		// function every wrapper of `screenBuilder` hands takes another name, as in production.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Session"),
			Self.type("Other"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let screenBuilder_received: Instantiator<Other>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init(),
			            screenBuilder_received: (() -> Other)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder,
			                screenBuilder_received: screenBuilder_received
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }
			        var screenBuilder_received: (() -> Other)? { __safeDI_storage.screenBuilder_received }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIMockConfiguration,
			                screenBuilder_received: (() -> Other)?
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			                self.screenBuilder_received = screenBuilder_received
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIMockConfiguration
			            let screenBuilder_received: (() -> Other)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let screenBuilder = Instantiator<Screen> {
			                __safeDI_screenBuilder(session: session)
			            }
			            func __safeDI_stepBuilder() -> Step {
			                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(screenBuilder) } else { Detail(screenBuilder: screenBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			        }
			        func __safeDI_screenBuilder_received_() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			        func __safeDI_screenBuilder_received() -> Other {
			            if let safeDIBuilder = safeDIOverrides.screenBuilder_received { safeDIBuilder() } else { Other() }
			        }
			        let screenBuilder_received = Instantiator<Other>(__safeDI_screenBuilder_received)
			        return Root(session: session, screenBuilder: screenBuilder, screenBuilder_received: screenBuilder_received)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesReceivedFunctionApart_whenCycleClosingNodeBeneathRefersToEnclosingFunctionOfItsName() async throws {
		// `Root` declares `screenBuilder_received`, whose builder function `__safeDI_screenBuilder_received` encloses `Flow`'s level, and `Tail`, beneath that level, closes a cycle on it by name, so the function every wrapper of `screenBuilder` hands takes another name, as in production.
		let fixture = [
			Self.type("Session"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Tail", "@Instantiated let screenBuilder_received: Instantiator<Flow>"),
			Self.type("Flow", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let tail: Tail"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let screenBuilder_received: Instantiator<Flow>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            screenBuilder_received: Flow.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                screenBuilder_received: screenBuilder_received
			            )
			        }

			        var screenBuilder_received: Flow.SafeDIMockConfiguration { __safeDI_storage.screenBuilder_received }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                screenBuilder_received: Flow.SafeDIMockConfiguration
			            ) {
			                self.screenBuilder_received = screenBuilder_received
			            }

			            let screenBuilder_received: Flow.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_screenBuilder_received() -> Flow {
			            let session = if let safeDIBuilder = safeDIOverrides.screenBuilder_received.session { safeDIBuilder() } else { Session() }
			            func __safeDI_screenBuilder(session: Session) -> Screen {
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                func __safeDI_stepBuilder() -> Step {
			                    let session = if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                    let screenBuilder = Instantiator<Screen> {
			                        __safeDI_screenBuilder(session: session)
			                    }
			                    return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			                }
			                let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			                let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.detail { safeDIBuilder(screenBuilder) } else { Detail(screenBuilder: screenBuilder) }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			            }
			            func __safeDI_screenBuilder_received_() -> Screen {
			                __safeDI_screenBuilder(session: session)
			            }
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			            func __safeDI_tail() -> Tail {
			                let screenBuilder_received = Instantiator<Flow>(__safeDI_screenBuilder_received)
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.tail.safeDIBuilder { safeDIBuilder(screenBuilder_received) } else { Tail(screenBuilder_received: screenBuilder_received) }
			            }
			            let tail: Tail = __safeDI_tail()
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder_received.safeDIBuilder { safeDIBuilder(session, screenBuilder, tail) } else { Flow(session: session, screenBuilder: screenBuilder, tail: tail) }
			        }
			        let screenBuilder_received = Instantiator<Flow>(__safeDI_screenBuilder_received)
			        return Root(screenBuilder_received: screenBuilder_received)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_namesReceivedFunctionApart_whenAnotherMembersLevelDeclaresBuilderFunctionOfItsName() async throws {
		// `Peer`, on the loop with `screenBuilder`, declares `screenBuilder_received`, whose builder function in `__safeDI_peerBuilder`'s body would hide the function `Peer`'s rebinding of `screenBuilder` hands, so that function takes another name, as in production.
		let fixture = [
			Self.type("Session"),
			Self.type("Other"),
			Self.type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let peerBuilder: Instantiator<Peer>"),
			Self.type("Peer", "@Received let screenBuilder: Instantiator<Screen>", "@Instantiated let screenBuilder_received: Instantiator<Other>"),
			Self.type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>", "@Instantiated let peerBuilder: Instantiator<Peer>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            session: (() -> Session)? = nil,
			            screenBuilder: Screen.SafeDIMockConfiguration = .init(),
			            peerBuilder: Peer.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                session: session,
			                screenBuilder: screenBuilder,
			                peerBuilder: peerBuilder
			            )
			        }

			        var session: (() -> Session)? { __safeDI_storage.session }
			        var screenBuilder: Screen.SafeDIMockConfiguration { __safeDI_storage.screenBuilder }
			        var peerBuilder: Peer.SafeDIMockConfiguration { __safeDI_storage.peerBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                session: (() -> Session)?,
			                screenBuilder: Screen.SafeDIMockConfiguration,
			                peerBuilder: Peer.SafeDIMockConfiguration
			            ) {
			                self.session = session
			                self.screenBuilder = screenBuilder
			                self.peerBuilder = peerBuilder
			            }

			            let session: (() -> Session)?
			            let screenBuilder: Screen.SafeDIMockConfiguration
			            let peerBuilder: Peer.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let session = if let safeDIBuilder = safeDIOverrides.session { safeDIBuilder() } else { Session() }
			        func __safeDI_screenBuilder(session: Session) -> Screen {
			            let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			            func __safeDI_stepBuilder() -> Step {
			                let session = if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.session { safeDIBuilder() } else { Session() }
			                let screenBuilder = Instantiator<Screen> {
			                    __safeDI_screenBuilder(session: session)
			                }
			                return if let safeDIBuilder = safeDIOverrides.screenBuilder.stepBuilder.safeDIBuilder { safeDIBuilder(session, screenBuilder) } else { Step(session: session, screenBuilder: screenBuilder) }
			            }
			            let stepBuilder = Instantiator<Step>(__safeDI_stepBuilder)
			            let detail = if let safeDIBuilder = safeDIOverrides.screenBuilder.detail { safeDIBuilder(peerBuilder) } else { Detail(peerBuilder: peerBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.screenBuilder.safeDIBuilder { safeDIBuilder(session, stepBuilder, detail) } else { Screen(session: session, stepBuilder: stepBuilder, detail: detail) }
			        }
			        func __safeDI_screenBuilder_received_() -> Screen {
			            __safeDI_screenBuilder(session: session)
			        }
			        func __safeDI_peerBuilder() -> Peer {
			            let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			            func __safeDI_screenBuilder_received() -> Other {
			                if let safeDIBuilder = safeDIOverrides.peerBuilder.screenBuilder_received { safeDIBuilder() } else { Other() }
			            }
			            let screenBuilder_received = Instantiator<Other>(__safeDI_screenBuilder_received)
			            return if let safeDIBuilder = safeDIOverrides.peerBuilder.safeDIBuilder { safeDIBuilder(screenBuilder, screenBuilder_received) } else { Peer(screenBuilder: screenBuilder, screenBuilder_received: screenBuilder_received) }
			        }
			        let screenBuilder = Instantiator<Screen>(__safeDI_screenBuilder_received_)
			        let peerBuilder = Instantiator<Peer>(__safeDI_peerBuilder)
			        return Root(session: session, screenBuilder: screenBuilder, peerBuilder: peerBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_spellsReceivedFunctionAsRawIdentifier_whenLoopMembersLabelIsRawIdentifier() async throws {
		let fixture = [
			Self.type("Session"),
			Self.type("Screen", "@Received let `c d`: Session", "@Instantiated let `a b`: Instantiator<Step>", "@Instantiated let detail: Detail"),
			Self.type("Detail", "@Received let `some thing`: Instantiator<Screen>", "@Received let peer: Instantiator<Peer>"),
			Self.type("Peer", "@Received let `some thing`: Instantiator<Screen>"),
			Self.type("Step", "@Instantiated let `c d`: Session", "@Instantiated let `some thing`: Instantiator<Screen>"),
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let `c d`: Session", "@Instantiated let `some thing`: Instantiator<Screen>", "@Instantiated let peer: Instantiator<Peer>"),
		]
		let output = try await executeSafeDIToolTest(swiftFileContent: fixture, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            `c d`: (() -> Session)? = nil,
			            `some thing`: Screen.SafeDIMockConfiguration = .init(),
			            peer: ((Instantiator<Screen>) -> Peer)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                `c d`: `c d`,
			                `some thing`: `some thing`,
			                peer: peer
			            )
			        }

			        var `c d`: (() -> Session)? { __safeDI_storage.`c d` }
			        var `some thing`: Screen.SafeDIMockConfiguration { __safeDI_storage.`some thing` }
			        var peer: ((Instantiator<Screen>) -> Peer)? { __safeDI_storage.peer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                `c d`: (() -> Session)?,
			                `some thing`: Screen.SafeDIMockConfiguration,
			                peer: ((Instantiator<Screen>) -> Peer)?
			            ) {
			                self.`c d` = `c d`
			                self.`some thing` = `some thing`
			                self.peer = peer
			            }

			            let `c d`: (() -> Session)?
			            let `some thing`: Screen.SafeDIMockConfiguration
			            let peer: ((Instantiator<Screen>) -> Peer)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        let `c d` = if let safeDIBuilder = safeDIOverrides.`c d` { safeDIBuilder() } else { Session() }
			        func `__safeDI_some thing`(`c d`: Session) -> Screen {
			            let `some thing` = Instantiator<Screen> {
			                `__safeDI_some thing`(`c d`: `c d`)
			            }
			            let peer = Instantiator<Peer>(__safeDI_peer)
			            func `__safeDI_a b`() -> Step {
			                let `c d` = if let safeDIBuilder = safeDIOverrides.`some thing`.`a b`.`c d` { safeDIBuilder() } else { Session() }
			                let `some thing` = Instantiator<Screen> {
			                    `__safeDI_some thing`(`c d`: `c d`)
			                }
			                return if let safeDIBuilder = safeDIOverrides.`some thing`.`a b`.safeDIBuilder { safeDIBuilder(`c d`, `some thing`) } else { Step(`c d`: `c d`, `some thing`: `some thing`) }
			            }
			            let `a b` = Instantiator<Step>(`__safeDI_a b`)
			            let detail = if let safeDIBuilder = safeDIOverrides.`some thing`.detail { safeDIBuilder(`some thing`, peer) } else { Detail(`some thing`: `some thing`, peer: peer) }
			            return if let safeDIBuilder = safeDIOverrides.`some thing`.safeDIBuilder { safeDIBuilder(`c d`, `a b`, detail) } else { Screen(`c d`: `c d`, `a b`: `a b`, detail: detail) }
			        }
			        func `__safeDI_some thing_received`() -> Screen {
			            `__safeDI_some thing`(`c d`: `c d`)
			        }
			        func __safeDI_peer() -> Peer {
			            let `some thing` = Instantiator<Screen>(`__safeDI_some thing_received`)
			            return if let safeDIBuilder = safeDIOverrides.peer { safeDIBuilder(`some thing`) } else { Peer(`some thing`: `some thing`) }
			        }
			        let `some thing` = Instantiator<Screen>(`__safeDI_some thing_received`)
			        let peer = Instantiator<Peer>(__safeDI_peer)
			        return Root(`c d`: `c d`, `some thing`: `some thing`, peer: peer)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
		try await expectMockBuildsWhatProductionBuilds(fixture: fixture, output: output)
	}

	// MARK: Tests – Public mocks

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuildersFromCallersValue_whenPublicMocksPromotedBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: .public)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            bBuilder: ((Instantiator<A>) -> B)? = nil,
			            aBuilder: ((Instantiator<B>) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                aBuilder: aBuilder
			            )
			        }

			        public var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }
			        public var aBuilder: ((Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: ((Instantiator<A>) -> B)?,
			                aBuilder: ((Instantiator<B>) -> A)?
			            ) {
			                self.bBuilder = bBuilder
			                self.aBuilder = aBuilder
			            }

			            let bBuilder: ((Instantiator<A>) -> B)?
			            let aBuilder: ((Instantiator<B>) -> A)?
			        }
			    }

			    public static func mock(
			        aBuilder: Instantiator<A>? = nil,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(aBuilder: aBuilder, bBuilder: bBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        aBuilder: Instantiator<A>? = nil,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = if let aBuilder { aBuilder } else { Instantiator<A>(__safeDI_aBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			        return A(bBuilder: bBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_DC87377F9DD950EC {}
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – Loops a mock reaches beside or beneath the mocked type

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilderInsideItsFunction_whenConstantInsideItsTreeReceivesIt_withRoot() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(isRoot: true, generateMock: true)
				public struct Root: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Instantiated let aBuilder: Instantiator<A>
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct A: Instantiable {
				    public init(b: B) { self.b = b }
				    @Instantiated let b: B
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init(),
			            b: ((Instantiator<A>) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                b: b
			            )
			        }

			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }
			        var b: ((Instantiator<A>) -> B)? { __safeDI_storage.b }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: A.SafeDIMockConfiguration,
			                b: ((Instantiator<A>) -> B)?
			            ) {
			                self.aBuilder = aBuilder
			                self.b = b
			            }

			            let aBuilder: A.SafeDIMockConfiguration
			            let b: ((Instantiator<A>) -> B)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration) -> A {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            let b = if let safeDIBuilder = __safeDI_A_configuration.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        let b = if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: ((Instantiator<A>) -> B)? = nil,
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                b: b,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var b: ((Instantiator<A>) -> B)? { __safeDI_storage.b }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((B) -> A)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                b: ((Instantiator<A>) -> B)?,
			                safeDIBuilder: ((B) -> A)?
			            ) {
			                self.b = b
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let b: ((Instantiator<A>) -> B)?
			            let safeDIBuilder: ((B) -> A)?
			        }
			    }
			}
			#endif
			""",
			"B+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder
			            )
			        }

			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: A.SafeDIMockConfiguration
			            ) {
			                self.aBuilder = aBuilder
			            }

			            let aBuilder: A.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration) -> A {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            let b = if let safeDIBuilder = __safeDI_A_configuration.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        return B(aBuilder: aBuilder)
			    }
			}
			#endif
			""",
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder
			            )
			        }

			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: A.SafeDIMockConfiguration
			            ) {
			                self.aBuilder = aBuilder
			            }

			            let aBuilder: A.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration) -> A {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            let b = if let safeDIBuilder = __safeDI_A_configuration.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        return Root(aBuilder: aBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilderInsideItsFunction_whenConstantInsideItsTreeReceivesIt_withoutRoot() async throws {
		// The loop of the _withRoot test with no root: `B`'s mock promotes `aBuilder`, whose tree receives it.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct A: Instantiable {
				    public init(b: B) { self.b = b }
				    @Instantiated let b: B
				}
				""",
				"""
				@Instantiable(generateMock: true)
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init(),
			            b: ((Instantiator<A>) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                b: b
			            )
			        }

			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }
			        var b: ((Instantiator<A>) -> B)? { __safeDI_storage.b }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: A.SafeDIMockConfiguration,
			                b: ((Instantiator<A>) -> B)?
			            ) {
			                self.aBuilder = aBuilder
			                self.b = b
			            }

			            let aBuilder: A.SafeDIMockConfiguration
			            let b: ((Instantiator<A>) -> B)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration) -> A {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            let b = if let safeDIBuilder = __safeDI_A_configuration.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        let b = if let safeDIBuilder = safeDIOverrides.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        return A(b: b)
			    }
			}
			#endif

			#if DEBUG
			extension A {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            b: ((Instantiator<A>) -> B)? = nil,
			            _ safeDIBuilder: ((B) -> A)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                b: b,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var b: ((Instantiator<A>) -> B)? { __safeDI_storage.b }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((B) -> A)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                b: ((Instantiator<A>) -> B)?,
			                safeDIBuilder: ((B) -> A)?
			            ) {
			                self.b = b
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let b: ((Instantiator<A>) -> B)?
			            let safeDIBuilder: ((B) -> A)?
			        }
			    }
			}
			#endif
			""",
			"B+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension B {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder
			            )
			        }

			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: A.SafeDIMockConfiguration
			            ) {
			                self.aBuilder = aBuilder
			            }

			            let aBuilder: A.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> B {
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration) -> A {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            let b = if let safeDIBuilder = __safeDI_A_configuration.b { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(b) } else { A(b: b) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        return B(aBuilder: aBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsEachOtherBuilderInsideEachFunction_whenNonRootMockedTypesBuildersReceiveEachOther() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Parent: Instantiable {
				    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
				        self.aBuilder = aBuilder
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct A: Instantiable {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Received let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            aBuilder: ((Instantiator<B>) -> A)? = nil,
			            bBuilder: ((Instantiator<A>) -> B)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                aBuilder: aBuilder,
			                bBuilder: bBuilder
			            )
			        }

			        var aBuilder: ((Instantiator<B>) -> A)? { __safeDI_storage.aBuilder }
			        var bBuilder: ((Instantiator<A>) -> B)? { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                aBuilder: ((Instantiator<B>) -> A)?,
			                bBuilder: ((Instantiator<A>) -> B)?
			            ) {
			                self.aBuilder = aBuilder
			                self.bBuilder = bBuilder
			            }

			            let aBuilder: ((Instantiator<B>) -> A)?
			            let bBuilder: ((Instantiator<A>) -> B)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_aBuilder(__safeDI_A_configuration: ((Instantiator<B>) -> A)?) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder(__safeDI_B_configuration: ((Instantiator<A>) -> B)?) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder)
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        return Parent(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsEachOtherBuilderInsideEachFunction_whenBuildersOfPromotedScopeReceiveEachOther() async throws {
		// Only `Top`'s mock reaches `Holder`, by promoting the `holder` that `Top` receives.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Top: Instantiable {
				    public init(holder: Holder) { self.holder = holder }
				    @Received let holder: Holder
				}
				""",
				"""
				@Instantiable
				public struct Holder: Instantiable {
				    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
				        self.aBuilder = aBuilder
				        self.bBuilder = bBuilder
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct A: Instantiable {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Received let bBuilder: Instantiator<B>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
				    @Received let aBuilder: Instantiator<A>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Top+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Top {
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
			    ) -> Top {
			        func __safeDI_aBuilder(__safeDI_A_configuration: ((Instantiator<B>) -> A)?, __safeDI_Holder_loopConfiguration: Holder.SafeDIMockConfiguration) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: __safeDI_Holder_loopConfiguration.bBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_loopConfiguration)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder(__safeDI_B_configuration: ((Instantiator<A>) -> B)?, __safeDI_Holder_loopConfiguration: Holder.SafeDIMockConfiguration) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: __safeDI_Holder_loopConfiguration.aBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_loopConfiguration)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        func __safeDI_holder(__safeDI_Holder_configuration: Holder.SafeDIMockConfiguration) -> Holder {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: __safeDI_Holder_configuration.aBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_configuration)
			            }
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: __safeDI_Holder_configuration.bBuilder, __safeDI_Holder_loopConfiguration: __safeDI_Holder_configuration)
			            }
			            return if let safeDIBuilder = __safeDI_Holder_configuration.safeDIBuilder { safeDIBuilder(aBuilder, bBuilder) } else { Holder(aBuilder: aBuilder, bBuilder: bBuilder) }
			        }
			        let holder: Holder = __safeDI_holder(__safeDI_Holder_configuration: safeDIOverrides.holder)
			        return Top(holder: holder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilders_whenSiblingInstantiatorIsReceivedInsideLazyCycleOfEarlierSibling() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Parent: Instantiable {
				    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, qBuilder: Instantiator<Q>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let aBuilder: Instantiator<A>
				    @Instantiated let bBuilder: Instantiator<B>
				    @Instantiated let qBuilder: Instantiator<Q>
				}
				""",
				"""
				@Instantiable
				public struct A: Instantiable {
				    public init(innerBBuilder: Instantiator<B>, qBuilder: Instantiator<Q>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let innerBBuilder: Instantiator<B>
				    @Received let qBuilder: Instantiator<Q>
				}
				""",
				"""
				@Instantiable
				public struct B: Instantiable {
				    public init(innerABuilder: Instantiator<A>) { self.innerABuilder = innerABuilder }
				    @Instantiated let innerABuilder: Instantiator<A>
				}
				""",
				"""
				@Instantiable
				public struct Q: Instantiable {
				    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
				    @Received let bBuilder: Instantiator<B>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Parent+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Parent {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init(),
			            qBuilder: ((Instantiator<B>) -> Q)? = nil,
			            aBuilder: A.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder,
			                qBuilder: qBuilder,
			                aBuilder: aBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }
			        var qBuilder: ((Instantiator<B>) -> Q)? { __safeDI_storage.qBuilder }
			        var aBuilder: A.SafeDIMockConfiguration { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration,
			                qBuilder: ((Instantiator<B>) -> Q)?,
			                aBuilder: A.SafeDIMockConfiguration
			            ) {
			                self.bBuilder = bBuilder
			                self.qBuilder = qBuilder
			                self.aBuilder = aBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			            let qBuilder: ((Instantiator<B>) -> Q)?
			            let aBuilder: A.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Parent {
			        func __safeDI_bBuilder(__safeDI_B_configuration: B.SafeDIMockConfiguration, __safeDI_A_configuration_nearest: A.SafeDIMockConfiguration?) -> B {
			            let qBuilder = Instantiator<Q> {
			                __safeDI_qBuilder(__safeDI_Q_configuration: safeDIOverrides.qBuilder, __safeDI_A_configuration_nearest: __safeDI_A_configuration_nearest)
			            }
			            let innerABuilder = Instantiator<A> {
			                __safeDI_innerABuilder(qBuilder: qBuilder, __safeDI_A_configuration: __safeDI_A_configuration_nearest ?? A.SafeDIMockConfiguration(), __safeDI_B_configuration_nearest: __safeDI_B_configuration)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(innerABuilder) } else { B(innerABuilder: innerABuilder) }
			        }
			        func __safeDI_qBuilder(__safeDI_Q_configuration: ((Instantiator<B>) -> Q)?, __safeDI_A_configuration_nearest: A.SafeDIMockConfiguration?) -> Q {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder, __safeDI_A_configuration_nearest: __safeDI_A_configuration_nearest)
			            }
			            return if let safeDIBuilder = __safeDI_Q_configuration { safeDIBuilder(bBuilder) } else { Q(bBuilder: bBuilder) }
			        }
			        func __safeDI_innerABuilder(qBuilder: Instantiator<Q>, __safeDI_A_configuration: A.SafeDIMockConfiguration, __safeDI_B_configuration_nearest: B.SafeDIMockConfiguration?) -> A {
			            let innerBBuilder = Instantiator<B> {
			                __safeDI_innerBBuilder(qBuilder: qBuilder, __safeDI_B_configuration: __safeDI_B_configuration_nearest ?? B.SafeDIMockConfiguration(), __safeDI_A_configuration_nearest: __safeDI_A_configuration)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(innerBBuilder, qBuilder) } else { A(innerBBuilder: innerBBuilder, qBuilder: qBuilder) }
			        }
			        func __safeDI_innerBBuilder(qBuilder: Instantiator<Q>, __safeDI_B_configuration: B.SafeDIMockConfiguration, __safeDI_A_configuration_nearest: A.SafeDIMockConfiguration?) -> B {
			            let innerABuilder = Instantiator<A> {
			                __safeDI_innerABuilder(qBuilder: qBuilder, __safeDI_A_configuration: __safeDI_A_configuration_nearest ?? A.SafeDIMockConfiguration(), __safeDI_B_configuration_nearest: __safeDI_B_configuration)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(innerABuilder) } else { B(innerABuilder: innerABuilder) }
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder, __safeDI_A_configuration_nearest: nil)
			        }
			        let qBuilder = Instantiator<Q> {
			            __safeDI_qBuilder(__safeDI_Q_configuration: safeDIOverrides.qBuilder, __safeDI_A_configuration_nearest: nil)
			        }
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration, __safeDI_B_configuration_nearest: B.SafeDIMockConfiguration?) -> A {
			            let innerBBuilder = Instantiator<B> {
			                __safeDI_innerBBuilder_(__safeDI_B_configuration: __safeDI_B_configuration_nearest ?? __safeDI_A_configuration.innerBBuilder, __safeDI_A_configuration_nearest: __safeDI_A_configuration)
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(innerBBuilder, qBuilder) } else { A(innerBBuilder: innerBBuilder, qBuilder: qBuilder) }
			        }
			        func __safeDI_innerBBuilder_(__safeDI_B_configuration: B.SafeDIMockConfiguration, __safeDI_A_configuration_nearest: A.SafeDIMockConfiguration?) -> B {
			            let innerABuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: __safeDI_A_configuration_nearest ?? A.SafeDIMockConfiguration(), __safeDI_B_configuration_nearest: __safeDI_B_configuration)
			            }
			            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(innerABuilder) } else { B(innerABuilder: innerABuilder) }
			        }
			        let aBuilder = Instantiator<A> {
			            __safeDI_aBuilder(__safeDI_A_configuration: safeDIOverrides.aBuilder, __safeDI_B_configuration_nearest: nil)
			        }
			        return Parent(aBuilder: aBuilder, bBuilder: bBuilder, qBuilder: qBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsDisambiguatedBuilder_whenTreeOfTypeReceivedByValueReceivesItsInstantiator_andTypeSortsBeforeInstantiator() async throws {
		// Consumer receives `x: Abc`, and the Inner that Abc instantiates receives `x: Instantiator<Abc>`. The mock
		// builds both forms, under names of their own, and the Abc that the Instantiator builds is passed the wrapper its
		// function makes again of itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(consumer: Consumer) { self.consumer = consumer }
				    @Instantiated let consumer: Consumer
				}
				""",
				"""
				@Instantiable
				public struct Consumer: Instantiable {
				    public init(x: Abc) { self.x = x }
				    @Received let x: Abc
				}
				""",
				"""
				@Instantiable
				public struct Abc: Instantiable {
				    public init(inner: Inner) { self.inner = inner }
				    @Instantiated let inner: Inner
				}
				""",
				"""
				@Instantiable
				public struct Inner: Instantiable {
				    public init(x: Instantiator<Abc>) { self.x = x }
				    @Received let x: Instantiator<Abc>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            x_Instantiator__Abc: Abc.SafeDIMockConfiguration = .init(),
			            x_Abc: Abc.SafeDIMockConfiguration = .init(),
			            consumer: ((Abc) -> Consumer)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                x_Instantiator__Abc: x_Instantiator__Abc,
			                x_Abc: x_Abc,
			                consumer: consumer
			            )
			        }

			        var x_Instantiator__Abc: Abc.SafeDIMockConfiguration { __safeDI_storage.x_Instantiator__Abc }
			        var x_Abc: Abc.SafeDIMockConfiguration { __safeDI_storage.x_Abc }
			        var consumer: ((Abc) -> Consumer)? { __safeDI_storage.consumer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                x_Instantiator__Abc: Abc.SafeDIMockConfiguration,
			                x_Abc: Abc.SafeDIMockConfiguration,
			                consumer: ((Abc) -> Consumer)?
			            ) {
			                self.x_Instantiator__Abc = x_Instantiator__Abc
			                self.x_Abc = x_Abc
			                self.consumer = consumer
			            }

			            let x_Instantiator__Abc: Abc.SafeDIMockConfiguration
			            let x_Abc: Abc.SafeDIMockConfiguration
			            let consumer: ((Abc) -> Consumer)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_x_Instantiator__Abc() -> Abc {
			            let x_Instantiator__Abc = Instantiator<Abc>(__safeDI_x_Instantiator__Abc)
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Abc> = x_Instantiator__Abc
			                return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Abc.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Abc.safeDIBuilder { safeDIBuilder(inner) } else { Abc(inner: inner) }
			        }
			        let x_Instantiator__Abc = Instantiator<Abc>(__safeDI_x_Instantiator__Abc)
			        func __safeDI_x_Abc() -> Abc {
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Abc> = x_Instantiator__Abc
			                return if let safeDIBuilder = safeDIOverrides.x_Abc.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Abc.safeDIBuilder { safeDIBuilder(inner) } else { Abc(inner: inner) }
			        }
			        let x_Abc: Abc = __safeDI_x_Abc()
			        func __safeDI_consumer() -> Consumer {
			            let x: Abc = x_Abc
			            return if let safeDIBuilder = safeDIOverrides.consumer { safeDIBuilder(x) } else { Consumer(x: x) }
			        }
			        let consumer: Consumer = __safeDI_consumer()
			        return Root(consumer: consumer)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsDisambiguatedBuilder_whenTreeOfTypeReceivedByValueReceivesItsInstantiator_andTypeSortsAfterInstantiator() async throws {
		// The graph of the test above with `Abc` renamed to `Xyz`, which sorts after `Instantiator<Xyz>`. The mock is
		// the same, with the type renamed.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Root: Instantiable {
				    public init(consumer: Consumer) { self.consumer = consumer }
				    @Instantiated let consumer: Consumer
				}
				""",
				"""
				@Instantiable
				public struct Consumer: Instantiable {
				    public init(x: Xyz) { self.x = x }
				    @Received let x: Xyz
				}
				""",
				"""
				@Instantiable
				public struct Xyz: Instantiable {
				    public init(inner: Inner) { self.inner = inner }
				    @Instantiated let inner: Inner
				}
				""",
				"""
				@Instantiable
				public struct Inner: Instantiable {
				    public init(x: Instantiator<Xyz>) { self.x = x }
				    @Received let x: Instantiator<Xyz>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Root {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            x_Instantiator__Xyz: Xyz.SafeDIMockConfiguration = .init(),
			            x_Xyz: Xyz.SafeDIMockConfiguration = .init(),
			            consumer: ((Xyz) -> Consumer)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                x_Instantiator__Xyz: x_Instantiator__Xyz,
			                x_Xyz: x_Xyz,
			                consumer: consumer
			            )
			        }

			        var x_Instantiator__Xyz: Xyz.SafeDIMockConfiguration { __safeDI_storage.x_Instantiator__Xyz }
			        var x_Xyz: Xyz.SafeDIMockConfiguration { __safeDI_storage.x_Xyz }
			        var consumer: ((Xyz) -> Consumer)? { __safeDI_storage.consumer }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                x_Instantiator__Xyz: Xyz.SafeDIMockConfiguration,
			                x_Xyz: Xyz.SafeDIMockConfiguration,
			                consumer: ((Xyz) -> Consumer)?
			            ) {
			                self.x_Instantiator__Xyz = x_Instantiator__Xyz
			                self.x_Xyz = x_Xyz
			                self.consumer = consumer
			            }

			            let x_Instantiator__Xyz: Xyz.SafeDIMockConfiguration
			            let x_Xyz: Xyz.SafeDIMockConfiguration
			            let consumer: ((Xyz) -> Consumer)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Root {
			        func __safeDI_x_Instantiator__Xyz() -> Xyz {
			            let x_Instantiator__Xyz = Instantiator<Xyz>(__safeDI_x_Instantiator__Xyz)
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Xyz> = x_Instantiator__Xyz
			                return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Xyz.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Instantiator__Xyz.safeDIBuilder { safeDIBuilder(inner) } else { Xyz(inner: inner) }
			        }
			        let x_Instantiator__Xyz = Instantiator<Xyz>(__safeDI_x_Instantiator__Xyz)
			        func __safeDI_x_Xyz() -> Xyz {
			            func __safeDI_inner() -> Inner {
			                let x: Instantiator<Xyz> = x_Instantiator__Xyz
			                return if let safeDIBuilder = safeDIOverrides.x_Xyz.inner { safeDIBuilder(x) } else { Inner(x: x) }
			            }
			            let inner: Inner = __safeDI_inner()
			            return if let safeDIBuilder = safeDIOverrides.x_Xyz.safeDIBuilder { safeDIBuilder(inner) } else { Xyz(inner: inner) }
			        }
			        let x_Xyz: Xyz = __safeDI_x_Xyz()
			        func __safeDI_consumer() -> Consumer {
			            let x: Xyz = x_Xyz
			            return if let safeDIBuilder = safeDIOverrides.consumer { safeDIBuilder(x) } else { Consumer(x: x) }
			        }
			        let consumer: Consumer = __safeDI_consumer()
			        return Root(consumer: consumer)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// No time limit; see `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesWithinTimeLimit_whenEveryReceivedInstantiatorPathFromEarlierSiblingsEndsInLoopOfInstantiators() async throws {
		// Each layer holds a Left and a Right service that both receive Instantiators of the two
		// services of the next layer, and the last layer's services receive an Instantiator of Ping,
		// which receives one of Pong, which receives one of Ping. Feature's mock promotes every one of
		// those Instantiators, so the number of received paths from any layer to that loop doubles
		// with each layer.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["pingBuilder: Instantiator<Ping>"]
				: ["left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
			return ["Left\(layer)", "Right\(layer)"].map { type in
				"""
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(receivedProperties.joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(left0Builder: Instantiator<Left0>, right0Builder: Instantiator<Right0>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let left0Builder: Instantiator<Left0>
				    @Instantiated let right0Builder: Instantiator<Right0>
				}
				""",
				"""
				@Instantiable
				public struct Ping: Instantiable {
				    public init(pongBuilder: Instantiator<Pong>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pongBuilder: Instantiator<Pong>
				}
				""",
				"""
				@Instantiable
				public struct Pong: Instantiable {
				    public init(pingBuilder: Instantiator<Ping>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pingBuilder: Instantiator<Ping>
				}
				""",
			] + layerFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)
		#expect(output.mockFiles.keys.sorted() == ["Feature+SafeDIMock.swift"])
		#expect(output.dependencyTreeFiles.isEmpty)
	}

	// No time limit; see `mock_generatesWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_generatesWithinTimeLimit_whenEveryReceivedAliasPathFromEarlierSiblingsEndsInLoopOfInstantiatorsOfLazyCycles() async throws {
		// Each layer holds a Left and a Right service that instantiate Instantiators of each other and
		// receive aliases of the Instantiators of the two services of the next layer. The last layer's
		// services receive an alias of Ping's Instantiator, and Ping and Pong receive aliases of each other's.
		// Feature declares the aliases of the last layer first.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["pingAlias: Instantiator<Ping>"]
				: ["left\(layer + 1)Alias: Instantiator<Left\(layer + 1)>", "right\(layer + 1)Alias: Instantiator<Right\(layer + 1)>"]
			return [("Left\(layer)", "Right\(layer)"), ("Right\(layer)", "Left\(layer)")].map { type, otherType in
				let instantiatedProperty = "inner\(otherType)Builder: Instantiator<\(otherType)>"
				return """
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(([instantiatedProperty] + receivedProperties).joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let \(instantiatedProperty)
				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		func alias(_ label: String, of fulfillingLabel: String, type: String) -> (property: String, declaration: String) {
			("\(label): \(type)", "@Received(fulfilledByDependencyNamed: \"\(fulfillingLabel)\", ofType: \(type).self) let \(label): \(type)")
		}
		let featureBuilders = (0..<layerCount).flatMap { ["left\($0)Builder: Instantiator<Left\($0)>", "right\($0)Builder: Instantiator<Right\($0)>"] } + ["pingBuilder: Instantiator<Ping>", "pongBuilder: Instantiator<Pong>"]
		let featureAliases = (0..<layerCount).reversed().flatMap { layer in
			["Left\(layer)", "Right\(layer)"].map { type in
				let label = type.prefix(1).lowercased() + type.dropFirst()
				return alias("\(label)Alias", of: "\(label)Builder", type: "Instantiator<\(type)>")
			}
		}
			+ [
				alias("pingAlias", of: "pingBuilder", type: "Instantiator<Ping>"),
				alias("pongAlias", of: "pongBuilder", type: "Instantiator<Pong>"),
			]
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public struct Feature: Instantiable {
				    public init(\((featureBuilders + featureAliases.map(\.property)).joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				\(featureBuilders.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
				\(featureAliases.map { "    \($0.declaration)" }.joined(separator: "\n"))
				}
				""",
				"""
				@Instantiable
				public struct Ping: Instantiable {
				    public init(pongAlias: Instantiator<Pong>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pongAlias: Instantiator<Pong>
				}
				""",
				"""
				@Instantiable
				public struct Pong: Instantiable {
				    public init(pingAlias: Instantiator<Ping>) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Received let pingAlias: Instantiator<Ping>
				}
				""",
			] + layerFiles,
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			skipCompileVerification: true,
		)
		#expect(output.mockFiles.keys.sorted() == ["Feature+SafeDIMock.swift"])
		#expect(output.dependencyTreeFiles.isEmpty)
	}

	// MARK: Tests – Renames of a builder that builds the type renaming it

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilderForTypesOwnRename_whenMockedTypeRenamesBuilderThatBuildsIt() async throws {
		// The mock promotes `nodeBuilder` to build Node, and the Node it builds aliases `nodeBuilder`
		// itself, so `__safeDI_nodeBuilder` wraps itself again for the alias.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Node: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder
			            )
			        }

			        var nodeBuilder: ((Instantiator<Node>) -> Node)? { __safeDI_storage.nodeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: ((Instantiator<Node>) -> Node)?
			            ) {
			                self.nodeBuilder = nodeBuilder
			            }

			            let nodeBuilder: ((Instantiator<Node>) -> Node)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder(__safeDI_Node_configuration: ((Instantiator<Node>) -> Node)?) -> Node {
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			            }
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Node_configuration { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			        }
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let childBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedSendableBuilderForTypesOwnRename_whenMockedTypeRenamesSendableBuilderThatBuildsIt() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Node: Instantiable, Sendable {
				    public init(childBuilder: SendableInstantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: SendableInstantiator<Node>.self) let childBuilder: SendableInstantiator<Node>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: (@Sendable (SendableInstantiator<Node>) -> Node)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder
			            )
			        }

			        var nodeBuilder: (@Sendable (SendableInstantiator<Node>) -> Node)? { __safeDI_storage.nodeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage: Sendable {
			            init(
			                nodeBuilder: (@Sendable (SendableInstantiator<Node>) -> Node)?
			            ) {
			                self.nodeBuilder = nodeBuilder
			            }

			            let nodeBuilder: (@Sendable (SendableInstantiator<Node>) -> Node)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        @Sendable nonisolated func __safeDI_nodeBuilder(__safeDI_Node_configuration: (@Sendable (SendableInstantiator<Node>) -> Node)?) -> Node {
			            let nodeBuilder = SendableInstantiator<Node> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: __safeDI_Node_configuration)
			            }
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let childBuilder: SendableInstantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Node_configuration { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let __safeDI_nodeBuilder____safeDI_Node_configuration: (@Sendable (SendableInstantiator<Node>) -> Node)? = safeDIOverrides.nodeBuilder
			        let nodeBuilder = SendableInstantiator<Node> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: __safeDI_nodeBuilder____safeDI_Node_configuration)
			        }
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let childBuilder: SendableInstantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_erasesBuilderMadeAgain_whenMockedTypeRenamesBuilderThatBuildsItErasingIt() async throws {
		// Holder's erasure lets the mock build `nodeBuilder: ErasedInstantiator<(), AnyNode>` from Node,
		// and the Node it builds aliases that instantiator, erased to another wrapper, which wraps the
		// instantiator `__safeDI_nodeBuilder` makes again of itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
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
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((AnyNodeFactory) -> AnyNode)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder
			            )
			        }

			        var nodeBuilder: ((AnyNodeFactory) -> AnyNode)? { __safeDI_storage.nodeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: ((AnyNodeFactory) -> AnyNode)?
			            ) {
			                self.nodeBuilder = nodeBuilder
			            }

			            let nodeBuilder: ((AnyNodeFactory) -> AnyNode)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder(__safeDI_Node_configuration: ((AnyNodeFactory) -> AnyNode)?) -> AnyNode {
			            let nodeBuilder = ErasedInstantiator<(), AnyNode> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			            }
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let childBuilder: AnyNodeFactory = AnyNodeFactory(nodeBuilder)
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Node_configuration { safeDIBuilder(childBuilder) } else { AnyNode(Node(childBuilder: childBuilder)) }
			        }
			        let nodeBuilder = ErasedInstantiator<(), AnyNode> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			        }
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let childBuilder: AnyNodeFactory = AnyNodeFactory(nodeBuilder)
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilder_whenChildRenamesAgainMockedTypesRenameOfBuilderThatBuildsIt() async throws {
		// Node renames `nodeBuilder` to `middleBuilder`, and its child renames `middleBuilder` to
		// `childBuilder`. The Node that the promoted `nodeBuilder` builds renames the wrapper its
		// function makes again of itself.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Node: Instantiable {
				    public init(middleBuilder: Instantiator<Node>, child: Child) { self.middleBuilder = middleBuilder; self.child = child }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let middleBuilder: Instantiator<Node>
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "middleBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: Node.SafeDIMockConfiguration = .init(),
			            child: ((Instantiator<Node>) -> Child)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder,
			                child: child
			            )
			        }

			        var nodeBuilder: Node.SafeDIMockConfiguration { __safeDI_storage.nodeBuilder }
			        var child: ((Instantiator<Node>) -> Child)? { __safeDI_storage.child }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: Node.SafeDIMockConfiguration,
			                child: ((Instantiator<Node>) -> Child)?
			            ) {
			                self.nodeBuilder = nodeBuilder
			                self.child = child
			            }

			            let nodeBuilder: Node.SafeDIMockConfiguration
			            let child: ((Instantiator<Node>) -> Child)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder(__safeDI_Node_configuration: Node.SafeDIMockConfiguration) -> Node {
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			            }
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			            let middleBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            let child: Child = __safeDI_child(middleBuilder: middleBuilder, __safeDI_Child_configuration: __safeDI_Node_configuration.child)
			            return if let safeDIBuilder = __safeDI_Node_configuration.safeDIBuilder { safeDIBuilder(middleBuilder, child) } else { Node(middleBuilder: middleBuilder, child: child) }
			        }
			        func __safeDI_child(middleBuilder: Instantiator<Node>, __safeDI_Child_configuration: ((Instantiator<Node>) -> Child)?) -> Child {
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = middleBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Child_configuration { safeDIBuilder(childBuilder) } else { Child(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			        }
			        #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 4)
			        let middleBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        let child: Child = __safeDI_child(middleBuilder: middleBuilder, __safeDI_Child_configuration: safeDIOverrides.child)
			        return Node(middleBuilder: middleBuilder, child: child)
			    }
			}
			#endif

			#if DEBUG
			extension Node {
			    /// Configuration for how this type is constructed within a mock tree.
			    struct SafeDIMockConfiguration {
			        init(
			            child: ((Instantiator<Node>) -> Child)? = nil,
			            _ safeDIBuilder: ((Instantiator<Node>, Child) -> Node)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                child: child,
			                safeDIBuilder: safeDIBuilder
			            )
			        }

			        var child: ((Instantiator<Node>) -> Child)? { __safeDI_storage.child }
			        /// Overrides how this type is constructed. Parameters match the type’s initializer or custom mock method. When `nil`, the default generated construction function is used.
			        var safeDIBuilder: ((Instantiator<Node>, Child) -> Node)? { __safeDI_storage.safeDIBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                child: ((Instantiator<Node>) -> Child)?,
			                safeDIBuilder: ((Instantiator<Node>, Child) -> Node)?
			            ) {
			                self.child = child
			                self.safeDIBuilder = safeDIBuilder
			            }

			            let child: ((Instantiator<Node>) -> Child)?
			            let safeDIBuilder: ((Instantiator<Node>, Child) -> Node)?
			        }
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilder_whenRenameInsideItsTreeReceivesIt() async throws {
		// Screen receives `nodeBuilder`, which the mock promotes. Child, built inside the Node it builds,
		// aliases `nodeBuilder`.
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(nodeBuilder: Instantiator<Node>) { self.nodeBuilder = nodeBuilder }
				    @Received let nodeBuilder: Instantiator<Node>
				}
				""",
				"""
				@Instantiable
				public final class Node: Instantiable {
				    public init(child: Child) { self.child = child }
				    @Instantiated let child: Child
				}
				""",
				"""
				@Instantiable
				public final class Child: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
				}
				""",
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: Node.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder
			            )
			        }

			        var nodeBuilder: Node.SafeDIMockConfiguration { __safeDI_storage.nodeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: Node.SafeDIMockConfiguration
			            ) {
			                self.nodeBuilder = nodeBuilder
			            }

			            let nodeBuilder: Node.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_nodeBuilder(__safeDI_Node_configuration: Node.SafeDIMockConfiguration) -> Node {
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			            }
			            let child: Child = __safeDI_child(nodeBuilder: nodeBuilder, __safeDI_Child_configuration: __safeDI_Node_configuration.child)
			            return if let safeDIBuilder = __safeDI_Node_configuration.safeDIBuilder { safeDIBuilder(child) } else { Node(child: child) }
			        }
			        func __safeDI_child(nodeBuilder: Instantiator<Node>, __safeDI_Child_configuration: ((Instantiator<Node>) -> Child)?) -> Child {
			            #sourceLocation(file: "\(output.fixtures["Child.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Child_configuration { safeDIBuilder(childBuilder) } else { Child(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			        }
			        return Screen(nodeBuilder: nodeBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsPromotedBuilder_whenTypeListedInAdditionalMocksToGenerateRenamesBuilderThatBuildsIt() async throws {
		// Node is defined in a dependent module without generateMock: true.
		let dependentModuleOutput = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				@Instantiable
				public final class Node: Instantiable {
				    public init(childBuilder: Instantiator<Node>) { self.childBuilder = childBuilder }
				    @Received(fulfilledByDependencyNamed: "nodeBuilder", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>
				}
				""",
			],
			filesToDelete: &filesToDelete,
			moduleMembershipArguments: ["--module-name", "DependentModule", "--package-name", "Example"],
		)
		let dependentModuleFixtures = dependentModuleOutput.fixtures

		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				"""
				#SafeDIConfiguration(
				    additionalMocksToGenerate: [
				        "Node",
				    ]
				)
				""",
			],
			dependentModuleInfoPaths: [dependentModuleOutput.writtenModuleInfoOutputPath],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			// The verifier compiles one module, and `Node` is declared in another.
			skipCompileVerification: true,
		)
		#expect(output.mockFiles == [
			"Node+SafeDIMock.swift": generatedFileHeader + """
			#if canImport(DependentModule)
			import DependentModule
			#endif

			#if DEBUG
			extension Node {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder
			            )
			        }

			        var nodeBuilder: ((Instantiator<Node>) -> Node)? { __safeDI_storage.nodeBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: ((Instantiator<Node>) -> Node)?
			            ) {
			                self.nodeBuilder = nodeBuilder
			            }

			            let nodeBuilder: ((Instantiator<Node>) -> Node)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Node {
			        func __safeDI_nodeBuilder(__safeDI_Node_configuration: ((Instantiator<Node>) -> Node)?) -> Node {
			            let nodeBuilder = Instantiator<Node> {
			                __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			            }
			            #sourceLocation(file: "\(dependentModuleFixtures["Node.swift"])", line: 4)
			            let childBuilder: Instantiator<Node> = nodeBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_Node_configuration { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node> {
			            __safeDI_nodeBuilder(__safeDI_Node_configuration: safeDIOverrides.nodeBuilder)
			        }
			        #sourceLocation(file: "\(dependentModuleFixtures["Node.swift"])", line: 4)
			        let childBuilder: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        return Node(childBuilder: childBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsMockedTypesRenameUnderItsOwnBindingName_whenRenameOnLoopSharesLabelWithPromotedDependency() async throws {
		// `Screen` renames `nodeBuilder` as `middleBuilder`, which `Node` renames again, so the rename is on the loop of
		// `nodeBuilder`. `Other` requires `middleBuilder: Tool`, which the mock promotes beside the rename, so the mock binds
		// the rename under a name of its own, and `__safeDI_nodeBuilder` wraps it again under that name.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Screen", attributes: "(generateMock: true)", "@Received(fulfilledByDependencyNamed: \"nodeBuilder\", ofType: Instantiator<Node>.self) let middleBuilder: Instantiator<Node>", "@Received let other: Other"),
			Self.type("Node", "@Received(fulfilledByDependencyNamed: \"middleBuilder\", ofType: Instantiator<Node>.self) let childBuilder: Instantiator<Node>"),
			Self.type("Other", "@Received let middleBuilder: Tool"),
			Self.type("Tool"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Screen+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Screen {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            nodeBuilder: ((Instantiator<Node>) -> Node)? = nil,
			            middleBuilder: (() -> Tool)? = nil,
			            other: ((Tool) -> Other)? = nil
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                nodeBuilder: nodeBuilder,
			                middleBuilder: middleBuilder,
			                other: other
			            )
			        }

			        var nodeBuilder: ((Instantiator<Node>) -> Node)? { __safeDI_storage.nodeBuilder }
			        var middleBuilder: (() -> Tool)? { __safeDI_storage.middleBuilder }
			        var other: ((Tool) -> Other)? { __safeDI_storage.other }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                nodeBuilder: ((Instantiator<Node>) -> Node)?,
			                middleBuilder: (() -> Tool)?,
			                other: ((Tool) -> Other)?
			            ) {
			                self.nodeBuilder = nodeBuilder
			                self.middleBuilder = middleBuilder
			                self.other = other
			            }

			            let nodeBuilder: ((Instantiator<Node>) -> Node)?
			            let middleBuilder: (() -> Tool)?
			            let other: ((Tool) -> Other)?
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Screen {
			        func __safeDI_nodeBuilder() -> Node {
			            let middleBuilder_Instantiator__Node: Instantiator<Node> = Instantiator<Node>(__safeDI_nodeBuilder)
			            #sourceLocation(file: "\(output.fixtures["Node.swift"])", line: 7)
			            let childBuilder: Instantiator<Node> = middleBuilder_Instantiator__Node
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.nodeBuilder { safeDIBuilder(childBuilder) } else { Node(childBuilder: childBuilder) }
			        }
			        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
			        #sourceLocation(file: "\(output.fixtures["Screen.swift"])", line: 8)
			        let middleBuilder_Instantiator__Node: Instantiator<Node> = nodeBuilder
			        #sourceLocation()
			        let middleBuilder = if let safeDIBuilder = safeDIOverrides.middleBuilder { safeDIBuilder() } else { Tool() }
			        let other = if let safeDIBuilder = safeDIOverrides.other { safeDIBuilder(middleBuilder) } else { Other(middleBuilder: middleBuilder) }
			        return Screen(middleBuilder: middleBuilder_Instantiator__Node, other: other)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – Receives through a cycle-closing scope

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsNothingInsideClosedOnBuildersTree_whenOnlyCycleClosingCallReceivesBuilderThroughRequiredRename() async throws {
		// The `B` inside `A` calls the enclosing `__safeDI_bBuilder`, which binds its own `aBuilder`: nothing in `A`'s function reads one.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration
			            ) {
			                self.bBuilder = bBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder(__safeDI_B_configuration: B.SafeDIMockConfiguration) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration(), __safeDI_B_configuration_nearest: __safeDI_B_configuration)
			            }
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(aBuilder, aBuilderAlias) } else { B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration, __safeDI_B_configuration_nearest: B.SafeDIMockConfiguration?) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: __safeDI_B_configuration_nearest ?? B.SafeDIMockConfiguration())
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsNothingInsideClosedOnBuildersTree_whenOnlyCycleClosingCallReceivesBuilderThroughOnlyIfAvailableRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration
			            ) {
			                self.bBuilder = bBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder(__safeDI_B_configuration: B.SafeDIMockConfiguration) -> B {
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration(), __safeDI_B_configuration_nearest: __safeDI_B_configuration)
			            }
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A>? = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(aBuilder, aBuilderAlias) } else { B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        func __safeDI_aBuilder(__safeDI_A_configuration: A.SafeDIMockConfiguration, __safeDI_B_configuration_nearest: B.SafeDIMockConfiguration?) -> A {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: __safeDI_B_configuration_nearest ?? B.SafeDIMockConfiguration())
			            }
			            return if let safeDIBuilder = __safeDI_A_configuration.safeDIBuilder { safeDIBuilder(bBuilder) } else { A(bBuilder: bBuilder) }
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsBuilderInsideItsOwnFunction_whenItsTypeReceivesItBesideCycleClosingCallThatReceivesItThroughRename() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self, onlyIfAvailable: true) let aBuilderAlias: Instantiator<A>?"),
			Self.type("A", "@Instantiated let bBuilder: Instantiator<B>", "@Received let aBuilder: Instantiator<A>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration
			            ) {
			                self.bBuilder = bBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder() -> B {
			            func __safeDI_aBuilder() -> A {
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return A(bBuilder: bBuilder, aBuilder: aBuilder)
			            }
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder)
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 9)
			            let aBuilderAlias: Instantiator<A>? = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = safeDIOverrides.bBuilder.safeDIBuilder { safeDIBuilder(aBuilder, aBuilderAlias) } else { B(aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_buildsValueBeforeBuilderThatReceivesIt_whenValuesTreeCallsEnclosingFunctionOfTypeThatRenamesTheBuilder() async throws {
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true)", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("Consumer", attributes: "(generateMock: true)", "@Received let bBuilder: Instantiator<B>"),
			Self.type("B", "@Instantiated let c: C", "@Instantiated let aBuilder: Instantiator<A>", "@Received(fulfilledByDependencyNamed: \"aBuilder\", ofType: Instantiator<A>.self) let aBuilderAlias: Instantiator<A>"),
			Self.type("C", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let c: C"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Consumer+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension Consumer {
			    /// Overrides for the mock dependency tree.
			    struct SafeDIOverrides {
			        init(
			            bBuilder: B.SafeDIMockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                bBuilder: bBuilder
			            )
			        }

			        var bBuilder: B.SafeDIMockConfiguration { __safeDI_storage.bBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                bBuilder: B.SafeDIMockConfiguration
			            ) {
			                self.bBuilder = bBuilder
			            }

			            let bBuilder: B.SafeDIMockConfiguration
			        }
			    }

			    static func mock(
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> Consumer {
			        func __safeDI_bBuilder(__safeDI_B_configuration: B.SafeDIMockConfiguration) -> B {
			            let c: C = __safeDI_c(__safeDI_C_configuration: __safeDI_B_configuration.c, __safeDI_B_configuration_nearest: __safeDI_B_configuration)
			            let aBuilder = Instantiator<A> {
			                __safeDI_aBuilder(c: c, __safeDI_A_configuration: __safeDI_B_configuration.aBuilder)
			            }
			            #sourceLocation(file: "\(output.fixtures["B.swift"])", line: 11)
			            let aBuilderAlias: Instantiator<A> = aBuilder
			            #sourceLocation()
			            return if let safeDIBuilder = __safeDI_B_configuration.safeDIBuilder { safeDIBuilder(c, aBuilder, aBuilderAlias) } else { B(c: c, aBuilder: aBuilder, aBuilderAlias: aBuilderAlias) }
			        }
			        func __safeDI_c(__safeDI_C_configuration: C.SafeDIMockConfiguration, __safeDI_B_configuration_nearest: B.SafeDIMockConfiguration?) -> C {
			            let bBuilder = Instantiator<B> {
			                __safeDI_bBuilder(__safeDI_B_configuration: __safeDI_B_configuration_nearest ?? B.SafeDIMockConfiguration())
			            }
			            return if let safeDIBuilder = __safeDI_C_configuration.safeDIBuilder { safeDIBuilder(bBuilder) } else { C(bBuilder: bBuilder) }
			        }
			        func __safeDI_aBuilder(c: C, __safeDI_A_configuration: ((C) -> A)?) -> A {
			            if let safeDIBuilder = __safeDI_A_configuration { safeDIBuilder(c) } else { A(c: c) }
			        }
			        let bBuilder = Instantiator<B> {
			            __safeDI_bBuilder(__safeDI_B_configuration: safeDIOverrides.bBuilder)
			        }
			        return Consumer(bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_wrapsLaterMemberAgainInReceivedFunction_whenMemberTakesLaterMemberAsCycleParameter() async throws {
		// `aBuilder`’s function takes `bBuilder`, which `C` builds again beneath it, as a cycle parameter, and `bBuilder` is
		// built after it on the root’s loop: `aBuilder`’s `_received` function wraps `bBuilder` again and passes it.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
			Self.type("A", "@Received let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>"),
			Self.type("C", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"Root+SafeDIMock.swift": generatedFileHeader + """
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
			        func __safeDI_aBuilder(bBuilder: Instantiator<B>) -> A {
			            func __safeDI_cBuilder() -> C {
			                func __safeDI_aBuilder_received() -> A {
			                    let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                    return __safeDI_aBuilder(bBuilder: bBuilder)
			                }
			                func __safeDI_bBuilder() -> B {
			                    let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                    return if let safeDIBuilder = safeDIOverrides.aBuilder.cBuilder.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			                }
			                let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			                let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			                return if let safeDIBuilder = safeDIOverrides.aBuilder.cBuilder.safeDIBuilder { safeDIBuilder(aBuilder, bBuilder) } else { C(aBuilder: aBuilder, bBuilder: bBuilder) }
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = safeDIOverrides.aBuilder.safeDIBuilder { safeDIBuilder(bBuilder, cBuilder) } else { A(bBuilder: bBuilder, cBuilder: cBuilder) }
			        }
			        func __safeDI_aBuilder_received() -> A {
			            let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			            return __safeDI_aBuilder(bBuilder: bBuilder)
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder) } else { B(aBuilder: aBuilder) }
			        }
			        let aBuilder = Instantiator<A>(__safeDI_aBuilder_received)
			        let bBuilder = Instantiator<B>(__safeDI_bBuilder)
			        return Root(aBuilder: aBuilder, bBuilder: bBuilder)
			    }
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	// MARK: Tests – A call of another module's public mock on a loop

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_rebindsCallsWrapperInsideItsFunction_whenPublicMockCallIsMemberOfLoopOfBuilders() async throws {
		// `Node`’s tree receives `nodeBuilder`, so `Screen`’s mock promotes it, a loop of one builder whose function calls
		// `Node`’s public mock: the function first wraps itself again, binds the `apiBuilder` the call passes up, and returns
		// the call.
		let output = try await executeSafeDIToolMultiModuleTest(modules: [
			ModuleFixture(name: "Feature", packageName: "Feature", swiftFileContent: [
				"""
				import SafeDI

				public protocol Api {}

				@Instantiable(generateMock: .public)
				public final class Node: Instantiable {
				    init(api: any Api, step: Step) { self.api = api; self.step = step }
				    @Instantiated let api: any Api
				    @Instantiated let step: Step
				}

				@Instantiable
				public final class Step: Instantiable {
				    public init(nodeBuilder: Instantiator<Node>) { self.nodeBuilder = nodeBuilder }
				    @Received let nodeBuilder: Instantiator<Node>
				}
				""",
			]),
			ModuleFixture(name: "App", packageName: "App", swiftFileContent: [
				"""
				import SafeDI
				import Feature

				@Instantiable(generateMock: true)
				public final class Screen: Instantiable {
				    public init(node: Node) { self.node = node }
				    @Instantiated let node: Node
				}
				""",
			], dependencies: ["Feature"]),
		], integration: .moduleInfo, filesToDelete: &filesToDelete)

		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif

		#if DEBUG
		extension Screen {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            nodeBuilder: Node.SafeDIOverrides = .init(),
		            node: Node.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                nodeBuilder: nodeBuilder,
		                node: node
		            )
		        }

		        var nodeBuilder: Node.SafeDIOverrides { __safeDI_storage.nodeBuilder }
		        var node: Node.SafeDIOverrides { __safeDI_storage.node }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                nodeBuilder: Node.SafeDIOverrides,
		                node: Node.SafeDIOverrides
		            ) {
		                self.nodeBuilder = nodeBuilder
		                self.node = node
		            }

		            let nodeBuilder: Node.SafeDIOverrides
		            let node: Node.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: @escaping () -> any Api,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Screen {
		        let __safeDI_apiBuilder = apiBuilder
		        _ = Node.__safeDI_Node_mock_836E5FB7AC49A953.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_nodeBuilder() -> Node {
		            let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return Node.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), nodeBuilder: nodeBuilder, safeDIOverrides: safeDIOverrides.nodeBuilder)
		        }
		        let nodeBuilder = Instantiator<Node>(__safeDI_nodeBuilder)
		        _ = Node.__safeDI_Node_mock_836E5FB7AC49A953.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		        func __safeDI_node() -> Node {
		            let apiBuilder: () -> any Api = __safeDI_apiBuilder
		            return Node.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder), nodeBuilder: nodeBuilder, safeDIOverrides: safeDIOverrides.node)
		        }
		        let node: Node = __safeDI_node()
		        return Screen(node: node)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A root that declares an erased builder of each of `screenCount` screens, each of which receives the builders of the
	/// screens one, two and five after it, round the ring.
	private static func screensOpeningOneAnother(screenCount: Int) -> [String] {
		var files = ["public protocol Screen {}"]
		for index in 0..<screenCount {
			files.append(type("S\(index)", openedScreenIndices(from: index, screenCount: screenCount).map { "@Received let s\($0)Builder: ErasedInstantiator<(), any Screen>" }, conformances: ", Screen"))
		}
		files.append(type("Root", attributes: "(isRoot: true, generateMock: true)", (0..<screenCount).map { "@Instantiated(fulfilledByType: \"S\($0)\") let s\($0)Builder: ErasedInstantiator<(), any Screen>" }))
		return files
	}

	/// The screens the screen at `index` opens, among `screenCount` (see `screensOpeningOneAnother(screenCount:)`).
	private static func openedScreenIndices(from index: Int, screenCount: Int) -> [Int] {
		[1, 2, 5].map { (index + $0) % screenCount }
	}

	/// `Step` declares its own `session` and closes a cycle on `screenBuilder`, so `__safeDI_screenBuilder` takes
	/// `session`, and `Detail` receives `screenBuilder` inside its tree.
	private static let loopMemberTakingCycleParameterFixture = [
		type("Session"),
		type("Screen", "@Received let session: Session", "@Instantiated let stepBuilder: Instantiator<Step>", "@Instantiated let detail: Detail"),
		type("Detail", "@Received let screenBuilder: Instantiator<Screen>"),
		type("Step", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
		type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let session: Session", "@Instantiated let screenBuilder: Instantiator<Screen>"),
	]

	/// `T4` receives `t4Builder`, which builds it, only if available, and `t2Builder` only if available, which waits on
	/// `t3`, which requires `t4Builder`: that receive is left `nil`, and `t4Builder` still receives itself.
	private static let typeReceivingItsBuilderOnlyIfAvailableBesideReceiveLeftNilThroughValueFixture = [
		type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
		type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
		type("T3", "@Received let t4Builder: Instantiator<T4>"),
		type("T4", "@Received(onlyIfAvailable: true) let t4Builder: Instantiator<T4>?", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
	]

	/// `T4` receives `t4Builder`, which builds it, through a rename, and `t2Builder` only if available, which waits on `t3`,
	/// which waits on `t4Builder`: that receive is left `nil`, and `t4Builder` still receives itself.
	private static let builderRenamedByItsTypeBesideBuilderWaitingOnItThroughValueFixture = [
		type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let t2Builder: Instantiator<T2>", "@Instantiated let t4Builder: Instantiator<T4>", "@Instantiated let t3: T3"),
		type("T2", "@Received(onlyIfAvailable: true) let t3: T3?"),
		type("T3", "@Instantiated let t4: T4"),
		type("T4", "@Received(fulfilledByDependencyNamed: \"t4Builder\", ofType: Instantiator<T4>.self) let t4BuilderAlias: Instantiator<T4>", "@Received(onlyIfAvailable: true) let t2Builder: Instantiator<T2>?"),
	]

	/// `aBuilder` and `bBuilder` receive each other, and `A` receives `cBuilder` only if available; `cBuilder` waits on `v`,
	/// which waits on `aBuilder`: that receive is left `nil`, and the two builders are still a loop.
	private static let twoBuilderLoopBesideReceiveWaitingOnItThroughValueFixture = [
		type("Root", attributes: "(isRoot: true, generateMock: true)", "@Instantiated let aBuilder: Instantiator<A>", "@Instantiated let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>", "@Instantiated let v: V"),
		type("A", "@Received let bBuilder: Instantiator<B>", "@Received(onlyIfAvailable: true) let cBuilder: Instantiator<C>?"),
		type("B", "@Received let aBuilder: Instantiator<A>"),
		type("C", "@Received let v: V"),
		type("V", "@Received let aBuilder: Instantiator<A>"),
	]

	/// `fixture`'s files, named by their position.
	private static func fixtureFiles(_ fixture: [String]) -> [String: String] {
		var fixtureFiles = [String: String]()
		for (index, file) in fixture.enumerated() {
			fixtureFiles["File\(index).swift"] = file
		}
		return fixtureFiles
	}

	/// Expects `Root.mock()` to build the values `Root()` builds, with the code `output` generated for `fixture`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectMockBuildsWhatProductionBuilds(fixture: [String], output: TestOutput, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		let fixtureFiles = Self.fixtureFiles(fixture)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(fixtureFiles: fixtureFiles, generatedFiles: #require(output.generatedFiles)),
			knownRight: DifferentialValuePath(
				fixtureFiles: fixtureFiles,
				generatedFiles: output.dependencyTreeFiles.merging(["Root+ProductionMock.swift": "extension Root {\n    static func mock() -> Root {\n        Root()\n    }\n}\n"]) { first, _ in first },
			),
			probes: [DifferentialValueProbe("Root.mock()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	@Test
	mutating func mock_rebindsInstantiatedMemberBesidePromotedMember_whenPublicMocksLoopHoldsBoth() async throws {
		// `B`, built at the mock’s root, rebinds two members of its loop: `aBuilder`, which the public mock promotes and its caller
		// may pass, and `cBuilder`, which `A` instantiates and no caller passes, so only `aBuilder` reads the parameter.
		let output = try await executeSafeDIToolTest(swiftFileContent: [
			Self.type("A", attributes: "(generateMock: .public)", "@Received let bBuilder: Instantiator<B>", "@Instantiated let cBuilder: Instantiator<C>"),
			Self.type("B", "@Received let aBuilder: Instantiator<A>", "@Received let cBuilder: Instantiator<C>"),
			Self.type("C", "@Received let bBuilder: Instantiator<B>"),
		], buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.mockFiles == [
			"A+SafeDIMock.swift": generatedFileHeader + """
			#if DEBUG
			extension A {
			    /// Overrides for the mock dependency tree.
			    nonisolated public struct SafeDIOverrides {
			        public init(
			            cBuilder: ((Instantiator<B>) -> C)? = nil,
			            bBuilder: ((Instantiator<A>, Instantiator<C>) -> B)? = nil,
			            aBuilder: __safeDI_A_MockConfiguration = .init()
			        ) {
			            __safeDI_storage = __safeDI_Storage(
			                cBuilder: cBuilder,
			                bBuilder: bBuilder,
			                aBuilder: aBuilder
			            )
			        }

			        public var cBuilder: ((Instantiator<B>) -> C)? { __safeDI_storage.cBuilder }
			        public var bBuilder: ((Instantiator<A>, Instantiator<C>) -> B)? { __safeDI_storage.bBuilder }
			        public var aBuilder: __safeDI_A_MockConfiguration { __safeDI_storage.aBuilder }

			        private let __safeDI_storage: __safeDI_Storage

			        private final class __safeDI_Storage {
			            init(
			                cBuilder: ((Instantiator<B>) -> C)?,
			                bBuilder: ((Instantiator<A>, Instantiator<C>) -> B)?,
			                aBuilder: __safeDI_A_MockConfiguration
			            ) {
			                self.cBuilder = cBuilder
			                self.bBuilder = bBuilder
			                self.aBuilder = aBuilder
			            }

			            let cBuilder: ((Instantiator<B>) -> C)?
			            let bBuilder: ((Instantiator<A>, Instantiator<C>) -> B)?
			            let aBuilder: __safeDI_A_MockConfiguration
			        }
			    }

			    public static func mock(
			        aBuilder: Instantiator<A>? = nil,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        A.__safeDI_mock(aBuilder: aBuilder, bBuilder: bBuilder, safeDIOverrides: safeDIOverrides)
			    }

			    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
			    public static func __safeDI_mock(
			        aBuilder: Instantiator<A>? = nil,
			        bBuilder: Instantiator<B>? = nil,
			        safeDIOverrides: SafeDIOverrides = .init()
			    ) -> A {
			        func __safeDI_cBuilder() -> C {
			            let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			            return if let safeDIBuilder = safeDIOverrides.cBuilder { safeDIBuilder(bBuilder) } else { C(bBuilder: bBuilder) }
			        }
			        func __safeDI_bBuilder() -> B {
			            let aBuilder = if let aBuilder { aBuilder } else { Instantiator<A>(__safeDI_aBuilder) }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return if let safeDIBuilder = safeDIOverrides.bBuilder { safeDIBuilder(aBuilder, cBuilder) } else { B(aBuilder: aBuilder, cBuilder: cBuilder) }
			        }
			        func __safeDI_aBuilder() -> A {
			            let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			            func __safeDI_cBuilder() -> C {
			                if let safeDIBuilder = safeDIOverrides.aBuilder.cBuilder { safeDIBuilder(bBuilder) } else { C(bBuilder: bBuilder) }
			            }
			            let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			            return A.__safeDI_init(bBuilder: bBuilder, cBuilder: cBuilder, safeDIBuilder: safeDIOverrides.aBuilder.safeDIBuilder)
			        }
			        let cBuilder = Instantiator<C>(__safeDI_cBuilder)
			        let bBuilder = if let bBuilder { bBuilder } else { Instantiator<B>(__safeDI_bBuilder) }
			        return A(bBuilder: bBuilder, cBuilder: cBuilder)
			    }
			}

			extension A {
			    public enum __safeDI_A_mock_DC87377F9DD950EC {}
			}
			#endif
			""",
		], "Unexpected output \(output.mockFiles)")
	}

	private static func type(_ name: String, attributes: String = "", _ declarations: String..., conformances: String = "") -> String {
		type(name, attributes: attributes, declarations, conformances: conformances)
	}

	private static func type(_ name: String, attributes: String = "", _ declarations: [String], conformances: String = "") -> String {
		let type = seamFixtureType(named: name, isFinalClass: true, declarations: declarations, conformances: conformances)
		guard !attributes.isEmpty else { return type }
		return "@Instantiable\(attributes)" + type.dropFirst("@Instantiable".count)
	}
}
