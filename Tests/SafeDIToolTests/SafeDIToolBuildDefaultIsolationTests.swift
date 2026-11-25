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

/// How `generate` compares the default isolation a build reports, through an expanded
/// `--build-setting-other-swift-flags` or `--build-default-isolation`, with the one the module’s
/// `#SafeDIConfiguration` declares. It warns when they disagree, and never changes the generated code.
struct SafeDIToolBuildDefaultIsolationTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Tests – Build settings

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenBuildSettingsReportMainActorAndConfigurationDeclaresIt() async throws {
		let output = try await generate(
			configuration: Self.mainActorConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-DXcode -default-isolation MainActor -g"),
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsAtConfiguration_whenBuildSettingsReportMainActorAndConfigurationDoesNotDeclareIt() async throws {
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-DXcode -default-isolation MainActor -g"),
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: \(Self.undeclaredMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsNamingWhereToDeclareIt_whenBuildSettingsReportMainActorAndModuleHasNoConfiguration() async throws {
		let output = try await generate(
			configuration: nil,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-default-isolation MainActor"),
		)

		#expect(output.warnings.map(\.formatted) == [
			"warning: This module is compiled with `-default-isolation MainActor`, but it declares no `#SafeDIConfiguration`, so SafeDI generates code for a nonisolated module. Add `#SafeDIConfiguration(defaultIsolation: MainActor.self)` to a file named `SafeDIConfiguration.swift` in this module.",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsAtConfiguration_whenBuildSettingsReportNonisolatedAndConfigurationDeclaresMainActor() async throws {
		let output = try await generate(
			configuration: Self.mainActorConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-default-isolation nonisolated"),
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: \(Self.declaredMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenBuildSettingsReportNonisolatedAndConfigurationDoesNotDeclareMainActor() async throws {
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-default-isolation nonisolated"),
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenBuildSettingsReportNonisolatedAndModuleHasNoConfiguration() async throws {
		let output = try await generate(
			configuration: nil,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-default-isolation nonisolated"),
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenBuildSettingsReportNoDefaultIsolation() async throws {
		// A build setting other than `OTHER_SWIFT_FLAGS` can set the default isolation, so a flag’s absence says nothing.
		let output = try await generate(
			configuration: Self.mainActorConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-DXcode -g"),
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenBuildSettingsAreUnexpanded() async throws {
		// SwiftPM's native build system passes the references through, so the flag beside one is not what the compiler receives.
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: [
				"--build-setting-active-compilation-conditions=[${SWIFT_ACTIVE_COMPILATION_CONDITIONS}]",
				"--build-setting-other-swift-flags=[-default-isolation MainActor ${OTHER_SWIFT_FLAGS}]",
			],
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsLastDefaultIsolationFlag_whenBuildSettingsRepeatItInBothSpellings() async throws {
		let output = try await generate(
			configuration: Self.mainActorConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-default-isolation MainActor -default-isolation=nonisolated"),
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: \(Self.declaredMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenLastDefaultIsolationFlagHasAValueTheCompilerRejects() async throws {
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-default-isolation MainActor -default-isolation=mainactor"),
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenDefaultIsolationFlagIsPassedToAnotherTool() async throws {
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: Self.buildSettingArguments(otherSwiftFlags: "-Xllvm -default-isolation -Xllvm MainActor"),
		)

		#expect(output.warnings == [])
	}

	// MARK: Tests – --build-default-isolation

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsAtConfiguration_whenOptionReportsMainActorAndConfigurationDoesNotDeclareIt() async throws {
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: ["--build-default-isolation", "MainActor"],
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: \(Self.undeclaredMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_warnsAtConfiguration_whenOptionReportsNonisolatedAndConfigurationDeclaresMainActor() async throws {
		let output = try await generate(
			configuration: Self.mainActorConfiguration,
			buildSettingArguments: ["--build-default-isolation=nonisolated"],
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: \(Self.declaredMessage)",
		])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_doesNotWarn_whenOptionNamesNeitherIsolationTheCompilerAccepts() async throws {
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: ["--build-default-isolation=CustomActor"],
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsBuildSettingsOverOption_whenBothReportDefaultIsolation() async throws {
		// The compiler receives `OTHER_SWIFT_FLAGS` after the flag Xcode’s setting adds, so the last flag is the setting’s.
		let output = try await generate(
			configuration: Self.mainActorConfiguration,
			buildSettingArguments: ["--build-default-isolation=nonisolated"] + Self.buildSettingArguments(otherSwiftFlags: "-default-isolation MainActor"),
		)

		#expect(output.warnings == [])
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_readsOption_whenBuildSettingsReportNoDefaultIsolation() async throws {
		let output = try await generate(
			configuration: Self.undeclaredConfiguration,
			buildSettingArguments: ["--build-default-isolation=MainActor"] + Self.buildSettingArguments(otherSwiftFlags: "-g"),
		)

		#expect(output.warnings.map(\.formatted) == [
			"\(output.fixtures["SafeDIConfiguration.swift"]):1:1: warning: \(Self.undeclaredMessage)",
		])
	}

	// MARK: Tests – Generated code

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_generatesSameCode_whetherOrNotBuildReportsDefaultIsolation() async throws {
		for configuration in [Self.mainActorConfiguration, Self.undeclaredConfiguration] {
			let unreported = try await generate(
				configuration: configuration,
				buildSettingArguments: [],
			)
			for reportedIsolation in ["MainActor", "nonisolated"] {
				let reported = try await generate(
					configuration: configuration,
					buildSettingArguments: ["--build-default-isolation", reportedIsolation],
				)

				#expect(reported.dependencyTreeFiles == unreported.dependencyTreeFiles)
				#expect(reported.mockFiles == unreported.mockFiles)
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]

	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generate(
		configuration: String?,
		buildSettingArguments: [String],
	) async throws -> TestOutput {
		try await executeSafeDIToolTest(
			swiftFileContent: [Self.rootContent],
			swiftFileContentByFilePath: configuration.map { ["SafeDIConfiguration.swift": $0] } ?? [:],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
			buildSettingArguments: buildSettingArguments,
			// Compiled under the isolation the configuration declares, which the generated code follows whatever the build reports.
			verificationCompilerSettings: VerificationCompilerSettings(defaultIsolation: configuration == Self.mainActorConfiguration ? "MainActor" : nil),
		)
	}

	private static func buildSettingArguments(otherSwiftFlags: String) -> [String] {
		[
			"--build-setting-active-compilation-conditions=[DEBUG]",
			"--build-setting-other-swift-flags=[\(otherSwiftFlags)]",
		]
	}

	private static let mainActorConfiguration = """
	#SafeDIConfiguration(defaultIsolation: MainActor.self)
	"""

	private static let undeclaredConfiguration = """
	#SafeDIConfiguration(additionalImportedModules: [])
	"""

	private static let undeclaredMessage = "This module is compiled with `-default-isolation MainActor`, but `#SafeDIConfiguration` doesn’t declare `defaultIsolation: MainActor.self`, so SafeDI generates code for a nonisolated module."

	private static let declaredMessage = "This module is compiled with `-default-isolation nonisolated`, but `#SafeDIConfiguration` declares `defaultIsolation: MainActor.self`, so SafeDI generates code for a main-actor module."

	private static let rootContent = """
	@Instantiable(isRoot: true, generateMock: true)
	public struct Root: Instantiable {
	    public init(service: Service) {
	        self.service = service
	    }

	    @Instantiated let service: Service
	}

	@Instantiable
	public struct Service: Instantiable {
	    public init() {}
	}
	"""
}
