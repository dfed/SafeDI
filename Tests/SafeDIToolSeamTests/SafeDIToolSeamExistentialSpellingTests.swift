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

/// A seam spells a value its tree's receivers spell apart, `any Service` and `Service`, which `==` reads as one type, as
/// the most explicit of their spellings, `any Service`, whichever receiver the tree reaches first: the parameter a
/// module that enables the `ExistentialAny` upcoming feature, which every compile of these tests enables, declares
/// without a warning. An alias's receive is spelled as its property spells it, never as its `ofType:` does.
struct SafeDIToolSeamExistentialSpellingTests: ~Copyable {
	// MARK: Initialization

	init() {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Fixtures

	/// `Root` holds `service` and builds the seam `Screen`, which builds `First` and then `Second`, each declaring
	/// `firstReceive` and `secondReceive`.
	private static func fixture(firstReceive: String, secondReceive: String) -> [String] {
		[
			seamFixtureType(named: "Root", isRoot: true, declarations: ["@Instantiated(fulfilledByType: \"DefaultService\") let service: any Service", "@Instantiated let screen: Screen"]),
			seamFixtureType(named: "Screen", isSeam: true, declarations: ["@Instantiated let first: First", "@Instantiated let second: Second"]),
			seamFixtureType(named: "First", declarations: [firstReceive]),
			seamFixtureType(named: "Second", declarations: [secondReceive]),
			"""
			public protocol Service {}

			@Instantiable
			public struct DefaultService: Service, Instantiable {
			    public init() {}
			}
			""",
		]
	}

	// MARK: Tests

	@Test(arguments: SeamReceiverSpellings.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPassThroughWithAny_whenTwoReceiversInTreeSpellItApart(spellings: SeamReceiverSpellings) async throws {
		let files = Self.fixture(
			firstReceive: "@Received let service: \(spellings.first)",
			secondReceive: "@Received let service: \(spellings.second)",
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_service: @autoclosure @escaping () -> any Service) {
		        let service = LazilyInstantiated<any Service>(__safeDI_service)
		        let first = First(service: service.instance)
		        let second = Second(service: service.instance)
		        self.init(first: first, second: second)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_6C3D8B09996784A6 {}
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test(arguments: SeamReceiverSpellings.allCases)
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPassThroughWithAny_whenOneReceiverRequiresItAndAnotherReceivesItsOptionalFormOnlyIfAvailable(spellings: SeamReceiverSpellings) async throws {
		let files = Self.fixture(
			firstReceive: "@Received let service: \(spellings.first)",
			secondReceive: "@Received(onlyIfAvailable: true) let service: \(spellings.secondOptional)",
		)
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_service: @autoclosure @escaping () -> any Service) {
		        let service = LazilyInstantiated<any Service>(__safeDI_service)
		        let first = First(service: service.instance)
		        let second = Second(service: service.instance)
		        self.init(first: first, second: second)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_6C3D8B09996784A6 {}
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func generate_spellsPassThroughAsAliasesInTreeDeclareIt_whenEveryReceiverReceivesItThroughAliasOfBareOfType() async throws {
		// Every declaration spells `any Service`: `Service.self` is an expression, which the `ExistentialAny` upcoming
		// feature does not flag, so a parameter spelled from it would be the only bare spelling in the module.
		let alias = "@Received(fulfilledByDependencyNamed: \"service\", ofType: Service.self) let other: any Service"
		let files = Self.fixture(firstReceive: alias, secondReceive: alias)
		let output = try await executeSafeDIToolTest(swiftFileContent: files, buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		#expect(output.dependencyTreeFiles["Screen+SafeDI.swift"] == generatedFileHeader + """
		extension Screen {
		    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.
		    /// To call this type from code you write, set `generatePlainDependencyTreeInitializers: true` in this module’s `#SafeDIConfiguration`.
		    public init(__safeDI_service: @autoclosure @escaping () -> any Service) {
		        let service = LazilyInstantiated<any Service>(__safeDI_service)
		        @inline(never) func __safeDI_first() -> First {
		            #sourceLocation(file: "\(output.fixtures["First.swift"])", line: 7)
		            let other: any Service = service.instance
		            #sourceLocation()
		            return First(other: other)
		        }
		        let first: First = __safeDI_first()
		        @inline(never) func __safeDI_second() -> Second {
		            #sourceLocation(file: "\(output.fixtures["Second.swift"])", line: 7)
		            let other: any Service = service.instance
		            #sourceLocation()
		            return Second(other: other)
		        }
		        let second: Second = __safeDI_second()
		        self.init(first: first, second: second)
		    }
		}

		extension Screen {
		    public enum __safeDI_Screen_6C3D8B09996784A6 {}
		}
		""")
		let inlineOutput = try await executeSafeDIToolTest(swiftFileContent: inlineFixture(files), buildSwiftOutputDirectory: true, filesToDelete: &filesToDelete)
		try await expectSeamBuildsInlineValues(of: files, seamOutput: output, inlineOutput: inlineOutput, filesToDelete: &filesToDelete)
	}

	/// How `First` and `Second` spell the value they receive: one with `any`, the other without.
	enum SeamReceiverSpellings: CaseIterable, CustomTestStringConvertible {
		case firstSpellsAny
		case secondSpellsAny

		/// How `First` spells the value.
		var first: String {
			switch self {
			case .firstSpellsAny:
				"any Service"
			case .secondSpellsAny:
				"Service"
			}
		}

		/// How `Second` spells the value.
		var second: String {
			switch self {
			case .firstSpellsAny:
				"Service"
			case .secondSpellsAny:
				"any Service"
			}
		}

		/// How `Second` spells the optional value.
		var secondOptional: String {
			second.hasPrefix("any ") ? "(\(second))?" : "\(second)?"
		}

		var testDescription: String {
			switch self {
			case .firstSpellsAny:
				"first receiver spells any"
			case .secondSpellsAny:
				"second receiver spells any"
			}
		}
	}

	// MARK: Private

	private var filesToDelete: [URL]
}
