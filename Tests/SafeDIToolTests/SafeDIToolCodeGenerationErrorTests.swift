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

import ArgumentParser
import Foundation
import SafeDICore
import Testing
@testable import SafeDITool

struct SafeDIToolCodeGenerationErrorTests: ~Copyable {
	// MARK: Initialization

	init() throws {
		filesToDelete = [URL]()
	}

	deinit {
		for fileToDelete in filesToDelete {
			try! FileManager.default.removeItem(at: fileToDelete)
		}
	}

	// MARK: Error Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithPropertyWithUnknownFulfilledType_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["RootViewController.swift"]):5:5: error: No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `DoesNotExist`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated(fulfilledByType: "DoesNotExist")
					    let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithPropertyWithUnknownTypeWithDotSuffixOfFulfillableType_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grandchild.swift"]):6:5: error: @Received property `value: NestedType` is not @Instantiated or @Forwarded in chain: Root -> Instantiator<Child> -> Grandchild. Did you mean `value: Grandchild.NestedType`?
				\(fixtures["Grandchild.swift"]):6:26-6:36: fixit: Grandchild.NestedType
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childBuilder: Instantiator<Child>
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Forwarded let value: Grandchild.NestedType
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Grandchild: Instantiable {
					    public struct NestedType {}
					    @Received let value: NestedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithPropertyWithUnknownTypeWithDotPrefixOfFulfillableType_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grandchild.swift"]):5:5: error: @Received property `value: Root.NestedType` is not @Instantiated or @Forwarded in chain: Root -> Instantiator<Child> -> Grandchild. Did you mean `value: NestedType`?
				\(fixtures["Grandchild.swift"]):5:26-5:41: fixit: NestedType
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childBuilder: Instantiator<Child>
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    public struct NestedType {}
					    @Forwarded let value: NestedType
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Grandchild: Instantiable {
					    @Received let value: Root.NestedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleInstantiateMethodsForTheSameTypeWithSameParameters_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File_2.swift"]):1:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `Container<Int>`
				\(fixtures["File_3.swift"]):1:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `Container<Int>`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					extension Container: Instantiable {}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleInstantiateMethodsForTheSameTypeWithDifferentParameters_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File_2.swift"]):1:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `Container<Int>`
				\(fixtures["File_3.swift"]):1:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `Container<Int>`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					extension Container: Instantiable {}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate() -> Container<Int> {
					        .init(0)
					    }
					}
					""",
					"""
					@Instantiable(conformsElsewhere: true)
					extension Array {
					    public static func instantiate(intValue: Int) -> Container<Int> {
					        .init(intValue)
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableInstantiatedProperty_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultNetworkService.swift"]):7:5: error: No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `URLSession`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    @Instantiated let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedProperty_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultNetworkService.swift"]):7:5: error: @Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain: RootViewController -> DefaultNetworkService. Declare `@Instantiated let urlSession: URLSession` on `RootViewController` or on another type in the chain to fix.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    @Received let urlSession: URLSession // URLSession is not `@Instantiable`! This will fail!
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToUnexpectedAny_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `erasedType: any ErasedType` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `erasedType: ErasedType`?
				\(fixtures["Child.swift"]):5:31-5:45: fixit: ErasedType
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated(fulfilledByType: "SomeErasedType") let erasedType: ErasedType
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					public protocol ErasedType {}

					@Instantiable
					public final class SomeErasedType: ErasedType, Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let erasedType: any ErasedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToDroppedAny_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `erasedType: ErasedType` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `erasedType: any ErasedType`?
				\(fixtures["Child.swift"]):5:31-5:41: fixit: any ErasedType
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated(fulfilledByType: "SomeErasedType") let erasedType: any ErasedType
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					public protocol ErasedType {}

					@Instantiable
					public final class SomeErasedType: ErasedType, Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let erasedType: ErasedType
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToUnexpectedForceUnwrap_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `thing: Thing!` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `thing: Thing`?
				\(fixtures["Child.swift"]):5:26-5:32: fixit: Thing
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing!
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToDroppedForceUnwrap_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `thing: Thing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `thing: Thing!`?
				\(fixtures["Child.swift"]):5:26-5:31: fixit: Thing!
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing!
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToUnexpectedOptional_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `thing: Thing?` is not @Instantiated or @Forwarded in chain: Root -> Child. The non-optional `thing: Thing` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
				\(fixtures["Child.swift"]):5:5-5:14: fixit: @Received(onlyIfAvailable: true)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToDroppedOptional_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `thing: Thing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `thing: Thing?`?
				\(fixtures["Child.swift"]):5:26-5:31: fixit: Thing?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing?
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: Thing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToIncorrectType_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `thing: OtherThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `thing: Thing`?
				\(fixtures["Child.swift"]):5:26-5:36: fixit: Thing
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}

					@Instantiable
					public final class OtherThing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: OtherThing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToIncorrectTypeOrLabel_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `thing: OtherThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean one of `otherThing: OtherThing`, `thing: Thing`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let thing: Thing
					    @Instantiated let otherThing: OtherThing
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Thing: Instantiable {}

					@Instantiable
					public final class OtherThing: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let thing: OtherThing
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithInstantiatedPropertyWithForwardedArgument_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["RootViewController.swift"]):5:5: error: Property `networkService: NetworkService` on RootViewController has at least one @Forwarded property. Property should instead be of type `Instantiator<DefaultNetworkService>`.
				\(fixtures["DefaultNetworkService.swift"]):7:5: note: @Forwarded property `urlSession: URLSession` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    @Forwarded let urlSession: URLSession
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithInstantiatedPropertyWithForwardedArgumentOnSeveralTypes_throwsErrorForFirstTypeName() async {
		// Scopes were validated in the order of a set hashed by object identity, so which type's
		// property was reported changed from run to run. With fifty such types, reporting the
		// first type name by chance is unlikely.
		let parentNames = (0..<50).map { "Parent" + ($0 < 10 ? "0" : "") + "\($0)" }
		let parentFiles = parentNames.map { parentName in
			"""
			@Instantiable
			public struct \(parentName): Instantiable {
			    public init(child: Child) {
			        fatalError("SafeDI doesn't inspect the initializer body")
			    }

			    @Instantiated let child: Child
			}
			"""
		}
		let rootInitializerParameters = parentNames
			.map { "\($0.lowercased()): \($0)" }
			.joined(separator: ", ")
		let rootProperties = parentNames
			.map { "    @Instantiated let \($0.lowercased()): \($0)" }
			.joined(separator: "\n")
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Parent00.swift"]):7:5: error: Property `child: Child` on Parent00 has at least one @Forwarded property. Property should instead be of type `Instantiator<Child>`.
				\(fixtures["Child.swift"]):7:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(\(rootInitializerParameters)) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					\(rootProperties)
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let name: String
					}
					""",
				] + parentFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDiamondDependencyWhereAReceivedPropertyIsUnfulfillableOnOneBranch_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grandchild.swift"]):3:5: error: @Received property `blankie: Blankie` is not @Instantiated or @Forwarded in chain: Root -> ChildB -> Grandchild. Declare `@Instantiated let blankie: Blankie` on `Root` or on another type in the chain to fix.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childA: ChildA
					    @Instantiated let childB: ChildB
					}
					""",
					"""
					@Instantiable
					public final class ChildA: Instantiable {
					    @Instantiated let grandchild: Grandchild
					    @Instantiated let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class ChildB: Instantiable {
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					@Instantiable
					public final class Grandchild: Instantiable {
					    @Received let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class Blankie: Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDiamondDependencyWhereMultipleReceivedPropertiesAreUnfulfillableOnOneBranch_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grandchild.swift"]):3:5: error: @Received property `blankie: Blankie` is not @Instantiated or @Forwarded in chain: Root -> ChildB -> Grandchild. Declare `@Instantiated let blankie: Blankie` on `Root` or on another type in the chain to fix.
				\(fixtures["Grandchild.swift"]):4:5: error: @Received property `blankie2: Blankie` is not @Instantiated or @Forwarded in chain: Root -> ChildA -> Grandchild. Did you mean `blankie: Blankie`?
				\(fixtures["Grandchild.swift"]):4:19-4:27: fixit: blankie
				\(fixtures["Grandchild.swift"]):4:5: error: @Received property `blankie2: Blankie` is not @Instantiated or @Forwarded in chain: Root -> ChildB -> Grandchild. Declare `@Instantiated let blankie2: Blankie` on `Root` or on another type in the chain to fix.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let childA: ChildA
					    @Instantiated let childB: ChildB
					}
					""",
					"""
					@Instantiable
					public final class ChildA: Instantiable {
					    @Instantiated let grandchild: Grandchild
					    @Instantiated let blankie: Blankie
					}
					""",
					"""
					@Instantiable
					public final class ChildB: Instantiable {
					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					@Instantiable
					public final class Grandchild: Instantiable {
					    @Received let blankie: Blankie
					    @Received let blankie2: Blankie
					}
					""",
					"""
					@Instantiable
					public final class Blankie: Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithInstantiatedPropertyThatRefersToCurrentInstantiable_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultAuthService.swift"]):13:5: error: Dependency cycle detected: AuthService -> AuthService
				\(fixtures["DefaultAuthService.swift"]):5:1: note: `AuthService` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {
					    public init(username: String) {}
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User(username: username)
					    }

					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithReceivedPropertyThatRefersToCurrentInstantiable_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultAuthService.swift"]):13:5: error: Dependency received in same chain it is instantiated: @Instantiated authService: AuthService -> @Received authService: AuthService
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {
					    public init(username: String) {}
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User(username: username)
					    }

					    @Instantiated let networkService: NetworkService

					    @Received let authService: AuthService
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsReceivedCycleErrorFoundOnSecondVisit_whenFirstVisitStoppedAtAnUnrelatedReceivedCycle() async {
		// Walking Parent's received properties reaches Shared twice. The first visit arrives through
		// `alpha`, so Shared stops at its own `alpha` (a received cycle that does not involve `parent`)
		// before checking `parent`. The second visit arrives through `extra` and finds `parent`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Shared.swift"]):9:5: error: Dependency received in same chain it is instantiated: @Instantiated parent: Parent -> @Received extra: Extra -> @Received shared: Shared -> @Received parent: Parent
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(parent: Parent, alpha: Alpha, extra: Extra, shared: Shared) {
					        self.parent = parent
					        self.alpha = alpha
					        self.extra = extra
					        self.shared = shared
					    }

					    @Instantiated let parent: Parent
					    @Instantiated let alpha: Alpha
					    @Instantiated let extra: Extra
					    @Instantiated let shared: Shared
					}
					""",
					"""
					@Instantiable
					public struct Parent: Instantiable {
					    public init(alpha: Alpha, extra: Extra) {
					        self.alpha = alpha
					        self.extra = extra
					    }

					    @Received let alpha: Alpha
					    @Received let extra: Extra
					}
					""",
					"""
					@Instantiable
					public struct Alpha: Instantiable {
					    public init(shared: Shared) {
					        self.shared = shared
					    }

					    @Received let shared: Shared
					}
					""",
					"""
					@Instantiable
					public struct Extra: Instantiable {
					    public init(shared: Shared) {
					        self.shared = shared
					    }

					    @Received let shared: Shared
					}
					""",
					"""
					@Instantiable
					public struct Shared: Instantiable {
					    public init(alpha: Alpha, parent: Parent) {
					        self.alpha = alpha
					        self.parent = parent
					    }

					    @Received let alpha: Alpha
					    @Received let parent: Parent
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableAliasedReceivedPropertyName_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultAuthService.swift"]):11:5: error: @Received property `networkService2: NetworkService` is not @Instantiated or @Forwarded in chain: RootViewController -> DefaultAuthService. Did you mean `networkService: NetworkService`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User(username: username)
					    }

					    @Received(fulfilledByDependencyNamed: "networkService2", ofType: NetworkService.self) let networking: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableAliasedReceivedPropertyType_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultAuthService.swift"]):11:5: error: @Received property `networkService: NetworkService2` is not @Instantiated or @Forwarded in chain: RootViewController -> DefaultAuthService. Did you mean `networkService: NetworkService`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User(username: username)
					    }

					    @Received(fulfilledByDependencyNamed: "networkService", ofType: NetworkService2.self) let networking: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWhereAliasedReceivedPropertyRefersToCurrentInstantiable_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultAuthService.swift"]):13:5: error: Dependency received in same chain it is instantiated: @Instantiated authService: AuthService -> @Received authService: AuthService
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {
					    public init(username: String) {}
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User(username: username)
					    }

					    @Instantiated let networkService: NetworkService

					    @Received(fulfilledByDependencyNamed: "authService", ofType: AuthService.self) let renamedAuthService: AuthService
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, loggedInViewControllerBuilder: Instantiator<LoggedInViewController>) {
					        self.authService = authService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let authService: AuthService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithUnfulfillableReceivedPropertyOnExtendedInstantiatedType_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):5:29: error: @Received property `urlSession: URLSession` is not @Instantiated or @Forwarded in chain: RootViewController -> URLSessionWrapper. Declare `@Instantiated let urlSession: URLSession` on `RootViewController` or on another type in the chain to fix.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import URLSessionWrapper

					@Instantiable
					extension URLSessionWrapper: Instantiable {
					    public func instantiate(urlSession: URLSession) -> URLSessionWrapper {
					        URLSessionWrapper(urlSession)
					    }
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    @Instantiated let urlSessionWrapper: URLSessionWrapper
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNames_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["RootViewController.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				\(fixtures["RootViewController_2.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesWhereOneIsRoot_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["RootViewController.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				\(fixtures["RootViewController_2.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtension_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				\(fixtures["RootViewController.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable
					extension RootViewController: Instantiable {
					    public static func instantiate() -> RootViewController {
					        RootViewController()
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtensionWhereDeclarationIsRoot_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				\(fixtures["RootViewController.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable
					extension RootViewController: Instantiable {
					    public static func instantiate() -> RootViewController {
					        RootViewController()
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaDeclarationAndExtensionWhereExtensionIsRoot_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				\(fixtures["RootViewController.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `RootViewController`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					extension RootViewController: Instantiable {
					    public static func instantiate() -> RootViewController {
					        RootViewController()
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableNamesViaExtension_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["File.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `UserDefaults`
				\(fixtures["File_2.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `UserDefaults`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import Foundation

					@Instantiable
					extension UserDefaults: Instantiable {
					    public static func instantiate() -> UserDefaults {
					        .standard
					    }
					}
					""",
					"""
					import Foundation

					@Instantiable
					extension UserDefaults: Instantiable {
					    public static func instantiate(suiteName: String) -> UserDefaults {
					        UserDefaults(suiteName: suiteName)
					    }
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithDuplicateInstantiableFulfillment_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["RootViewController.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `UIViewController`
				\(fixtures["SplashViewController.swift"]):3:1: error: @Instantiable-decorated types and extensions must have globally unique type names and fulfill globally unique types. Found multiple types or extensions fulfilling `UIViewController`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import UIKit

					@Instantiable(isRoot: true, fulfillingAdditionalTypes: [UIViewController.self])
					public final class RootViewController: UIViewController, Instantiable {}
					""",
					"""
					import UIKit

					@Instantiable(fulfillingAdditionalTypes: [UIViewController.self])
					public final class SplashViewController: UIViewController, Instantiable {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitialized_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):3:5: error: Dependency cycle detected: A -> B -> C -> A
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    @Instantiated let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedWithMixOfReceivedAndInstantiated_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):14:2: error: Dependency cycle detected: A -> C -> B -> A
				\(fixtures["Root.swift"]):7:1: note: `A` is part of the cycle
				\(fixtures["Root.swift"]):17:1: note: `C` is part of the cycle
				\(fixtures["Root.swift"]):12:1: note: `B` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
						@Instantiated public let a: A // A -> C -> Received B
						@Instantiated public let b: B // B -> Received A
					}

					@Instantiable
					public final class A: Instantiable {
						@Instantiated let c: C
					}

					@Instantiable
					public final class B: Instantiable {
						@Received public let a: A
					}

					@Instantiable
					public final class C: Instantiable {
						@Received public let b: B
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedAndReceived_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):3:5: error: Dependency cycle detected: A -> B -> C -> A
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    @Received let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesLazyInitializedAndReceived_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):3:5: error: Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received `aBuilder: Instantiator<A>` on `C` as @Instantiated to fix. Full cycle: Instantiator<A> -> Instantiator<B> -> Instantiator<C> -> Instantiator<A>
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received let aBuilder: Instantiator<A>
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesLazyInitializedAndOnlyIfAvailableReceived_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):3:5: error: Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>?` is @Received in tree created by @Instantiated `aBuilder: Instantiator<A>?`. Declare @Received `aBuilder: Instantiator<A>?` on `C` as @Instantiated to fix. Full cycle: Instantiator<A>? -> Instantiator<B> -> Instantiator<C> -> Instantiator<A>?
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated let aBuilder: Instantiator<A>?
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received(onlyIfAvailable: true) let aBuilder: Instantiator<A>?
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularPropertyDependenciesImmediatelyInitializedWithVaryingNames_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):3:5: error: Dependency cycle detected: B -> C -> A -> B
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Instantiated let a2: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularReceivedDependencies_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):3:5: error: Dependency received in same chain it is instantiated: @Instantiated a: A -> @Received b: B -> @Received c: C -> @Received a: A
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated private let a: A
					    @Instantiated private let b: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Received private let b: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received private let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithCircularReceivedRenamedDependencies_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):3:5: error: Dependency received in same chain it is instantiated: @Instantiated a: A -> @Received renamedB: B -> @Received c: C -> @Received a: A
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated private let a: A
					    @Instantiated private let b: B
					    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) private let renamedB: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Received private let renamedB: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received private let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleCircularReceivedRenamedDependencies_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):3:5: error: Dependency received in same chain it is instantiated: @Instantiated c: C -> @Received renamedB: B -> @Received c: C
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    @Instantiated private let a: A
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    @Instantiated private let b: B
					    @Received(fulfilledByDependencyNamed: "b", ofType: B.self) private let renamedB: B
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    @Received private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    @Received private let renamedB: B
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithOptionalPropertyAliasAndMarkedOnlyIfAvailableAndItIsOnlyAvailableViaCircularDependency_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):7:2: error: Dependency cycle detected: C -> B -> C
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
						public init(aBuilder: Instantiator<A>) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
						public init(c: C) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let c: C
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
						public init(cRenamed: CRenamed?) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Received(fulfilledByDependencyNamed: "c", ofType: C.self, onlyIfAvailable: true) let cRenamed: CRenamed?
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
						public init(b: B) {
							fatalError("SafeDI doesn't inspect the initializer body")
						}

						@Instantiated let b: B
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasSingleForwardedProperty_throwsError() async {
		await assertThrowsError(
			"""
			Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>`.
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User()
					    }

					    @Received let networkService: NetworkService
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>) {
					        self.authService = authService
					        self.networkService = networkService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        derivedValue = false
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService

					    @Instantiated(fulfilledByType: "LoggedInViewController")
					    let loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>

					    private let derivedValue: Bool

					    func login(username: String, password: String) {
					        Task { @MainActor in
					            let loggedInViewController = loggedInViewControllerBuilder.instantiate(username)
					            pushViewController(loggedInViewController)
					        }
					    }
					}
					""",
					"""
					import UIKit

					@Instantiable
					public final class LoggedInViewController: UIViewController, Instantiable {
					    @Forwarded private let user: User

					    @Received let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_whenInstantiableHasMultipleForwardedProperty_throwsError() async {
		await assertThrowsError(
			"""
			Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<LoggedInViewController.ForwardedProperties, UIViewController>`.
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					public struct User {}
					""",
					"""
					public protocol AuthService {
					    func login(username: String, password: String) async -> User
					}

