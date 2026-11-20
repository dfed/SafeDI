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

/// Where the tree of `Page`’s fill reaches `Book`, whose builder of `Page` re-enters the call, and the type that
/// instantiates `analytics: any Analytics`, which nothing `App` sees fulfills (`ReenteringFillFixtures`).
enum ReenteringFillLayout: CaseIterable {
	/// `DefaultService`, `Page`’s fill, instantiates `analytics` and builds `Book`.
	case fillInstantiatesIt
	/// `Page` holds a second place, `logger`, whose fill `DefaultLogger` instantiates `analytics`; `DefaultService`, the
	/// fill of `service`, builds `Book`, so `analytics` is reached on the route of either place.
	case siblingPlacesFillInstantiatesIt
	/// `Book` holds a place of its own, `store`, whose fill `DefaultStore` instantiates `analytics`; `DefaultService`
	/// builds `Book`.
	case calledMocksOwnPlacesFillInstantiatesIt
	/// `DefaultService` builds `Chapter`, a public mock of `Core`, whose fill `DefaultStore` instantiates `analytics` and
	/// builds `Book`: the call that re-enters `Page`’s is nested in a fill of another call.
	case nestedCallsFillInstantiatesIt
	/// `DefaultService` instantiates `analytics` and builds `Chapter`, whose fill `DefaultStore` builds `Book`.
	case fillAroundNestedCallInstantiatesIt
	/// `DefaultService` instantiates `analytics` and holds `Page` in the builder itself, so the call inside its fill is of
	/// `Page`, and `Mid`’s `Book`, which holds `Page` in the builder too, is a public mock or a seam no type of `App`
	/// builds.
	case fillCallsCalledTypeItselfBesideUncalledHolder
}

/// The builder that holds `Page` where a type re-enters its call: `Book`’s, and `DefaultService`’s own in
/// `ReenteringFillLayout.fillCallsCalledTypeItselfBesideUncalledHolder`.
enum ReenteringFillBuilder: CaseIterable {
	case instantiator
	/// A `SendableInstantiator`, whose `@Sendable` builder function re-enters the fill of `Page`’s place, so that fill is
	/// built in a `@Sendable` function and `analytics` is a place of the `@Sendable` family.
	case sendableInstantiator

	/// The builder’s type over `Page`.
	var typeOfPage: String {
		switch self {
		case .instantiator:
			"Instantiator<Page>"
		case .sendableInstantiator:
			"SendableInstantiator<Page>"
		}
	}

	/// The label of the builder of `analytics` that a calling mock or the twin takes.
	var analyticsBuilderLabel: String {
		switch self {
		case .instantiator:
			"analyticsBuilder"
		case .sendableInstantiator:
			"analyticsSendableBuilder"
		}
	}
}

/// The files of a graph in which a fill of `Page`’s place, a public mock or a seam of module `Core`, builds a type of a
/// third module, `Mid`, that holds a builder of `Page`, and whose tree, through that re-entry or beside it, reaches
/// `analytics: any Analytics`, which nothing module `App` sees fulfills.
enum ReenteringFillFixtures {
	static let publicMock = "@Instantiable(generateMock: .public)"
	static let seamAndPublicMock = "@Instantiable(generateDependencyTree: true, generateMock: .public)"

	/// `Core`’s file: `Page`, whose places of `Service`, and of `Logger` for the sibling place’s layout, no type `Core` sees
	/// fulfills, and, where the layout nests a call, `Chapter`, whose place of `Store` no type `Core` sees fulfills either.
	static func core(of layout: ReenteringFillLayout, attribute: String) -> String {
		var protocols = ["public protocol Service: AnyObject {}"]
		var page = """
		\(attribute)
		public final class Page: Instantiable {
		    init(service: any Service) { self.service = service }
		    @Instantiated public let service: any Service
		}
		"""
		var chapter = ""
		switch layout {
		case .fillInstantiatesIt, .fillCallsCalledTypeItselfBesideUncalledHolder:
			break
		case .siblingPlacesFillInstantiatesIt:
			protocols.append("public protocol Logger: AnyObject {}")
			page = """
			\(attribute)
			public final class Page: Instantiable {
			    init(service: any Service, logger: any Logger) { self.service = service; self.logger = logger }
			    @Instantiated public let service: any Service
			    @Instantiated public let logger: any Logger
			}
			"""
		case .calledMocksOwnPlacesFillInstantiatesIt:
			protocols.append("public protocol Store: AnyObject {}")
		case .nestedCallsFillInstantiatesIt, .fillAroundNestedCallInstantiatesIt:
			protocols.append("public protocol Store: AnyObject {}")
			chapter = """

			\(attribute)
			public final class Chapter: Instantiable {
			    init(store: any Store) { self.store = store }
			    @Instantiated public let store: any Store
			}
			"""
		}
		return """
		import SafeDI

		\(protocols.joined(separator: "\n\n"))

		\(page)
		\(chapter)

		"""
	}

