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

/// A place of `Inner`, a seam, that two routes of its tree reach, filled by `Top`, a seam of a module above, through
/// `Outer`, a seam between them, where the fill's tree reads `tag`, a label a scope on some of the routes binds.
///
/// The fill takes the label as a parameter: a route that binds it hands its own value, and a route that binds none
/// hands what the scopes enclosing `Top`'s call of `Outer` declare. `Top` declares none, so the read on such a route
/// leaves `Top`, which takes a parameter for it, as it would for the tree built inline.
struct SafeDIToolSeamFillReadOnSomeRoutesTests: ~Copyable {
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
	mutating func generate_seamTakesOptionalParameterForLabelItsFillReads_whenSomeRouteToPlaceBindsLabel() async throws {
		let modules = Self.modules(routes: [.bindingLabel, .atRoot], read: .onlyIfAvailable)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_tag: @autoclosure @escaping () -> Tag?) {
		        let tag = LazilyInstantiated<Tag?>(__safeDI_tag)
		        @inline(never) func __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: Tag?) -> Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = GadgetImpl(tag: tag)
		                return gadget
		            })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: tag) })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(service: { values_tag in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: values_tag) })
		        }
		        @inline(never) func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_3331E0C491C0ACF8.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(tag: tag.instance) })
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_D4F03FC0589CDA5F {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
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
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_D4F03FC0589CDA5F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top(__safeDI_tag: nil)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.probe(builders: ["screenBuilder"]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamPassesCallersValueToFill_whenSomeRouteToPlaceBindsLabelCallerDeclares() async throws {
		let modules = Self.modules(routes: [.bindingLabel, .atRoot], read: .onlyIfAvailable, rootDeclaresTag: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_tag: @autoclosure @escaping () -> Tag?) {
		        let tag = LazilyInstantiated<Tag?>(__safeDI_tag)
		        @inline(never) func __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: Tag?) -> Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = GadgetImpl(tag: tag)
		                return gadget
		            })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag?) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: tag) })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(service: { values_tag in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: values_tag) })
		        }
		        @inline(never) func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_3331E0C491C0ACF8.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(tag: tag.instance) })
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_D4F03FC0589CDA5F {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
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
		        let tag = Tag()
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_D4F03FC0589CDA5F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top(__safeDI_tag: tag)
		        }
		        let top: Top = __safeDI_top()
		        self.init(tag: tag, top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.probe(builders: ["screenBuilder"]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesNoParameterForLabelItsFillReads_whenEveryRouteToPlaceBindsLabel() async throws {
		let modules = Self.modules(routes: [.bindingLabel, .bindingLabelBesideFirst], read: .onlyIfAvailable)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Code you write and code SafeDI generates can both call this initializer.
		    public convenience init() {
		        @inline(never) func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		            .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = GadgetImpl(tag: tag)
		                return gadget
		            })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), sheetBuilder: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_Inner_Sheet_Scope() })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(service: { values_tag in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: values_tag) })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner_Sheet_Scope() -> Inner.__safeDI_ServiceCarrier_Sheet<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(service: { values_tag in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: values_tag) })
		        }
		        @inline(never) func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_4F6E54C67EC95FE8.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_CBF29CE484222325 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
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
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_CBF29CE484222325.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top()
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.probe(builders: ["screenBuilder", "sheetBuilder"]))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesOptionalParameterForLabelItsFillReads_whenNoRouteToPlaceBindsLabel() async throws {
		let modules = Self.modules(routes: [.bindingNothing, .atRoot], read: .onlyIfAvailable)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_tag: @autoclosure @escaping () -> Tag?) {
		        let tag = LazilyInstantiated<Tag?>(__safeDI_tag)
		        @inline(never) func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_3DB6D1007C15B7D4.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner() })
		            }
		            @inline(never) func __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope() -> Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget> {
		                .init(gadget: { _ in
		                    let gadget: any Gadget = GadgetImpl(tag: tag.instance)
		                    return gadget
		                })
		            }
		            @inline(never) func __safeDI_gadgetBuilder_Outer_Inner() -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		                .init(panel: __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope(), service: { values_panel in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope() })
		            }
		            @inline(never) func __safeDI_gadgetBuilder_Outer_Inner_Panel_Scope() -> Inner.__safeDI_ServiceCarrier_Panel<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		                .init(service: { __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope() })
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_D4F03FC0589CDA5F {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
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
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_D4F03FC0589CDA5F.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top(__safeDI_tag: nil)
		        }
		        let top: Top = __safeDI_top()
		        self.init(top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.probe(builders: []))
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_seamTakesRequiredParameterForLabelItsFillReads_whenSomeRouteToPlaceBindsLabelFillRequires() async throws {
		let modules = Self.modules(routes: [.bindingLabel, .atRoot], read: .required, rootDeclaresTag: true)
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: .moduleInfo, filesToDelete: &filesToDelete)
		#expect(output.modules["Feature"]?.generatedFiles == ["Feature.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
		#if canImport(SafeDI)
		import SafeDI
		#endif
		#if canImport(Session)
		import Session
		#endif

		extension Top {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public convenience init(__safeDI_tag: @autoclosure @escaping () -> Tag) {
		        let tag = LazilyInstantiated<Tag>(__safeDI_tag)
		        @inline(never) func __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: Tag) -> Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget> {
		            .init(gadget: { _ in
		                let gadget: any Gadget = GadgetImpl(tag: tag)
		                return gadget
		            })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner(tag: Tag) -> Inner.__safeDI_ServiceCarrier<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(screenBuilder: __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope(), service: { values_screenBuilder in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: tag) })
		        }
		        @inline(never) func __safeDI_gadgetBuilder_Outer_Inner_Screen_Scope() -> Inner.__safeDI_ServiceCarrier_Screen<Outer.SafeDIScope_Gadget.ServiceImpl_Scope.__safeDI_Builder<any Gadget>> {
		            .init(service: { values_tag in __safeDI_gadgetBuilder_Outer_ServiceImpl_Scope(tag: values_tag) })
		        }
		        @inline(never) func __safeDI_outer() -> Outer {
		            _ = Outer.__safeDI_Outer_3331E0C491C0ACF8.self // If this line does not compile, compile the code SafeDI generates for module Session into Session: under Bazel, add Session’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            @inline(never) func __safeDI_gadgetBuilder_Outer() -> Outer.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
		                .init(inner_serviceBuilder: { _ in __safeDI_gadgetBuilder_Outer_Inner(tag: tag.instance) })
		            }
		            return Outer(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Outer())
		        }
		        let outer: Outer = __safeDI_outer()
		        self.init(outer: outer)
		    }
		}

		extension Top {
		    public enum __safeDI_Top_304746C4E4869842 {}
		}
		"""])
		#expect(output.modules["App"]?.generatedFiles == ["App.swift": generatedFileHeader + """
		#if canImport(Core)
		import Core
		#endif
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
		        let tag = Tag()
		        func __safeDI_top() -> Top {
		            _ = Top.__safeDI_Top_304746C4E4869842.self // If this line does not compile, compile the code SafeDI generates for module Feature into Feature: under Bazel, add Feature’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes.
		            return Top(__safeDI_tag: tag)
		        }
		        let top: Top = __safeDI_top()
		        self.init(tag: tag, top: top)
		    }
		}
		"""])
		try await expectValues(of: output, modules: modules, equalThoseOf: Self.oneModule(modules), probe: Self.probe(builders: ["screenBuilder"]))
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// A route of `Inner`'s tree to a place of `service`.
	private enum Route {
		/// Beneath `Screen`, which `Inner` builds through an instantiator and which is forwarded `tag`.
		case bindingLabel
		/// Beneath `Sheet`, which `Inner` builds through an instantiator and which is forwarded `tag` too.
		case bindingLabelBesideFirst
		/// Beneath `Panel`, which `Inner` builds and which declares nothing but the place.
		case bindingNothing
		/// `Inner`'s own property.
		case atRoot
	}

	/// How the type that fills the place reads `tag`.
	private enum Read {
		case onlyIfAvailable
		case required
	}

	/// `Core`, which declares `Inner` with a place of `service` on each of `routes`; `Session`, whose seam `Outer` calls
	/// `Inner`; `Feature`, whose seam `Top` calls `Outer` and declares `ServiceImpl`, which fills the place and reads `tag`
	/// as `read` says; and `App`, whose root builds `Top`, beside a `tag` of its own where `rootDeclaresTag`.
	private static func modules(routes: [Route], read: Read, rootDeclaresTag: Bool = false) -> [ModuleFixture] {
		var holders = [String]()
		var innerParameters = [String]()
		var innerAssignments = [String]()
		var innerProperties = [String]()
		func addProperty(_ label: String, _ type: String) {
			innerParameters.append("\(label): \(type)")
			innerAssignments.append("self.\(label) = \(label)")
			innerProperties.append("@Instantiated public let \(label): \(type)")
		}
		func forwardedHolder(_ name: String) -> String {
			"""
			@Instantiable
			public final class \(name): Instantiable {
				public init(tag: Tag, service: any Service) { self.tag = tag; self.service = service }
				@Forwarded public let tag: Tag
				@Instantiated public let service: any Service
			}
			"""
		}
		for route in routes {
			switch route {
			case .bindingLabel:
				holders.append(forwardedHolder("Screen"))
				addProperty("screenBuilder", "Instantiator<Screen>")
			case .bindingLabelBesideFirst:
				holders.append(forwardedHolder("Sheet"))
				addProperty("sheetBuilder", "Instantiator<Sheet>")
			case .bindingNothing:
				holders.append("""
				@Instantiable
				public final class Panel: Instantiable {
					public init(service: any Service) { self.service = service }
					@Instantiated public let service: any Service
				}
				""")
				addProperty("panel", "Panel")
			case .atRoot:
				addProperty("service", "any Service")
			}
		}
		let (tagType, tagAttribute) = switch read {
		case .onlyIfAvailable: ("Tag?", "@Received(onlyIfAvailable: true)")
		case .required: ("Tag", "@Received")
		}
		let (rootParameters, rootAssignments, rootProperties) = rootDeclaresTag
			? ("tag: Tag, top: Top", "self.tag = tag; self.top = top", "@Instantiated public let tag: Tag\n\t@Instantiated public let top: Top")
			: ("top: Top", "self.top = top", "@Instantiated public let top: Top")
		return [
			ModuleFixture(name: "Core", packageName: "Min", swiftFileContent: ["""
			import SafeDI

			public protocol Service {}

			@Instantiable
			public final class Tag: Instantiable {
				public init() {}
			}

			\(holders.joined(separator: "\n\n"))

			@Instantiable(generateDependencyTree: true)
			public final class Inner: Instantiable {
				public init(\(innerParameters.joined(separator: ", "))) {
					\(innerAssignments.joined(separator: "\n\t\t"))
				}
				\(innerProperties.joined(separator: "\n\t"))
			}
			"""]),
			ModuleFixture(name: "Session", packageName: "Min", swiftFileContent: ["""
			import Core
			import SafeDI

			public protocol Gadget {}

			@Instantiable(fulfillingAdditionalTypes: [Service.self])
			public final class ServiceImpl: Instantiable, Service {
				public init(gadget: any Gadget) { self.gadget = gadget }
				@Instantiated public let gadget: any Gadget
			}

			@Instantiable(generateDependencyTree: true)
			public final class Outer: Instantiable {
				public init(inner: Inner) { self.inner = inner }
				@Instantiated public let inner: Inner
			}
			"""], dependencies: ["Core"]),
			ModuleFixture(name: "Feature", packageName: "Min", swiftFileContent: ["""
			import Core
			import Session
			import SafeDI

			@Instantiable(fulfillingAdditionalTypes: [Gadget.self])
			public final class GadgetImpl: Instantiable, Gadget {
				public init(tag: \(tagType)) { self.tag = tag }
				\(tagAttribute) public let tag: \(tagType)
			}

			@Instantiable(generateDependencyTree: true)
			public final class Top: Instantiable {
				public init(outer: Outer) { self.outer = outer }
				@Instantiated public let outer: Outer
			}
			"""], dependencies: ["Core", "Session"]),
			ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["""
			import Core
			import Feature
			import SafeDI

			@Instantiable(isRoot: true)
			public final class Root: Instantiable {
				public init(\(rootParameters)) { \(rootAssignments) }
				\(rootProperties)
			}
			"""], dependencies: ["Core", "Session", "Feature"]),
		]
	}

	/// A probe that builds `Root`, then what each of `builders`, instantiators of `Inner`, builds when forwarded a `Tag` of
	/// its own: the comparator then sees which `Tag` the `GadgetImpl` on each route holds.
	private static func probe(builders: [String]) -> DifferentialValueProbe {
		let built = builders.map { ", root.top.outer.inner.\($0).instantiate(Tag())" }.joined()
		return DifferentialValueProbe(name: "root beside what its builders build", expression: "{ () -> Any in\n\tlet root = Root()\n\treturn (root\(built))\n}()")
	}

	/// Every declaration of `modules` in one module, which builds every seam's tree inline.
	private static func oneModule(_ modules: [ModuleFixture]) -> [ModuleFixture] {
		let declarations = modules.map { module in
			module.swiftFileContent.joined(separator: "\n\n").components(separatedBy: "\n").filter { !$0.hasPrefix("import ") }.joined(separator: "\n")
		}
		return [ModuleFixture(name: "App", packageName: "Min", swiftFileContent: ["import SafeDI\n" + declarations.joined(separator: "\n")])]
	}

	/// Expects the values `output`, the run of `modules`, builds for `probe` to equal those `knownRightModules` build.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectValues(of output: MultiModuleTestOutput, modules: [ModuleFixture], equalThoseOf knownRightModules: [ModuleFixture], probe: DifferentialValueProbe, sourceLocation: SourceLocation = #_sourceLocation) async throws {
		guard compileVerificationIsEnabled else { return }
		let knownRightOutput = try await executeSafeDIToolMultiModuleTest(modules: knownRightModules, integration: .moduleInfo, compileVerification: .skipped, filesToDelete: &filesToDelete)
		try await expectDifferentialValuesAgree(
			feature: DifferentialValuePath(output: output, modules: modules),
			knownRight: DifferentialValuePath(output: knownRightOutput, modules: knownRightModules),
			probes: [probe],
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