					@Instantiable(fulfillingAdditionalTypes: [AuthService.self])
					public final class DefaultAuthService: AuthService, Instantiable {
					    public func login(username: String, password: String) async -> User {
					        User()
					    }

					    @Received let networkService: NetworkService
					}
					""",
					"""
					public protocol NetworkService {}

					@Instantiable(fulfillingAdditionalTypes: [NetworkService.self])
					public final class DefaultNetworkService: NetworkService, Instantiable {
					    public init() {}
					}
					""",
					"""
					import UIKit

					@Instantiable(isRoot: true)
					public final class RootViewController: UIViewController, Instantiable {
					    public init(authService: AuthService, networkService: NetworkService, loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>) {
					        self.authService = authService
					        self.networkService = networkService
					        self.loggedInViewControllerBuilder = loggedInViewControllerBuilder
					        derivedValue = false
					        super.init(nibName: nil, bundle: nil)
					    }

					    @Instantiated let networkService: NetworkService

					    @Instantiated let authService: AuthService

					    @Instantiated(fulfilledByType: "LoggedInViewController")
					    let loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>

					    private let derivedValue: Bool

					    func login(username: String, password: String) {
					        Task { @MainActor in
					            let loggedInViewController = loggedInViewControllerBuilder.instantiate(username)
					            pushViewController(loggedInViewController)
					        }
					    }
					}
					""",
					"""
					import UIKit

