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

/// How the code a seam generates grows with the shape of its tree: what a value bound in the seam's tree costs where no
/// generated fill can read it.
struct SafeDIToolSeamGeneratedSizeTests: ~Copyable {
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
	mutating func generate_addsOneLinePerService_whenSeamPassesUpPlacesOfInnerSeams() async throws {
		// The adopter's wide shape P1, scaled down: `Home` instantiates services, then an instantiator of each of two screens,
		// each a seam of `Screens` that holds two hole types, which `Home` passes up for `App` to fill. No generated fill reads
		// a value `Home` binds before a call, and a call's case holds the screen's enum alone, so a service costs `Home` the one
		// line that builds it, as it would inline. When each call's case of each hole type carried every service, a service
		// cost a line per screen per hole type, and the adopter's 100 services, 40 screens and three hole types generated
		// 15,159 lines where `Home` generated 459 before its enums were nested by type.
		let oneService = try await homeLineCount(serviceCount: 1)
		let threeServices = try await homeLineCount(serviceCount: 3)
		#expect(threeServices - oneService == 2)
	}

	// MARK: Private

	private var filesToDelete: [URL]

	/// The number of lines `Feat` generates for `Home`, which instantiates `serviceCount` services, then
	/// `screen0Builder: Instantiator<Screen0>` and `screen1Builder: Instantiator<Screen1>`, each screen a seam of module
	/// `Screens` that instantiates `widget: any Widget` and `gadget: any Gadget`, which `App` fills.
	private mutating func homeLineCount(serviceCount: Int) async throws -> Int {
		let services = (0..<serviceCount).map { Self.type(named: "Service\($0)", properties: []) }
		let screens = (0..<2).map { index in
			Self.type(named: "Screen\(index)", attributes: "@Instantiable(generateDependencyTree: true)", properties: ["@Instantiated let widget: any Widget", "@Instantiated let gadget: any Gadget"])
		}
		let homeProperties = (0..<serviceCount).map { "@Instantiated let service\($0): Service\($0)" } + (0..<2).map { "@Instantiated let screen\($0)Builder: Instantiator<Screen\($0)>" }
		let output = try await executeSafeDIToolMultiModuleTest(
			modules: [
				ModuleFixture(name: "Core", packageName: "Shop", swiftFileContent: ["public protocol Widget {}", "public protocol Gadget {}"] + services),
				ModuleFixture(name: "Screens", packageName: "Shop", swiftFileContent: screens.map { "import Core\n\n" + $0 }, dependencies: ["Core"]),
				ModuleFixture(
					name: "Feat",
					packageName: "Shop",
					swiftFileContent: ["import Core\nimport Screens\n\n" + Self.type(named: "Home", attributes: "@Instantiable(generateDependencyTree: true)", properties: homeProperties)],
					dependencies: ["Core", "Screens"],
				),
				ModuleFixture(
					name: "App",
					packageName: "Other",
					swiftFileContent: [
						"@Instantiable(fulfillingAdditionalTypes: [Widget.self])\npublic final class LiveWidget: Widget, Instantiable {\n    public init() {}\n}",
						"@Instantiable(fulfillingAdditionalTypes: [Gadget.self])\npublic final class LiveGadget: Gadget, Instantiable {\n    public init() {}\n}",
						Self.type(named: "Root", attributes: "@Instantiable(isRoot: true)", properties: ["@Instantiated let home: Home"]),
					].map { "import Core\nimport Feat\nimport Screens\n\n" + $0 },
					dependencies: ["Core", "Screens", "Feat"],
				),
			],
			integration: .moduleInfo,
			compileVerification: .skipped,
			filesToDelete: &filesToDelete,
		)
		let generated = try #require(output.modules["Feat"]?.generatedFiles["Feat.swift"])
		return generated.components(separatedBy: "\n").count
	}

	/// A `public final class` named `name` whose initializer takes `properties`, each of `@Attribute let label: Type`.
	private static func type(named name: String, attributes: String = "@Instantiable", properties: [String]) -> String {
		let parameters = properties.map { property in
			property.components(separatedBy: " let ").last ?? ""
		}
		let labels = parameters.map { String($0.prefix { $0 != ":" }) }
		return """
		\(attributes)
		public final class \(name): Instantiable {
		    public init(\(parameters.joined(separator: ", "))) {
		\(labels.map { "        self.\($0) = \($0)" }.joined(separator: "\n"))
		    }
		\(properties.map { "    \($0)" }.joined(separator: "\n"))
		}
		"""
	}
}
