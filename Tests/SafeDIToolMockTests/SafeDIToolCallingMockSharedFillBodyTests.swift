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

/// A calling mock's fills of the holes of other modules' public mocks it calls share one body per tree, as a root's fills
/// of its seam calls do: `mock()` declares each body once, before its tree (`MockLowering.Walk.declareFillBodies`).
///
/// `Feature` declares `F0` and `F1`, seams with public mocks that receive `service` and instantiate `hidden`, a type no other
/// module can construct, so a mock in `App` calls their mocks, and `api: any Api`, a hole `App` fills with `LiveApi`.
struct SafeDIToolCallingMockSharedFillBodyTests: ~Copyable {
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
	mutating func mock_declaresFillBodyOnce_whenTwoPublicMockCallsFillHoleWithSameTree() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(modules: Self.modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		expectGeneratedFiles(output.modules["App"]?.generatedFiles, ["App.swift": generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif

		extension Root {
		    public convenience init() {
		        func __safeDI_apiBuilder_F0_api(_ scope_service: Service, _ scope_hidden: Hidden0) -> any Api {
		            return __safeDI_fillBody_4090EA3CC5C36131(service: scope_service)
		        }
		        func __safeDI_fillBody_4090EA3CC5C36131(service: Service) -> any Api {
		            func __safeDI_api() -> LiveApi {
		                let c = C(service: service)
		                return LiveApi(service: service, c: c)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        func __safeDI_apiBuilder_F0() -> F0.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service, scope_hidden in __safeDI_apiBuilder_F0_api(scope_service, scope_hidden) })
		        }
		        func __safeDI_apiBuilder_F1_api(_ scope_service: Service, _ scope_hidden: Hidden1) -> any Api {
		            return __safeDI_fillBody_4090EA3CC5C36131(service: scope_service)
		        }
		        func __safeDI_apiBuilder_F1() -> F1.__safeDI_ApiCarrier<any Api> {
		            .init(api: { scope_service, scope_hidden in __safeDI_apiBuilder_F1_api(scope_service, scope_hidden) })
		        }
		        let service = Service()
		        func __safeDI_f0() -> F0 {
		            _ = F0.__safeDI_F0_B8F18DF39AAEFE50.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F0())
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            _ = F1.__safeDI_F1_0BC50899BF9DB3B0.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F1(__safeDI_service: service, __safeDI_apiBuilder: __safeDI_apiBuilder_F1())
		        }
		        let f1: F1 = __safeDI_f1()
		        self.init(service: service, f0: f0, f1: f1)
		    }
		}

		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            service: (() -> Service)? = nil,
		            f0: F0.SafeDIOverrides = .init(),
		            f1: F1.SafeDIOverrides = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                service: service,
		                f0: f0,
		                f1: f1
		            )
		        }

		        var service: (() -> Service)? { __safeDI_storage.service }
		        var f0: F0.SafeDIOverrides { __safeDI_storage.f0 }
		        var f1: F1.SafeDIOverrides { __safeDI_storage.f1 }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                service: (() -> Service)?,
		                f0: F0.SafeDIOverrides,
		                f1: F1.SafeDIOverrides
		            ) {
		                self.service = service
		                self.f0 = f0
		                self.f1 = f1
		            }

		            let service: (() -> Service)?
		            let f0: F0.SafeDIOverrides
		            let f1: F1.SafeDIOverrides
		        }
		    }

		    static func mock(
		        apiBuilder: (() -> any Api)? = nil,
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_fillBody_4090EA3CC5C36131(service: Service) -> any Api {
		            func __safeDI_api() -> LiveApi {
		                let c = C(service: service)
		                return LiveApi(service: service, c: c)
		            }
		            let api: any Api = __safeDI_api()
		            return api
		        }
		        let service = if let safeDIBuilder = safeDIOverrides.service { safeDIBuilder() } else { Service() }
		        func __safeDI_f0() -> F0 {
		            func __safeDI_apiBuilder_F0_api(_ scope: F0.SafeDIMockScope_Api.api_Values) -> any Api {
		                return __safeDI_fillBody_4090EA3CC5C36131(service: scope.service)
		            }
		            func __safeDI_apiBuilder_F0() -> F0.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in __safeDI_apiBuilder_F0_api(scope) })
		            }
		            _ = F0.__safeDI_F0_mock_77EDE4998C4FD7E9.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F0.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F0(), service: service, safeDIOverrides: safeDIOverrides.f0)
		        }
		        let f0: F0 = __safeDI_f0()
		        func __safeDI_f1() -> F1 {
		            func __safeDI_apiBuilder_F1_api(_ scope: F1.SafeDIMockScope_Api.api_Values) -> any Api {
		                return __safeDI_fillBody_4090EA3CC5C36131(service: scope.service)
		            }
		            func __safeDI_apiBuilder_F1() -> F1.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
		                .init(api: { scope in __safeDI_apiBuilder_F1_api(scope) })
		            }
		            _ = F1.__safeDI_F1_mock_3BD7C2857126556A.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return F1.__safeDI_mock(apiBuilder: apiBuilder.map { .init(__safeDI_noScope: $0) } ?? __safeDI_apiBuilder_F1(), service: service, safeDIOverrides: safeDIOverrides.f1)
		        }
		        let f1: F1 = __safeDI_f1()
		        return Root(service: service, f0: f0, f1: f1)
		    }
		}
		#endif
		"""])
	}

	// MARK: Private

	private var filesToDelete: [URL]

	private static var modules: [ModuleFixture] {
		let seamDeclarations = { (index: Int) in
			"""
			@Instantiable(generateDependencyTree: true, generateMock: .public) public final class F\(index): Instantiable {
				public init(service: Service, hidden: Hidden\(index), api: any Api) { self.service = service; self.hidden = hidden; self.api = api }
				@Received public let service: Service
				@Instantiated public let hidden: Hidden\(index)
				@Instantiated public let api: any Api
			}
			"""
		}
		return [
			ModuleFixture(name: "Feature", packageName: "Shop", swiftFileContent: [
				"public protocol Api {}\n\n@Instantiable public final class Service: Instantiable { public init() {} }",
				"@Instantiable public final class Hidden0: Instantiable { init() {} }",
				"@Instantiable public final class Hidden1: Instantiable { init() {} }",
				seamDeclarations(0),
				seamDeclarations(1),
			]),
			ModuleFixture(name: "App", packageName: "Other", swiftFileContent: [
				"""
				@Instantiable(fulfillingAdditionalTypes: [Api.self]) public final class LiveApi: Instantiable, Api {
					public init(service: Service, c: C) { self.service = service; self.c = c }
					@Received let service: Service
					@Instantiated let c: C
				}
				""",
				"""
				@Instantiable public final class C: Instantiable {
					public init(service: Service) { self.service = service }
					@Received let service: Service
				}
				""",
				"""
				@Instantiable(isRoot: true, generateMock: true) public final class Root: Instantiable {
					public init(service: Service, f0: F0, f1: F1) { self.service = service; self.f0 = f0; self.f1 = f1 }
					@Instantiated let service: Service
					@Instantiated let f0: F0
					@Instantiated let f1: F1
				}
				""",
			].map { "import Feature\n\n" + $0 }, dependencies: ["Feature"]),
		]
	}

	private func expectGeneratedFiles(_ generatedFiles: [String: String]?, _ expected: [String: String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(generatedFiles == expected, sourceLocation: sourceLocation)
		if let generatedFiles, generatedFiles != expected {
			Issue.record(Comment(rawValue: generatedFiles.sorted { $0.key < $1.key }.map { "=== \($0.key)\n\($0.value)" }.joined(separator: "\n")), sourceLocation: sourceLocation)
		}
	}
}