					@Instantiable
					public final class LoggedInViewController: UIViewController, Instantiable {
					    @Forwarded private let user: User

					    @Forwarded private let userManager: UserManager

					    @Received let networkService: NetworkService
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Argument handling error tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func include_throwsErrorWhenCanNotCreateEnumerator() async throws {
		final class FailingFileFinder: FileFinder {
			func enumerator(
				at _: URL,
				includingPropertiesForKeys _: [URLResourceKey]?,
				options _: FileManager.DirectoryEnumerationOptions,
				errorHandler _: ((URL, any Error) -> Bool)?,
			) -> FileManager.DirectoryEnumerator? {
				nil
			}
		}
		let tool = try Generate.parse(["--include", "Fake"])
		await SafeDITool.$fileFinder.withValue(FailingFileFinder()) {
			await assertThrowsError("Could not create file enumerator for directory 'Fake'") {
				let mutableTool = tool
				try await mutableTool.run()
			}
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func include_throwsErrorWhenNoSwiftSourcesFilePathAndNoInclude() async throws {
		let tool = try Generate.parse([])
		await assertThrowsError("Must provide 'swift-sources-file-path' or '--include'.") {
			try await tool.run()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	func generate_throwsError_whenOutputDirectoryProvidedWithoutCSV() async throws {
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		let tool = try Generate.parse([
			"--include", "SomeDir",
			"--output-directory", outputDirectory.path,
		])
		await assertThrowsError("--output-directory requires 'swift-sources-file-path'.") {
			try await tool.run()
		}
	}

	// MARK: Manifest Validation Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesFileWithoutCode_whenManifestListsFileThatDoesNotContainRoot() async throws {
		// The build system expects every output the manifest lists, so a listed file without a root,
		// such as one whose root is in an inactive `#if` clause, still gets a file.
		let swiftFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
		try """
		@Instantiable
		public struct NotRoot: Instantiable {
		    public init() {}
		}
		""".write(to: swiftFile, atomically: true, encoding: .utf8)
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try swiftFile.relativePath.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		let outputFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
		let manifest = SafeDIToolManifest(dependencyTreeGeneration: [.init(inputFilePath: swiftFile.relativePath, outputFilePath: outputFile.relativePath)])
		try JSONEncoder().encode(manifest).write(to: manifestFile)
		let moduleInfoOutput = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".safedi")

		filesToDelete += [swiftFileCSV, swiftFile, manifestFile, outputFile, moduleInfoOutput]

		let tool = try Generate.parse([
			swiftFileCSV.relativePath,
			"--module-info-output", moduleInfoOutput.relativePath,
			"--swift-manifest", manifestFile.relativePath,
		])
		try await tool.run()

		#expect(try String(contentsOf: outputFile, encoding: .utf8) == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		""" + "\n")
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenRootExistsButNotInManifest() async throws {
		let swiftFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
		try """
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init(dep: Dep) { self.dep = dep }
		    @Instantiated let dep: Dep
		}
		@Instantiable
		public struct Dep: Instantiable {
		    public init() {}
		}
		""".write(to: swiftFile, atomically: true, encoding: .utf8)
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try swiftFile.relativePath.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		let manifest = SafeDIToolManifest(dependencyTreeGeneration: [])
		try JSONEncoder().encode(manifest).write(to: manifestFile)
		let moduleInfoOutput = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".safedi")

		filesToDelete += [swiftFileCSV, swiftFile, manifestFile, moduleInfoOutput]

		await assertThrowsError(
			"Found @Instantiable(isRoot: true) in '\(swiftFile.relativePath)', but this file is not listed in the manifest’s dependencyTreeGeneration. SafeDI decides which files to generate before the build runs, listing every file that declares a root, a type that sets `generateMock: true`, or a #SafeDIConfiguration in any clause of its `#if` blocks, so the file most likely changed after that decision; building again lists it. A hand-written manifest must list the file, or the type must not be a root.",
		) {
			let tool = try Generate.parse([
				swiftFileCSV.relativePath,
				"--module-info-output", moduleInfoOutput.relativePath,
				"--swift-manifest", manifestFile.relativePath,
			])
			try await tool.run()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenMockGeneratingTypeExistsButNotInManifest() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		@Instantiable(generateMock: true)
		public struct Service: Instantiable {
		    public init() {}
		}
		""")

		await assertThrowsError(
			"Found @Instantiable(generateMock: true) on `Service` in '\(swiftFile.relativePath)', but this file is not listed in the manifest’s mockGeneration. \(Self.manifestPlanningExplanation) A hand-written manifest must list the file, or the type must not set `generateMock: true`.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [],
				mockScopedFilePaths: [swiftFile.relativePath],
			))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenConfigurationExistsButNotInManifest() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		#SafeDIConfiguration()
		""")

		await assertThrowsError(
			"Found #SafeDIConfiguration in '\(swiftFile.relativePath)', but this file is not listed in the manifest’s configurationFilePaths. \(Self.manifestPlanningExplanation) A hand-written manifest must list the file.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [],
				mockScopedFilePaths: [swiftFile.relativePath],
			))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenConfiguredAdditionalMockIsNotInManifest() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		#SafeDIConfiguration(additionalMocksToGenerate: ["Service"])
		""")

		await assertThrowsError(
			"The #SafeDIConfiguration lists `Service` in additionalMocksToGenerate, but the manifest’s additionalMocksToGenerate does not. \(Self.manifestPlanningExplanation) A hand-written manifest must list the type in additionalMocksToGenerate and mockGeneration.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [],
				configurationFilePaths: [swiftFile.relativePath],
				mockScopedFilePaths: [swiftFile.relativePath],
			))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithMultipleSafeDIConfigurations_throwsError() async {
		do {
			_ = try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					#SafeDIConfiguration()
					""",
					"""
					#SafeDIConfiguration(
					    mockConditionalCompilation: nil
					)
					""",
					"""
					@Instantiable
					public struct SimpleType: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
			Issue.record("Did not throw error!")
		} catch {
			let errorMessage = "\(error)"
			#expect(errorMessage.hasPrefix("Found 2 #SafeDIConfiguration declarations in this module. Each module must have at most one #SafeDIConfiguration. Found in:"))
			#expect(errorMessage.contains("File.swift"))
			#expect(errorMessage.contains("File_2.swift"))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenPartiallyLazyInstantiationCycleExists() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):7:5: error: Dependency cycle detected. Cycles with a mix of constant and lazy (Instantiator) dependencies cannot be resolved. Make all dependencies in the cycle lazy by using Instantiator: A -> B -> Instantiator<C> -> A
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(a: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(b: B) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let b: B
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(cBuilder: Instantiator<C>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    public init(a: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Diagnostic Format Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsFailureExitCode_whenGenerationThrowsSourceLocatedError() async throws {
		// `run()` prints located errors in compiler format and replaces them with an `ExitCode`
		// so ArgumentParser exits non-zero without printing an `Error:`-prefixed copy.
		let fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
		filesToDelete.append(fixtureDirectory)
		let firstFile = fixtureDirectory.appendingPathComponent("First.swift")
		let secondFile = fixtureDirectory.appendingPathComponent("Second.swift")
		for file in [firstFile, secondFile] {
			try """
			@Instantiable
			public struct Service: Instantiable {
			    public init() {}
			}
			""".write(to: file, atomically: true, encoding: .utf8)
		}
		let swiftFileCSV = fixtureDirectory.appendingPathComponent("InputSwiftFiles.csv")
		try "\(firstFile.path),\(secondFile.path)".write(to: swiftFileCSV, atomically: true, encoding: .utf8)

		let tool = try Generate.parse([swiftFileCSV.path])
		await #expect(throws: ExitCode.failure) {
			try await tool.run()
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_namesRootOfChainInFixHint_whenUnfulfillableReceivedPropertyHasNoSuggestedAlternatives() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grandchild.swift"]):7:5: error: @Received property `missing: Missing` is not @Instantiated or @Forwarded in chain: Root -> Child -> Grandchild. Declare `@Instantiated let missing: Missing` on `Root` or on another type in the chain to fix.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(grandchild: Grandchild) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let grandchild: Grandchild
					}
					""",
					"""
					@Instantiable
					public struct Grandchild: Instantiable {
					    public init(missing: Missing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let missing: Missing
					}

					public struct Missing {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_reportsErrorAtEveryReferencingDeclaration_whenNoInstantiableFound() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `Missing`
				\(fixtures["Root.swift"]):7:5: error: No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `Missing`
				\(fixtures["Root.swift"]):9:5: error: No `@Instantiable`-decorated type or extension found to fulfill `@Instantiated`-decorated property with type `Missing`
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(missing: Missing, child: Child, otherMissing: Missing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let missing: Missing
					    @Instantiated let child: Child
					    @Instantiated let otherMissing: Missing
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(missing: Missing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let missing: Missing
					}

					public struct Missing {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_omitsCycleMemberNote_whenCycleMemberPropertyTypeIsNotAnInstantiableType() async {
		// `b: BProtocol` is fulfilled by `B` via `fulfilledByType`, but `B` does not declare that it fulfills
		// `BProtocol`, so no `@Instantiable` is registered for the property's type and no note can point at it.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):7:5: error: Dependency cycle detected: A -> BProtocol -> A
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(a: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let a: A
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(b: BProtocol) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "B") let b: BProtocol
					}

					public protocol BProtocol {}
					""",
					"""
					@Instantiable
					public struct B: Instantiable, BProtocol {
					    public init(a: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let a: A
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Fix-It Tests

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersFixItRenamingProperty_whenUnfulfillableReceivedPropertyHasOneSuggestionOfSameType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: @Received property `shared2: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?
				\(fixtures["Child.swift"]):7:19-7:26: fixit: shared
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(shared: SharedThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: SharedThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(shared2: SharedThing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let shared2: SharedThing
					}
					""",
					"""
					@Instantiable
					public struct SharedThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersFixItRenamingParameter_whenUnfulfillableInstantiateParameterHasOneSuggestionOfSameType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):3:36: error: @Received property `shared2: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?
				\(fixtures["Child.swift"]):3:36-3:43: fixit: shared
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(shared: SharedThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: SharedThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					extension Child: Instantiable {
					    public static func instantiate(shared2: SharedThing) -> Child {
					        Child(shared: shared2)
					    }
					}

					public struct Child {
					    public init(shared: SharedThing) {}
					}
					""",
					"""
					@Instantiable
					public struct SharedThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersFixItRenamingParameterInnerName_whenUnfulfillableInstantiateParameterHasAnOuterLabel() async {
		// The dependency's label is the parameter's inner name, so that is what the fix-it renames.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):3:36: error: @Received property `shared3: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?
				\(fixtures["Child.swift"]):3:44-3:51: fixit: shared
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(shared: SharedThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: SharedThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					extension Child: Instantiable {
					    public static func instantiate(shared2 shared3: SharedThing) -> Child {
					        Child(shared: shared3)
					    }
					}

					public struct Child {
					    public init(shared: SharedThing) {}
					}
					""",
					"""
					@Instantiable
					public struct SharedThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersNoFixIt_whenUnfulfillableReceivedPropertyHasSeveralSuggestionsOfSameType() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: @Received property `shared2: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean one of `sharedA: SharedThing`, `sharedB: SharedThing`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(sharedA: SharedThing, sharedB: SharedThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let sharedA: SharedThing
					    @Instantiated let sharedB: SharedThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(shared2: SharedThing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let shared2: SharedThing
					}
					""",
					"""
					@Instantiable
					public struct SharedThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersFixItRetypingProperty_whenUnfulfillableReceivedPropertyHasOneSuggestionOfSameLabel() async {
		// The suggestion shares the property's label, so renaming the identifier would change nothing; the
		// fix-it rewrites the type annotation instead.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: @Received property `shared: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: OtherThing`?
				\(fixtures["Child.swift"]):7:27-7:38: fixit: OtherThing
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(shared: OtherThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: OtherThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(shared: SharedThing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let shared: SharedThing
					}

					public struct SharedThing {}
					""",
					"""
					@Instantiable
					public struct OtherThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersNoFixIt_whenUnfulfillableReceivedPropertyTypeIsModuleQualified() async {
		// The suggester matches on the least-qualified type, so `shared: SharedThing` is suggested, but
		// normalization does not unify `SharedModule.SharedThing` with `SharedThing`: label and type both
		// differ, so neither the rename nor the retype alone would fulfill the property, and no fix-it is offered.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: @Received property `shared2: SharedModule.SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: SharedThing`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(shared: SharedThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: SharedThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(shared2: SharedModule.SharedThing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let shared2: SharedModule.SharedThing
					}
					""",
					"""
					@Instantiable
					public struct SharedThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersFixItRetypingParameter_whenUnfulfillableInstantiateParameterHasOneSuggestionOfSameLabel() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):3:36: error: @Received property `shared: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `shared: OtherThing`?
				\(fixtures["Child.swift"]):3:44-3:55: fixit: OtherThing
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(shared: OtherThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: OtherThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					extension Child: Instantiable {
					    public static func instantiate(shared: SharedThing) -> Child {
					        Child(shared: shared)
					    }
					}

					public struct Child {
					    public init(shared: SharedThing) {}
					}

					public struct SharedThing {}
					""",
					"""
					@Instantiable
					public struct OtherThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersNoFixIt_whenUnfulfillableReceivedPropertyHasSuggestionsOfSameLabelAndOfSameType() async {
		// Renaming to `sharedThing` and retyping to `OtherThing` would each fulfill the property, so the choice is
		// left to the user.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: @Received property `shared: SharedThing` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean one of `shared: OtherThing`, `sharedThing: SharedThing`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(shared: OtherThing, sharedThing: SharedThing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let shared: OtherThing
					    @Instantiated let sharedThing: SharedThing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(shared: SharedThing) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let shared: SharedThing
					}
					""",
					"""
					@Instantiable
					public struct SharedThing: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct OtherThing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersFixItAddingOnlyIfAvailable_whenUnfulfillableOptionalReceivedPropertyHasNonOptionalSuggestionAmongSeveral() async {
		// The `onlyIfAvailable` hint names a single repair however many near-matches exist, so its fix-it is
		// offered even though several suggestions are found.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: @Received property `thing: Thing?` is not @Instantiated or @Forwarded in chain: Root -> Child. The non-optional `thing: Thing` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
				\(fixtures["Child.swift"]):7:5-7:14: fixit: @Received(onlyIfAvailable: true)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(thing: Thing, otherThing: Thing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let thing: Thing
					    @Instantiated let otherThing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(thing: Thing?) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let thing: Thing?
					}
					""",
					"""
					@Instantiable
					public struct Thing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_offersNoFixIt_whenOnlyIfAvailableSuggestionArisesOnReceivedAttributeWithArguments() async {
		// Only a bare `@Received` is rewritten, so the fix-it never discards arguments the user wrote.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):7:5: error: @Received property `thing: Thing?` is not @Instantiated or @Forwarded in chain: Root -> Child. The non-optional `thing: Thing` is available in chain. Did you mean to decorate this property with `@Received(onlyIfAvailable: true)`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(thing: Thing, child: Child) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated let thing: Thing
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public struct Child: Instantiable {
					    public init(thing: Thing?) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received(onlyIfAvailable: false) let thing: Thing?
					}
					""",
					"""
					@Instantiable
					public struct Thing: Instantiable {
					    public init() {}
					}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	// MARK: Private

	private var filesToDelete = [URL]()

	private static let manifestPlanningExplanation = "SafeDI decides which files to generate before the build runs, listing every file that declares a root, a type that sets `generateMock: true`, or a #SafeDIConfiguration in any clause of its `#if` blocks, so the file most likely changed after that decision; building again lists it."

	/// A new Swift file holding `content`, which the test deletes.
	private mutating func writeTemporarySwiftFile(_ content: String) throws -> URL {
		let swiftFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".swift")
		try content.write(to: swiftFile, atomically: true, encoding: .utf8)
		filesToDelete.append(swiftFile)
		return swiftFile
	}

	/// Runs `generate` on `swiftFile` with the hand-written `manifest`.
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	private mutating func generate(_ swiftFile: URL, manifest: SafeDIToolManifest) async throws {
		let swiftFileCSV = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try swiftFile.relativePath.write(to: swiftFileCSV, atomically: true, encoding: .utf8)
		let manifestFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".json")
		try JSONEncoder().encode(manifest).write(to: manifestFile)
		filesToDelete += [swiftFileCSV, manifestFile]

		try await Generate.parse([
			swiftFileCSV.relativePath,
			"--swift-manifest", manifestFile.relativePath,
		]).run()
	}
}
