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

/// A public mock labels a builder as a seam does: by its filling type, and its returned type where the two differ, from
/// the first place on.
struct SafeDIToolPublicMockBuilderLabelTests: ~Copyable {
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
	mutating func generate_labelsMocksBuilderByFillingAndReturnedType_whenTheMockedTypesOwnPlaceIsFilledByAnotherType() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
					"""
					public protocol Api {}

					@Instantiable(generateMock: .public)
					public struct F: Instantiable {
					    public init(a: ErasedInstantiator<Int, any Api>) {
					        self.a = a
					    }

					    @Instantiated(fulfilledByType: "Impl") let a: ErasedInstantiator<Int, any Api>
					}
					""",
				]),
				ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
					"""
					import Feature
					import SafeDI

					struct Impl: Api {
					    init(id: Int) {}
					}

					func handWrittenMock() -> F {
					    F.mock(impl_ApiBuilder: { id in Impl(id: id) })
					}
					""",
				], dependencies: ["Feature"]),
			],
			integration: .moduleInfo,
			compileVerification: .returningOutcomeOnly,
			filesToDelete: &filesToDelete,
		)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if DEBUG
		extension F {
		    nonisolated public enum SafeDIMockScope_Impl_Api {
		        nonisolated public struct a_Values {}

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public struct __safeDI_Builder<__safeDI_Built> {
		            public let a: (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder

		            public init(a: @escaping (a_Values) -> ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.a = a
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping ErasedInstantiator<Int, __safeDI_Built>.Builder) {
		                self.init(a: { _ in __safeDI_builder })
		            }
		        }
		    }

		    public static func mock(
		        impl_ApiBuilder: @escaping ErasedInstantiator<Int, any Api>.Builder
		    ) -> F {
		        F.__safeDI_mock(impl_ApiBuilder: .init(__safeDI_noScope: impl_ApiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        impl_ApiBuilder __safeDI_impl_ApiBuilder: F.SafeDIMockScope_Impl_Api.__safeDI_Builder<any Api>
		    ) -> F {
		        let a = ErasedInstantiator<Int, any Api>(__safeDI_impl_ApiBuilder.a(SafeDIMockScope_Impl_Api.a_Values()))
		        return F(a: a)
		    }
		}

		extension F {
		    public enum __safeDI_F_mock_C767B7BC2835A9DA {}
		}
		#endif
		"""])
		guard compileVerificationIsEnabled else { return }
		let compilation = try #require(output.compilation)
		#expect(compilation.modules.map(\.exitCode) == output.moduleNames.map { _ in 0 })
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
