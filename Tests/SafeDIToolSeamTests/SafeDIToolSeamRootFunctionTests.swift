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

/// A call of another module’s seam declares the dispatchers of the seam’s tree. Each that captures nothing of the call is
/// declared once, at the top of the root that holds the call, before its first statement (`RootFunctionHoisting`). Every
/// cell compiles.
struct SafeDIToolSeamRootFunctionTests: ~Copyable {
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

	/// A root that calls `Home` twice declares `Home`’s dispatchers once, at its top, and each call’s builder function holds only the call.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEachDispatcherOnceAtTheRootsTop_whenTheRootCallsTheSeamTwice() async throws {
		let output = try await generate(root: """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(home: Home, homeBuilder: Instantiator<Home>) { self.home = home; self.homeBuilder = homeBuilder }
		    @Instantiated let home: Home
		    @Instantiated let homeBuilder: Instantiator<Home>
		}
		""")

		#expect(output == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        func __safeDI_homeBuilder() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let homeBuilder = Instantiator<Home>(__safeDI_homeBuilder)
		        self.init(home: home, homeBuilder: homeBuilder)
		    }
		}
		""")
	}

	/// `Outer`’s call reaches `Home`’s dispatchers, which the root also calls directly: each is declared once.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresTheInnerSeamsDispatchersOnce_whenTheRootCallsASeamThatCallsIt() async throws {
		let output = try await generate(root: """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(home: Home, outer: Outer) { self.home = home; self.outer = outer }
		    @Instantiated let home: Home
		    @Instantiated let outer: Outer
		}
		""")

		#expect(output == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		            .init(home: __safeDI_apiBuilder_Home())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Outer() -> Outer.__safeDI_ApiSendableCarrier<any Api> {
		            .init(home_Sendable: __safeDI_apiSendableBuilder_Home())
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_B4AA1274DF97DFE3.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(home: home, outer: outer)
		    }
		}
		""")
	}

	/// Each root of a file declares the dispatchers it reaches, since a root’s functions are local to its initializer.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresEachRootsOwnDispatchers_whenTwoRootsInOneFileCallTheSeam() async throws {
		let output = try await generate(root: """
		@Instantiable(isRoot: true)
		public struct FirstRoot: Instantiable {
		    public init(home: Home) { self.home = home }
		    @Instantiated let home: Home
		}

		@Instantiable(isRoot: true)
		public struct SecondRoot: Instantiable {
		    public init(outer: Outer) { self.outer = outer }
		    @Instantiated let outer: Outer
		}
		""")

		#expect(output == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension FirstRoot {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        self.init(home: home)
		    }
		}

		extension SecondRoot {
		    public init() {
		        func __safeDI_apiBuilder_Outer() -> Outer.__safeDI_ApiCarrier<any Api> {
		            .init(home: __safeDI_apiBuilder_Home())
		        }
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Outer() -> Outer.__safeDI_ApiSendableCarrier<any Api> {
		            .init(home_Sendable: __safeDI_apiSendableBuilder_Home())
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_B4AA1274DF97DFE3.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer(__safeDI_apiBuilder: __safeDI_apiBuilder_Outer(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}
		""")
	}

	/// A call inside a `@Sendable` builder function reaches dispatchers declared `@Sendable nonisolated` at the root’s top, since a `@Sendable` function calls no other local function.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresDispatchersSendable_whenTheCallIsInsideASendableFunction() async throws {
		let output = try await generate(root: """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(homeBuilder: SendableInstantiator<Home>) { self.homeBuilder = homeBuilder }
		    @Instantiated let homeBuilder: SendableInstantiator<Home>
		}
		""")

		#expect(output == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        @Sendable nonisolated func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        @Sendable nonisolated func __safeDI_homeBuilder() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let homeBuilder = SendableInstantiator<Home>(__safeDI_homeBuilder)
		        self.init(homeBuilder: homeBuilder)
		    }
		}
		""")
	}

	/// A dispatcher reached both inside and outside a `@Sendable` function is declared once, `@Sendable nonisolated`, which
	/// plain code calls as it called the plain one, with every dispatcher it calls.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresADispatcherOnceSendable_whenTheRootReachesItInsideAndOutsideASendableFunction() async throws {
		let output = try await generate(root: """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(home: Home, homeBuilder: SendableInstantiator<Home>) { self.home = home; self.homeBuilder = homeBuilder }
		    @Instantiated let home: Home
		    @Instantiated let homeBuilder: SendableInstantiator<Home>
		}
		""")

		#expect(output == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        @Sendable nonisolated func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        @Sendable nonisolated func __safeDI_homeBuilder() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let homeBuilder = SendableInstantiator<Home>(__safeDI_homeBuilder)
		        self.init(home: home, homeBuilder: homeBuilder)
		    }
		}
		""")
	}

	/// `Tab` builds `Home` in a function the root reaches twice.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_declaresDispatchersReachedOnlyInsideASharedFunction() async throws {
		let output = try await generate(root: """
		@Instantiable
		public struct Tab: Instantiable {
		    public init(home: Home) { self.home = home }
		    @Instantiated let home: Home
		}

		@Instantiable
		public struct Shelf: Instantiable {
		    public init(tabBuilder: Instantiator<Tab>) { self.tabBuilder = tabBuilder }
		    @Instantiated let tabBuilder: Instantiator<Tab>
		}

		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(tabBuilder: Instantiator<Tab>, shelf: Shelf) { self.tabBuilder = tabBuilder; self.shelf = shelf }
		    @Instantiated let tabBuilder: Instantiator<Tab>
		    @Instantiated let shelf: Shelf
		}
		""")

		#expect(output == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		            .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		        }
		        func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		            .init(
		                api: { scope_id, scope_model in
		                    let id = scope_id
		                    let model = scope_model
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                },
		                detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		            )
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		            .init(api: {
		                let api: any Api = Impl(id: id, model: model)
		                return api
		            })
		        }
		        @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		            .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		        }
		        @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		            .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		        }
		        func __safeDI_tabBuilder() -> Tab {
		            func __safeDI_home() -> Home {
		                _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		            }
		            let home: Home = __safeDI_home()
		            return Tab(home: home)
		        }
		        let tabBuilder = Instantiator<Tab>(__safeDI_tabBuilder)
		        func __safeDI_shelf() -> Shelf {
		            let tabBuilder = Instantiator<Tab>(__safeDI_tabBuilder)
		            return Shelf(tabBuilder: tabBuilder)
		        }
		        let shelf: Shelf = __safeDI_shelf()
		        self.init(tabBuilder: tabBuilder, shelf: shelf)
		    }
		}
		""")
	}

	/// `Tab` builds `Home`, whose fill reads the root's `token`, in a function the root reaches twice: both paths read one
	/// declaration of `token`, so the root declares the function once.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsCallWithFillsInOneFunction_whenFillReadsCallersValueBothPathsShare() async throws {
		let root = """
		@Instantiable
		public struct Tab: Instantiable {
		    public init(home: Home) { self.home = home }
		    @Instantiated let home: Home
		}

		@Instantiable
		public struct Shelf: Instantiable {
		    public init(tabBuilder: Instantiator<Tab>) { self.tabBuilder = tabBuilder }
		    @Instantiated let tabBuilder: Instantiator<Tab>
		}

		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(token: Token, tabBuilder: Instantiator<Tab>, shelf: Shelf) { self.token = token; self.tabBuilder = tabBuilder; self.shelf = shelf }
		    @Instantiated let token: Token
		    @Instantiated let tabBuilder: Instantiator<Tab>
		    @Instantiated let shelf: Shelf
		}
		"""
		let output = try await generateReadingToken(root: root)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        let token = Token()
		        func __safeDI_tabBuilder() -> Tab {
		            func __safeDI_home() -> Home {
		                _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                    .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		                }
		                func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		                    .init(
		                        api: { scope_id, scope_model in
		                            let id = scope_id
		                            let model = scope_model
		                            let api: any Api = Impl(id: id, model: model, token: token)
		                            return api
		                        },
		                        detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		                    )
		                }
		                @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		                    .init(api: {
		                        let api: any Api = Impl(id: id, model: model, token: token)
		                        return api
		                    })
		                }
		                @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		                    .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		                }
		                @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		                    .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		                }
		                return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		            }
		            let home: Home = __safeDI_home()
		            return Tab(home: home)
		        }
		        let tabBuilder = Instantiator<Tab>(__safeDI_tabBuilder)
		        func __safeDI_shelf() -> Shelf {
		            let tabBuilder = Instantiator<Tab>(__safeDI_tabBuilder)
		            return Shelf(tabBuilder: tabBuilder)
		        }
		        let shelf: Shelf = __safeDI_shelf()
		        self.init(token: token, tabBuilder: tabBuilder, shelf: shelf)
		    }
		}
		""")
		try await expectValuesEqualVisibleBuild(output, root: root)
	}

	/// `Tab` builds `Home`, whose fill reads `token`, on two paths, and `Shelf` declares `token` again above one of them:
	/// each path's fill reads its own `token`, so the function is not shared above `Shelf`'s declaration.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_buildsCallWithFillsOnEachPath_whenTypeOnOnePathDeclaresFillsValueAgain() async throws {
		let root = """
		@Instantiable
		public struct Tab: Instantiable {
		    public init(home: Home) { self.home = home }
		    @Instantiated let home: Home
		}

		@Instantiable
		public struct Shelf: Instantiable {
		    public init(token: Token, tabBuilder: Instantiator<Tab>) { self.token = token; self.tabBuilder = tabBuilder }
		    @Instantiated let token: Token
		    @Instantiated let tabBuilder: Instantiator<Tab>
		}

		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(token: Token, tabBuilder: Instantiator<Tab>, shelf: Shelf) { self.token = token; self.tabBuilder = tabBuilder; self.shelf = shelf }
		    @Instantiated let token: Token
		    @Instantiated let tabBuilder: Instantiator<Tab>
		    @Instantiated let shelf: Shelf
		}
		"""
		let output = try await generateReadingToken(root: root)

		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        let token = Token()
		        func __safeDI_tabBuilder(token: Token) -> Tab {
		            func __safeDI_home() -> Home {
		                _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                    .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		                }
		                func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		                    .init(
		                        api: { scope_id, scope_model in
		                            let id = scope_id
		                            let model = scope_model
		                            let api: any Api = Impl(id: id, model: model, token: token)
		                            return api
		                        },
		                        detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		                    )
		                }
		                @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		                    .init(api: {
		                        let api: any Api = Impl(id: id, model: model, token: token)
		                        return api
		                    })
		                }
		                @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		                    .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		                }
		                @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		                    .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		                }
		                return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		            }
		            let home: Home = __safeDI_home()
		            return Tab(home: home)
		        }
		        let tabBuilder = Instantiator<Tab> {
		            __safeDI_tabBuilder(token: token)
		        }
		        func __safeDI_shelf() -> Shelf {
		            let token = Token()
		            let tabBuilder = Instantiator<Tab> {
		                __safeDI_tabBuilder(token: token)
		            }
		            return Shelf(token: token, tabBuilder: tabBuilder)
		        }
		        let shelf: Shelf = __safeDI_shelf()
		        self.init(token: token, tabBuilder: tabBuilder, shelf: shelf)
		    }
		}
		""")
		try await expectValuesEqualVisibleBuild(output, root: root)
	}

	/// `Home`’s dispatcher of its `Detail` enum and the root dispatcher of `Home_Detail_Scope` take one name, each in the
	/// builder function of its own call. They are different functions, so neither is declared at the root’s top, where
	/// one would redeclare the other: each stays with its call, and every function that calls one stays with it.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsEachDispatcherWithItsCall_whenDispatchersOfTwoSeamsShareAName() async throws {
		let output = try await generate(
			root: """
			@Instantiable
			public struct Holder: Instantiable {
			    public init(id: Int, model: Model, other: Home_Detail_Scope) { self.id = id; self.model = model; self.other = other }
			    @Forwarded let id: Int
			    @Instantiated let model: Model
			    @Instantiated let other: Home_Detail_Scope
			}

			@Instantiable(isRoot: true)
			public struct Root: Instantiable {
			    public init(home: Home, holderBuilder: Instantiator<Holder>) { self.home = home; self.holderBuilder = holderBuilder }
			    @Instantiated let home: Home
			    @Instantiated let holderBuilder: Instantiator<Holder>
			}
			""",
			seamAddition: """
			@Instantiable(generateDependencyTree: true)
			public final class Home_Detail_Scope: Instantiable {
			    public init(id: Int, model: Model, api: any Api) { self.id = id; self.model = model; self.api = api }
			    @Received let id: Int
			    @Received let model: Model
			    @Instantiated let api: any Api
			}
			""",
		)

		#expect(output == generatedFileHeader + """
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Seam)
		import Seam
		#endif

		extension Root {
		    public init() {
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_4F2020B42ED8EAF2.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            func __safeDI_apiBuilder_Home() -> Home.__safeDI_ApiCarrier<any Api> {
		                .init(screenBuilder: __safeDI_apiBuilder_Home_Screen_Scope())
		            }
		            func __safeDI_apiBuilder_Home_Screen_Scope() -> Home.__safeDI_ApiCarrier_Screen<any Api> {
		                .init(
		                    api: { scope_id, scope_model in
		                        let id = scope_id
		                        let model = scope_model
		                        let api: any Api = Impl(id: id, model: model)
		                        return api
		                    },
		                    detailBuilder: { values_id, values_model, values_api in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) }
		                )
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Home_Detail_Scope(id: Int, model: Model) -> Home.__safeDI_ApiCarrier_Detail<any Api> {
		                .init(api: {
		                    let api: any Api = Impl(id: id, model: model)
		                    return api
		                })
		            }
		            @Sendable nonisolated func __safeDI_apiSendableBuilder_Home() -> Home.__safeDI_ApiSendableCarrier<any Api> {
		                .init(workBuilder: { __safeDI_apiBuilder_Home_Work_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_apiBuilder_Home_Work_Scope() -> Home.__safeDI_ApiCarrier_Work<any Api> {
		                .init(detailBuilder: { values_id, values_model in __safeDI_apiBuilder_Home_Detail_Scope(id: values_id, model: values_model) })
		            }
		            return Home(__safeDI_apiBuilder: __safeDI_apiBuilder_Home(), __safeDI_apiSendableBuilder: __safeDI_apiSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        func __safeDI_holderBuilder(id: Int) -> Holder {
		            let model = Model(id: id)
		            func __safeDI_other() -> Home_Detail_Scope {
		                _ = Home_Detail_Scope.__safeDI_Home_Detail_Scope_A27E9650D62B9DBD.self // If this line does not compile, compile the code SafeDI generates for module Seam into Seam: under Bazel, add Seam’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		                func __safeDI_apiBuilder_Home_Detail_Scope() -> Home_Detail_Scope.__safeDI_ApiCarrier<any Api> {
		                    .init(api: { scope_id, scope_model in
		                        let id = scope_id
		                        let model = scope_model
		                        let api: any Api = Impl(id: id, model: model)
		                        return api
		                    })
		                }
		                return Home_Detail_Scope(__safeDI_id: id, __safeDI_model: model, __safeDI_apiBuilder: __safeDI_apiBuilder_Home_Detail_Scope())
		            }
		            let other: Home_Detail_Scope = __safeDI_other()
		            return Holder(id: id, model: model, other: other)
		        }
		        let holderBuilder = Instantiator<Holder> {
		            __safeDI_holderBuilder(id: $0)
		        }
		        self.init(home: home, holderBuilder: holderBuilder)
		    }
		}
		""")
	}

	// MARK: Helpers

	/// The run of `Seam` and module `App`, whose root is `root` and whose fill of `Api` reads `token` besides the level's
	/// values.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generateReadingToken(root: String) async throws -> MultiModuleTestOutput {
		try await executeSafeDIToolMultiModuleTest(
			modules: Self.modulesReadingToken(root: root),
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
	}

	/// The modules of `generateReadingToken(root:)`.
	private static func modulesReadingToken(root: String) -> [ModuleFixture] {
		[
			ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": seam]),
			ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": "import Seam\nimport SafeDI\n\n" + implReadingToken + "\n\n" + root], dependencies: ["Seam"]),
		]
	}

	/// Expects `output`, the run of `modulesReadingToken(root:)`, to build `Root()`'s values as the build in which `Seam`
	/// declares the fill does.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValuesEqualVisibleBuild(_ output: MultiModuleTestOutput, root: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let modules = Self.modulesReadingToken(root: root)
		let visibleModules = [
			ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": Self.seam + "\n\n" + Self.implReadingToken]),
			ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": "import Seam\nimport SafeDI\n\n" + root], dependencies: ["Seam"]),
		]
		let visibleOutput = try await executeSafeDIToolMultiModuleTest(modules: visibleModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: output, modules: modules),
			knownRight: SafeDIToolSeamBuilderParameterTests.differentialValuePath(of: visibleOutput, modules: visibleModules),
			probes: [DifferentialValueProbe("Root()")],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}

	/// `Top` calls `Home` through `Both`, and the root calls `Home` itself. Each call's `Stager` and `Deep` dispatchers
	/// call the fills of their own call, which `Top`'s call names apart from the root's, so each call keeps its
	/// dispatchers: declared once at the root's top, the root's call's dispatchers would call `Top`'s fills in `Top`'s
	/// call, and `Top`'s fills would be declared and never called.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_keepsEachCallsDispatchersInItsCall_whenTwoCallsOfOneLevelCallFillsOfTwoNames() async throws {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Session", packageName: "pkg", swiftFileContentByFilePath: ["Deep.swift": """
				import SafeDI
				public protocol DeepService: Sendable {}
				@Instantiable(generateDependencyTree: true)
				public final class Deep: Instantiable, Sendable {
				    public init(deepService: any DeepService) { self.deepService = deepService }
				    @Instantiated public let deepService: any DeepService
				}
				"""]),
				ModuleFixture(name: "Feature", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": """
				import SafeDI
				import Session
				public protocol Service: Sendable {}
				@Instantiable public final class Analytics: Instantiable, Sendable { public init() {} }
				@Instantiable public final class StageOwner: Instantiable, Sendable {
				    public init(analytics: Analytics, service: any Service) { self.analytics = analytics; self.service = service }
				    @Instantiated public let analytics: Analytics
				    @Instantiated public let service: any Service
				}
				@Instantiable(generateDependencyTree: true) public final class Stager: Instantiable, Sendable {
				    public init(ownerBuilder: SendableInstantiator<StageOwner>) { self.ownerBuilder = ownerBuilder }
				    @Instantiated public let ownerBuilder: SendableInstantiator<StageOwner>
				}
				@Instantiable(fulfillingAdditionalTypes: [DeepService.self]) public final class DeepImpl: Instantiable, Sendable, DeepService {
				    public init(analytics: Analytics, service: any Service) { self.analytics = analytics; self.service = service }
				    @Instantiated public let analytics: Analytics
				    @Instantiated public let service: any Service
				}
				@Instantiable(generateDependencyTree: true) public final class Home: Instantiable, Sendable {
				    public init(stagerBuilder: SendableInstantiator<Stager>, deepBuilder: SendableInstantiator<Deep>) { self.stagerBuilder = stagerBuilder; self.deepBuilder = deepBuilder }
				    @Instantiated public let stagerBuilder: SendableInstantiator<Stager>
				    @Instantiated public let deepBuilder: SendableInstantiator<Deep>
				}
				@Instantiable(generateDependencyTree: true) public final class Both: Instantiable, Sendable {
				    public init(homeBuilder: SendableInstantiator<Home>) { self.homeBuilder = homeBuilder }
				    @Instantiated public let homeBuilder: SendableInstantiator<Home>
				}
				@Instantiable(generateDependencyTree: true) public final class Top: Instantiable, Sendable {
				    public init(both: Both) { self.both = both }
				    @Instantiated public let both: Both
				}
				"""], dependencies: ["Session"]),
				ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": """
				import Feature
				import SafeDI
				import Session
				@Instantiable(fulfillingAdditionalTypes: [Service.self]) public final class LiveService: Instantiable, Sendable, Service {
				    public init(stats: Analytics) { self.stats = stats }
				    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) public let stats: Analytics
				}
				@Instantiable(isRoot: true) public final class Root: Instantiable, Sendable {
				    public init(home: Home, top: Top) { self.home = home; self.top = top }
				    @Instantiated public let home: Home
				    @Instantiated public let top: Top
				}
				"""], dependencies: ["Feature", "Session"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)

		let rootPath = try #require(output.modules["App"]).fixtures["Root.swift"]
		#expect(output.modules["App"]?.generatedFiles["App.swift"] == generatedFileHeader + """
		#if canImport(Feature)
		import Feature
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Root {
		    public convenience init() {
		        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Stager_StageOwner_Scope_service(_ scope_analytics: Analytics) -> any Service {
		            return __safeDI_fillBody_3DA0D783809250A2(analytics: scope_analytics)
		        }
		        @Sendable nonisolated func __safeDI_fillBody_3DA0D783809250A2(analytics: Analytics) -> any Service {
		            func __safeDI_service() -> LiveService {
		                #sourceLocation(file: "\(rootPath)", line: 6)
		                let stats: Analytics = analytics
		                #sourceLocation()
		                return LiveService(stats: stats)
		            }
		            let service: any Service = __safeDI_service()
		            return service
		        }
		        @Sendable nonisolated func __safeDI_serviceSendableBuilder_Home_DeepImpl_Scope_service(_ scope: Home.SafeDIScope_Service.DeepImpl_Scope.service_Values) -> any Service {
		            return __safeDI_fillBody_3DA0D783809250A2(analytics: scope.analytics)
		        }
		        @Sendable nonisolated func __safeDI_serviceSendableBuilder_StageOwner_Stager_StageOwner_Scope_service(_ scope_analytics: Analytics) -> any Service {
		            return __safeDI_fillBody_3DA0D783809250A2(analytics: scope_analytics)
		        }
		        @Sendable nonisolated func __safeDI_serviceSendableBuilder_DeepImpl_Home_DeepImpl_Scope_service(_ scope: Home.SafeDIScope_Service.DeepImpl_Scope.service_Values) -> any Service {
		            return __safeDI_fillBody_3DA0D783809250A2(analytics: scope.analytics)
		        }
		        func __safeDI_home() -> Home {
		            _ = Home.__safeDI_Home_BA1C0D484BB01770.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Home() -> Home.SafeDISendableScope_Service.__safeDI_Builder<any Service> {
		                .init(stagerBuilder_Sendable: { _ in __safeDI_serviceSendableBuilder_Stager() }, deepBuilder_deepServiceBuilder: { _ in __safeDI_serviceBuilder_Home_Deep() })
		            }
		            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Stager() -> Stager.__safeDI_ServiceSendableCarrier<any Service> {
		                .init(ownerBuilder: { __safeDI_serviceBuilder_Stager_StageOwner_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Stager_StageOwner_Scope() -> Stager.__safeDI_ServiceCarrier_StageOwner<any Service> {
		                .init(service: { scope_analytics in __safeDI_serviceSendableBuilder_Stager_StageOwner_Scope_service(scope_analytics) })
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Home_DeepImpl_Scope() -> Home.SafeDIScope_Service.DeepImpl_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceSendableBuilder_Home_DeepImpl_Scope_service(scope) })
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Home_Deep() -> Deep.__safeDI_DeepServiceCarrier<Home.SafeDIScope_Service.DeepImpl_Scope.__safeDI_Builder<any Service>> {
		                .init(deepService: { __safeDI_serviceBuilder_Home_DeepImpl_Scope() })
		            }
		            return Home(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Home())
		        }
		        let home: Home = __safeDI_home()
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_7975D2135DE32E42.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Top() -> Top.__safeDI_ServiceSendableCarrier<any Service> {
		                .init(both_Sendable: __safeDI_serviceSendableBuilder_Both())
		            }
		            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Both() -> Both.__safeDI_ServiceSendableCarrier<any Service> {
		                .init(homeBuilder_Sendable: __safeDI_serviceSendableBuilder_Home())
		            }
		            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Home() -> Home.SafeDISendableScope_Service.__safeDI_Builder<any Service> {
		                .init(stagerBuilder_Sendable: { _ in __safeDI_serviceSendableBuilder_Stager() }, deepBuilder_deepServiceBuilder: { _ in __safeDI_serviceBuilder_Home_Deep() })
		            }
		            @Sendable nonisolated func __safeDI_serviceSendableBuilder_Stager() -> Stager.__safeDI_ServiceSendableCarrier<any Service> {
		                .init(ownerBuilder: { __safeDI_serviceBuilder_Stager_StageOwner_Scope() })
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Stager_StageOwner_Scope() -> Stager.__safeDI_ServiceCarrier_StageOwner<any Service> {
		                .init(service: { scope_analytics in __safeDI_serviceSendableBuilder_StageOwner_Stager_StageOwner_Scope_service(scope_analytics) })
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Home_DeepImpl_Scope() -> Home.SafeDIScope_Service.DeepImpl_Scope.__safeDI_Builder<any Service> {
		                .init(service: { scope in __safeDI_serviceSendableBuilder_DeepImpl_Home_DeepImpl_Scope_service(scope) })
		            }
		            @Sendable nonisolated func __safeDI_serviceBuilder_Home_Deep() -> Deep.__safeDI_DeepServiceCarrier<Home.SafeDIScope_Service.DeepImpl_Scope.__safeDI_Builder<any Service>> {
		                .init(deepService: { __safeDI_serviceBuilder_Home_DeepImpl_Scope() })
		            }
		            return Top(__safeDI_serviceSendableBuilder: __safeDI_serviceSendableBuilder_Top())
		        }
		        let top: Top = __safeDI_top()
		        self.init(home: home, top: top)
		    }
		}
		""")
	}

	/// The code generated for module `App`, whose root is `root`, built on `Seam`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generate(root: String, seamAddition: String = "") async throws -> String? {
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Seam", packageName: "pkg", swiftFileContentByFilePath: ["Types.swift": seamAddition.isEmpty ? Self.seam : Self.seam + "\n\n" + seamAddition]),
				ModuleFixture(name: "App", packageName: "pkg", swiftFileContentByFilePath: ["Root.swift": Self.impl + "\n\n" + root], dependencies: ["Seam"]),
			],
			integration: .moduleInfo,
			filesToDelete: &filesToDelete,
		)
		return output.modules["App"]?.generatedFiles["App.swift"]
	}

	// MARK: Fixtures

	/// `SafeDIToolSeamCarrierIsolationTests`’ seam, and `Outer`, a seam that calls it.
	private static let seam = """
	import SafeDI

	nonisolated public protocol Api {}

	@Instantiable
	public final class Model: Instantiable {
	    public init(id: Int) { self.id = id }
	    @Received let id: Int
	}

	@Instantiable
	public final class Detail: Instantiable {
	    public init(api: any Api) { self.api = api }
	    @Instantiated let api: any Api
	}

	@Instantiable
	public final class Screen: Instantiable {
	    public init(id: Int, model: Model, api: any Api, detailBuilder: Instantiator<Detail>) {
	        self.id = id; self.model = model; self.api = api; self.detailBuilder = detailBuilder
	    }
	    @Forwarded let id: Int
	    @Instantiated let model: Model
	    @Instantiated let api: any Api
	    @Instantiated let detailBuilder: Instantiator<Detail>
	}

	@Instantiable
	public final class Work: Instantiable {
	    public init(id: Int, model: Model, detailBuilder: Instantiator<Detail>) {
	        self.id = id; self.model = model; self.detailBuilder = detailBuilder
	    }
	    @Forwarded let id: Int
	    @Instantiated let model: Model
	    @Instantiated let detailBuilder: Instantiator<Detail>
	}

	@Instantiable(generateDependencyTree: true)
	public final class Home: Instantiable {
	    public init(screenBuilder: Instantiator<Screen>, workBuilder: SendableInstantiator<Work>) {
	        self.screenBuilder = screenBuilder; self.workBuilder = workBuilder
	    }
	    @Instantiated let screenBuilder: Instantiator<Screen>
	    @Instantiated let workBuilder: SendableInstantiator<Work>
	}

	@Instantiable(generateDependencyTree: true)
	public final class Outer: Instantiable {
	    public init(home: Home) { self.home = home }
	    @Instantiated let home: Home
	}
	"""

	/// The fill of `Api`, which reads the level’s `id` and `Model`.
	private static let impl = """
	import Seam
	import SafeDI

	@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
	public final class Impl: Api, Instantiable {
	    public init(id: Int, model: Model) { self.id = id; self.model = model }
	    @Received let id: Int
	    @Received let model: Model
	}
	"""

	/// The fill of `Api`, which reads the level’s `id` and `Model` and the caller’s `token`, with `Token`, which is `Sendable`, since `Home`’s `@Sendable` family builds a place whose fill reads it.
	private static let implReadingToken = """
	@Instantiable
	public final class Token: Instantiable, Sendable {
	    public init() {}
	}

	@Instantiable(fulfillingAdditionalTypes: [(any Api).self])
	public final class Impl: Api, Instantiable {
	    public init(id: Int, model: Model, token: Token) { self.id = id; self.model = model; self.token = token }
	    @Received let id: Int
	    @Received let model: Model
	    @Received let token: Token
	}
	"""

	private var filesToDelete: [URL]
}