	/// `Mid`’s file: `Book`, which holds `Page` in `builder`, and, for the called mock’s own place’s layout, a place of
	/// `Store`.
	static func mid(of layout: ReenteringFillLayout, attribute: String, builder: ReenteringFillBuilder = .instantiator) -> String {
		let book = if layout == .calledMocksOwnPlacesFillInstantiatesIt {
			"""
			public final class Book: Instantiable {
			    init(pageBuilder: \(builder.typeOfPage), store: any Store) { self.pageBuilder = pageBuilder; self.store = store }
			    @Instantiated public let pageBuilder: \(builder.typeOfPage)
			    @Instantiated public let store: any Store
			}
			"""
		} else {
			"""
			public final class Book: Instantiable {
			    init(pageBuilder: \(builder.typeOfPage)) { self.pageBuilder = pageBuilder }
			    @Instantiated public let pageBuilder: \(builder.typeOfPage)
			}
			"""
		}
		return """
		import Core
		import SafeDI

		\(attribute)
		\(book)

		"""
	}

	/// `App`’s file: `Analytics`, `LiveAnalytics`, the fills (`ReenteringFillLayout`), and the caller `Screen`, which builds
	/// `Page`. `analyticsIsInstantiable` says whether `LiveAnalytics` is an `Instantiable` that fulfills `Analytics`, a
	/// plain class, or, where `nil`, not declared.
	static func app(of layout: ReenteringFillLayout, callerAttribute: String, access: String, analyticsIsInstantiable: Bool?, builder: ReenteringFillBuilder = .instantiator) -> String {
		func fulfilling(_ type: String, _ protocolName: String, _ properties: [(label: String, type: String)]) -> String {
			let parameters = properties.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
			let assignments = properties.map { "self.\($0.label) = \($0.label)" }.joined(separator: "; ")
			let declarations = properties.map { "    @Instantiated let \($0.label): \($0.type)" }.joined(separator: "\n")
			return """
			@Instantiable(fulfillingAdditionalTypes: [(any \(protocolName)).self])
			\(access)final class \(type): \(protocolName), Instantiable {
			    \(access)init(\(parameters)) { \(assignments) }
			\(declarations)
			}
			"""
		}
		let analytics = (label: "analytics", type: "any Analytics")
		let fills = switch layout {
		case .fillInstantiatesIt:
			[fulfilling("DefaultService", "Service", [analytics, ("book", "Book")])]
		case .siblingPlacesFillInstantiatesIt:
			[fulfilling("DefaultService", "Service", [("book", "Book")]), fulfilling("DefaultLogger", "Logger", [analytics])]
		case .calledMocksOwnPlacesFillInstantiatesIt:
			[fulfilling("DefaultService", "Service", [("book", "Book")]), fulfilling("DefaultStore", "Store", [analytics])]
		case .nestedCallsFillInstantiatesIt:
			[fulfilling("DefaultService", "Service", [("chapter", "Chapter")]), fulfilling("DefaultStore", "Store", [analytics, ("book", "Book")])]
		case .fillAroundNestedCallInstantiatesIt:
			[fulfilling("DefaultService", "Service", [analytics, ("chapter", "Chapter")]), fulfilling("DefaultStore", "Store", [("book", "Book")])]
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			[fulfilling("DefaultService", "Service", [analytics, ("pageBuilder", builder.typeOfPage)])]
		}
		var declarations = ["public protocol Analytics: AnyObject {}"]
		switch analyticsIsInstantiable {
		case true:
			declarations.append("""
			@Instantiable(fulfillingAdditionalTypes: [(any Analytics).self])
			public final class LiveAnalytics: Analytics, Instantiable {
			    public init() {}
			}
			""")
		case false:
			declarations.append("""
			public final class LiveAnalytics: Analytics {
			    public init() {}
			}
			""")
		case nil:
			break
		}
		declarations += fills
		// A `Screen` another module builds has an initializer only `App` calls, so that module calls its public mock.
		let screenInitializerAccess = analyticsIsInstantiable == nil ? "" : access
		declarations.append("""
		\(callerAttribute)
		\(access)final class Screen: Instantiable {
		    \(screenInitializerAccess)init(page: Page) { self.page = page }
		    @Instantiated let page: Page
		}
		""")
		return """
		import Core
		import Mid
		import SafeDI

		\(declarations.joined(separator: "\n\n"))

		"""
	}

	/// An expression that reads `Screen`, built by `screen`, and the `Page` that `Book`’s builder builds, or, where
	/// `DefaultService` holds `Page`’s builder itself, that builder builds, which re-enters the call’s level functions or
	/// the seam’s fill.
	static func screenAndReenteredPage(of layout: ReenteringFillLayout, screen: String) -> String {
		switch layout {
		case .fillInstantiatesIt, .siblingPlacesFillInstantiatesIt, .calledMocksOwnPlacesFillInstantiatesIt:
			"{ let screen = \(screen); let service = screen.page.service as! App.DefaultService; return (screen, service.book.pageBuilder.instantiate()) }()"
		case .nestedCallsFillInstantiatesIt, .fillAroundNestedCallInstantiatesIt:
			"{ let screen = \(screen); let store = (screen.page.service as! App.DefaultService).chapter.store as! App.DefaultStore; return (screen, store.book.pageBuilder.instantiate()) }()"
		case .fillCallsCalledTypeItselfBesideUncalledHolder:
			"{ let screen = \(screen); let service = screen.page.service as! App.DefaultService; return (screen, service.pageBuilder.instantiate()) }()"
		}
	}
}
