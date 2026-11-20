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

/// A public mock's builder struct follows a seam's rule: two or more members make it a `final class` (contract rule 7).
struct SafeDIToolPublicMockClassBuilderTests: ~Copyable {
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
	mutating func generate_declaresFinalClassBuilder_whenPublicMocksEnumHasTwoCases() async throws {
		let modules = [
			ModuleFixture(name: "Feed", packageName: "Feed", swiftFileContent: [
				"public protocol Api {}",
				"""
				@Instantiable(generateMock: .public)
				public final class Page: Instantiable {
				    init(primaryApi: any Api, secondaryApi: any Api) {
				        self.primaryApi = primaryApi
				        self.secondaryApi = secondaryApi
				    }

				    @Instantiated public let primaryApi: any Api
				    @Instantiated public let secondaryApi: any Api
				}
				""",
			]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feed"]?.generatedFiles == ["Feed.swift": generatedFileHeader + """
		#if DEBUG
		extension Page {
		    nonisolated public enum SafeDIMockScope_Api {
		        nonisolated public struct __safeDI_Values: Sendable {}

		        nonisolated public struct secondaryApi_Values {
		            public let primaryApi: any Api
		        }

		        /// Only code SafeDI generates reads this type, and its shape can change in any release of SafeDI.
		        nonisolated public final class __safeDI_Builder<__safeDI_Built> {
		            public let primaryApi: (__safeDI_Values) -> __safeDI_Built
		            public let secondaryApi: (secondaryApi_Values) -> __safeDI_Built

		            public init(primaryApi: @escaping (__safeDI_Values) -> __safeDI_Built, secondaryApi: @escaping (secondaryApi_Values) -> __safeDI_Built) {
		                self.primaryApi = primaryApi
		                self.secondaryApi = secondaryApi
		            }

		            public init(__safeDI_noScope __safeDI_builder: @escaping () -> __safeDI_Built) {
		                self.primaryApi = { _ in __safeDI_builder() }
		                self.secondaryApi = { _ in __safeDI_builder() }
		            }
		        }
		    }

		    public static func mock(
		        apiBuilder: @escaping () -> any Api
		    ) -> Page {
		        Page.__safeDI_mock(apiBuilder: .init(__safeDI_noScope: apiBuilder))
		    }

		    /// Only code SafeDI generates calls this function, and its shape can change in any release of SafeDI.
		    public static func __safeDI_mock(
		        apiBuilder __safeDI_apiBuilder: Page.SafeDIMockScope_Api.__safeDI_Builder<any Api>
		    ) -> Page {
		        let primaryApi: any Api = __safeDI_apiBuilder.primaryApi(SafeDIMockScope_Api.__safeDI_Values())
		        let secondaryApi: any Api = __safeDI_apiBuilder.secondaryApi(SafeDIMockScope_Api.secondaryApi_Values(primaryApi: primaryApi))
		        return Page(primaryApi: primaryApi, secondaryApi: secondaryApi)
		    }
		}

		extension Page {
		    public enum __safeDI_Page_mock_18321BDEA2F52890 {}
		}
		#endif
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
