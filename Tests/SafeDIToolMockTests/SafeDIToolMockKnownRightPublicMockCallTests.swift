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

/// An internal mock that holds a reader of `x: PX?` in its own module, beside or above a service whose public mock, in
/// another module, reads `x: PX`, checked against a build written by hand from the Manual: the mock promotes one
/// non-optional `x` and hands it to both readers, the public mock's call included.
struct SafeDIToolMockKnownRightPublicMockCallTests: ~Copyable {
	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try? FileManager.default.removeItem(at: fileToDelete)
		}
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_sharesOneNonOptionalValue_whenOptionalReaderIsBesideServiceWhosePublicMockReadsItNonOptionally(integration: MultiModuleIntegration) async throws {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "PStamp")
		let core = """
		import SafeDI

		@Instantiable
		public final class PX: Instantiable {
		    public init() {}
		    \(stamp)
		}

		@Instantiable
		public final class PB: Instantiable {
		    package init(x: PX) {
		        self.x = x
		    }

		    @Received let x: PX
		    \(stamp)
		}

		@Instantiable(generateMock: .public)
		public final class PSvc: Instantiable {
		    package init(b: PB) {
		        self.b = b
		    }

		    @Instantiated let b: PB
		    \(stamp)
		}
		"""
		let app = """
		import Core
		import SafeDI

		@Instantiable
		public final class PC: Instantiable {
		    public init(x: PX?) {
		        self.x = x
		    }

		    @Received let x: PX?
		    \(stamp)
		}

		@Instantiable(generateMock: true)
		public final class PScreen: Instantiable {
		    public init(c: PC, svc: PSvc) {
		        self.c = c
		        self.svc = svc
		    }

		    @Instantiated let c: PC
		    @Received let svc: PSvc
		    \(stamp)
		}

		@Instantiable
		public final class PFeature: Instantiable {
		    public init(x: PX?, screen: PScreen) {
		        self.x = x
		        self.screen = screen
		    }

		    @Forwarded let x: PX?
		    @Instantiated let screen: PScreen
		    \(stamp)
		}
		"""
		let expected = """
		import Core

		func expectedScreen(x: PX = PX()) -> PScreen {
		    PScreen(c: PC(x: x), svc: expectedService(x: x))
		}
		"""
		try await expectAgreement(core: core, app: app, expected: expected, integration: integration, probes: [
			(#"PScreen.mock()"#, #"expectedScreen()"#),
			(#"{ let x = PX(); return (PScreen.mock(safeDIOverrides: .init(x: { x })), x) }()"#, #"{ let x = PX(); return (expectedScreen(x: x), x) }()"#),
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_sharesOneNonOptionalValue_whenOptionalReaderIsBesideServiceWhosePublicMockReadsItNonOptionallyAsFlatParameter(integration: MultiModuleIntegration) async throws {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "PStamp")
		let core = """
		import SafeDI

		public final class PX {
		    public init() {}
		    \(stamp)
		}

		@Instantiable
		public final class PB: Instantiable {
		    package init(x: PX) {
		        self.x = x
		    }

		    @Received let x: PX
		    \(stamp)
		}

		@Instantiable(generateMock: .public)
		public final class PSvc: Instantiable {
		    package init(b: PB) {
		        self.b = b
		    }

		    @Instantiated let b: PB
		    \(stamp)
		}
		"""
		let app = """
		import Core
		import SafeDI

		@Instantiable
		public final class PC: Instantiable {
		    public init(x: PX?) {
		        self.x = x
		    }

		    @Received let x: PX?
		    \(stamp)
		}

		@Instantiable(generateMock: true)
		public final class PScreen: Instantiable {
		    public init(c: PC, svc: PSvc) {
		        self.c = c
		        self.svc = svc
		    }

		    @Instantiated let c: PC
		    @Received let svc: PSvc
		    \(stamp)
		}

		@Instantiable
		public final class PFeature: Instantiable {
		    public init(x: PX?, screen: PScreen) {
		        self.x = x
		        self.screen = screen
		    }

		    @Forwarded let x: PX?
		    @Instantiated let screen: PScreen
		    \(stamp)
		}
		"""
		let expected = """
		import Core

		func expectedScreen(x: PX) -> PScreen {
		    PScreen(c: PC(x: x), svc: expectedService(x: x))
		}
		"""
		try await expectAgreement(core: core, app: app, expected: expected, integration: integration, probes: [
			(#"{ let x = PX(); return (PScreen.mock(x: x), x) }()"#, #"{ let x = PX(); return (expectedScreen(x: x), x) }()"#),
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_sharesOneNonOptionalValue_whenOptionalReaderReceivesServiceWhosePublicMockReadsItNonOptionally(integration: MultiModuleIntegration) async throws {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "PStamp")
		let core = """
		import SafeDI

		@Instantiable
		public final class PX: Instantiable {
		    public init() {}
		    \(stamp)
		}

		@Instantiable
		public final class PB: Instantiable {
		    package init(x: PX) {
		        self.x = x
		    }

		    @Received let x: PX
		    \(stamp)
		}

		@Instantiable(generateMock: .public)
		public final class PSvc: Instantiable {
		    package init(b: PB) {
		        self.b = b
		    }

		    @Instantiated let b: PB
		    \(stamp)
		}
		"""
		let app = """
		import Core
		import SafeDI

		@Instantiable
		public final class PC: Instantiable {
		    public init(x: PX?, svc: PSvc) {
		        self.x = x
		        self.svc = svc
		    }

		    @Received let x: PX?
		    @Received let svc: PSvc
		    \(stamp)
		}

		@Instantiable(generateMock: true)
		public final class PScreen: Instantiable {
		    public init(c: PC) {
		        self.c = c
		    }

		    @Instantiated let c: PC
		    \(stamp)
		}

		@Instantiable
		public final class PFeature: Instantiable {
		    public init(x: PX?, screen: PScreen) {
		        self.x = x
		        self.screen = screen
		    }

		    @Forwarded let x: PX?
		    @Instantiated let screen: PScreen
		    \(stamp)
		}
		"""
		let expected = """
		import Core

		func expectedScreen(x: PX = PX()) -> PScreen {
		    PScreen(c: PC(x: x, svc: expectedService(x: x)))
		}
		"""
		try await expectAgreement(core: core, app: app, expected: expected, integration: integration, probes: [
			(#"PScreen.mock()"#, #"expectedScreen()"#),
			(#"{ let x = PX(); return (PScreen.mock(safeDIOverrides: .init(x: { x })), x) }()"#, #"{ let x = PX(); return (expectedScreen(x: x), x) }()"#),
		])
	}

	@Test(arguments: MultiModuleIntegration.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_sharesOneNonOptionalValue_whenOptionalReaderReceivesServiceWhosePublicMockReadsItNonOptionallyAsFlatParameter(integration: MultiModuleIntegration) async throws {
		let stamp = DifferentialValueCreationStamp.property(counterNamed: "PStamp")
		let core = """
		import SafeDI

		public final class PX {
		    public init() {}
		    \(stamp)
		}

		@Instantiable
		public final class PB: Instantiable {
		    package init(x: PX) {
		        self.x = x
		    }

		    @Received let x: PX
		    \(stamp)
		}

		@Instantiable(generateMock: .public)
		public final class PSvc: Instantiable {
		    package init(b: PB) {
		        self.b = b
		    }

		    @Instantiated let b: PB
		    \(stamp)
		}
		"""
		let app = """
		import Core
		import SafeDI

		@Instantiable
		public final class PC: Instantiable {
		    public init(x: PX?, svc: PSvc) {
		        self.x = x
		        self.svc = svc
		    }

		    @Received let x: PX?
		    @Received let svc: PSvc
		    \(stamp)
		}

		@Instantiable(generateMock: true)
		public final class PScreen: Instantiable {
		    public init(c: PC) {
		        self.c = c
		    }

		    @Instantiated let c: PC
		    \(stamp)
		}

		@Instantiable
		public final class PFeature: Instantiable {
		    public init(x: PX?, screen: PScreen) {
		        self.x = x
		        self.screen = screen
		    }

		    @Forwarded let x: PX?
		    @Instantiated let screen: PScreen
		    \(stamp)
		}
		"""
		let expected = """
		import Core

		func expectedScreen(x: PX) -> PScreen {
		    PScreen(c: PC(x: x, svc: expectedService(x: x)))
		}
		"""
		try await expectAgreement(core: core, app: app, expected: expected, integration: integration, probes: [
			(#"{ let x = PX(); return (PScreen.mock(x: x), x) }()"#, #"{ let x = PX(); return (expectedScreen(x: x), x) }()"#),
		])
	}

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func expectAgreement(
		core: String,
		app: String,
		expected: String,
		integration: MultiModuleIntegration,
		probes: [(feature: String, knownRight: String)],
		sourceLocation: SourceLocation = #_sourceLocation,
	) async throws {
		let modules = [
			ModuleFixture(name: "Core", packageName: "core", swiftFileContentByFilePath: [
				"Core.swift": core,
				"PStamp.swift": DifferentialValueCreationStamp.counterDeclaration(named: "PStamp"),
			]),
			ModuleFixture(name: "App", packageName: "app", swiftFileContentByFilePath: ["App.swift": app], dependencies: ["Core"]),
		]
		let output = try await executeSafeDIToolMultiModuleTest(modules: modules, integration: integration, filesToDelete: &filesToDelete)
		let feature = try DifferentialValuePath(output: output, modules: modules)
		let knownRight = DifferentialValuePath(modules: feature.modules.map { module in
			var module = module
			if module.name == "App" {
				module.fixtureFiles["Expected.swift"] = expected
			} else {
				// The service’s initializer is `package`, so the hand build of what its public mock builds is in its module.
				module.fixtureFiles["ExpectedService.swift"] = "public func expectedService(x: PX) -> PSvc {\n    PSvc(b: PB(x: x))\n}"
			}
			return module
		})
		try await expectDifferentialValuesAgree(
			feature: feature,
			knownRight: knownRight,
			probes: probes.map { DifferentialValueProbe(name: $0.feature, expression: $0.feature, knownRightExpression: $0.knownRight) },
			filesToDelete: &filesToDelete,
			sourceLocation: sourceLocation,
		)
	}
}
