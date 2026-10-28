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
	mutating func run_onCodeWithUnfulfillableReceivedPropertyDueToUnexpectedSome_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `erasedType: some ErasedType` is not @Instantiated or @Forwarded in chain: Root -> Child. Did you mean `erasedType: ErasedType`?
				\(fixtures["Child.swift"]):5:31-5:46: fixit: ErasedType
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
					    @Received let erasedType: some ErasedType
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
	mutating func run_onCodeWithReceivedPropertyHiddenByAliasReusingItsLabel_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `analytics: Analytics` is hidden in chain: Root -> Mid -> Child. `Mid` declares `analytics: EventTracker` with the same label, so the types below `Mid` receive `analytics: EventTracker` instead. Give `analytics: EventTracker` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):5:5: note: `analytics: EventTracker` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let analytics: Analytics
					    @Instantiated let mid: Mid
					}
					""",
					"""
					import SafeDI

					public protocol EventTracker {}

					@Instantiable
					public final class Analytics: Instantiable, EventTracker {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Mid: Instantiable {
					    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let analytics: EventTracker
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let analytics: Analytics
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
	mutating func run_onCodeWithReceivedPropertiesHiddenByAliasReusingTheirLabel_throwsErrorForEachInSourceOrder() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `analytics: Analytics` is hidden in chain: Root -> Mid -> Child. `Mid` declares `analytics: EventTracker` with the same label, so the types below `Mid` receive `analytics: EventTracker` instead. Give `analytics: EventTracker` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):5:5: note: `analytics: EventTracker` is declared here
				\(fixtures["Sibling.swift"]):5:5: error: @Received property `analytics: Analytics` is hidden in chain: Root -> Mid -> Sibling. `Mid` declares `analytics: EventTracker` with the same label, so the types below `Mid` receive `analytics: EventTracker` instead. Give `analytics: EventTracker` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):5:5: note: `analytics: EventTracker` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let analytics: Analytics
					    @Instantiated let mid: Mid
					}
					""",
					"""
					import SafeDI

					public protocol EventTracker {}

					@Instantiable
					public final class Analytics: Instantiable, EventTracker {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Mid: Instantiable {
					    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let analytics: EventTracker
					    @Instantiated let sibling: Sibling
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Sibling: Instantiable {
					    @Received let analytics: Analytics
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let analytics: Analytics
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
	mutating func run_onCodeWithOnlyIfAvailableReceivedPropertyHiddenByAliasReusingItsLabel_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `analytics: Analytics?` is hidden in chain: Root -> Mid -> Child. `Mid` declares `analytics: EventTracker` with the same label, so the types below `Mid` receive `analytics: EventTracker` instead. Give `analytics: EventTracker` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):5:5: note: `analytics: EventTracker` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let analytics: Analytics
					    @Instantiated let mid: Mid
					}
					""",
					"""
					import SafeDI

					public protocol EventTracker {}

					@Instantiable
					public final class Analytics: Instantiable, EventTracker {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Mid: Instantiable {
					    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let analytics: EventTracker
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received(onlyIfAvailable: true) let analytics: Analytics?
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
	mutating func run_onCodeWithAliasedReceivedPropertyHiddenByAliasReusingItsLabel_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `analytics: Analytics` is hidden in chain: Root -> Instantiator<Mid> -> Child. `Mid` declares `analytics: EventTracker` with the same label, so the types below `Mid` receive `analytics: EventTracker` instead. Give `analytics: EventTracker` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):5:5: note: `analytics: EventTracker` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let analytics: Analytics
					    @Instantiated let midBuilder: Instantiator<Mid>
					}
					""",
					"""
					import SafeDI

					public protocol EventTracker {}
					public protocol CrashReporter {}

					@Instantiable
					public final class Analytics: Instantiable, EventTracker, CrashReporter {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Mid: Instantiable {
					    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let analytics: EventTracker
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received(fulfilledByDependencyNamed: "analytics", ofType: Analytics.self) let crashReporter: CrashReporter
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
	mutating func run_onCodeWithReceivedPropertyHiddenByInstantiatedPropertyWithSameLabel_throwsError() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):5:5: error: @Received property `analytics: Analytics` is hidden in chain: Root -> Mid -> Inner -> Child. `Mid` declares `analytics: OtherAnalytics` with the same label, so the types below `Mid` receive `analytics: OtherAnalytics` instead. Give `analytics: OtherAnalytics` on `Mid` a different label to fix.
				\(fixtures["Mid.swift"]):5:5: note: `analytics: OtherAnalytics` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					import SafeDI

					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    @Instantiated let analytics: Analytics
					    @Instantiated let mid: Mid
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Analytics: Instantiable {}

					@Instantiable
					public final class OtherAnalytics: Instantiable {}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Mid: Instantiable {
					    @Instantiated let analytics: OtherAnalytics
					    @Instantiated let inner: Inner
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Inner: Instantiable {
					    @Instantiated let child: Child
					}
					""",
					"""
					import SafeDI

					@Instantiable
					public final class Child: Instantiable {
					    @Received let analytics: Analytics
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
	mutating func run_throwsErrorSuggestingErasedInstantiator_whenErasedConstantTypeHasForwardedProperty() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):7:5: error: Property `child: AnyChild` on Root has at least one @Forwarded property. Property should instead be of type `ErasedInstantiator<String, AnyChild>`.
				\(fixtures["Child.swift"]):7:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: AnyChild) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let child: AnyChild
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let name: String
					}

					public final class AnyChild {
					    public init(_ child: Child) {}
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
	mutating func run_throwsErrorSuggestingErasedInstantiator_whenOptionalErasedConstantTypeHasForwardedProperty() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):7:5: error: Property `child: AnyChild?` on Root has at least one @Forwarded property. Property should instead be of type `ErasedInstantiator<String, AnyChild>`.
				\(fixtures["Child.swift"]):7:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: AnyChild?) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let child: AnyChild?
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let name: String
					}

					public final class AnyChild {
					    public init(_ child: Child) {}
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
	mutating func run_throwsErrorSuggestingErasedInstantiator_whenConstantFulfilledByTypeHasForwardedProperty() async {
		// `fulfilledByType` cannot be used on an `Instantiator`, so the suggestion is an `ErasedInstantiator`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):7:5: error: Property `child: any ChildProtocol` on Root has at least one @Forwarded property. Property should instead be of type `ErasedInstantiator<String, any ChildProtocol>`.
				\(fixtures["Child.swift"]):7:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: any ChildProtocol) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child") let child: any ChildProtocol
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable, ChildProtocol {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let name: String
					}

					public protocol ChildProtocol {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsErrorSuggestingErasedInstantiatorOfForwardedPropertiesTuple_whenErasedTypeHasMultipleForwardedProperties() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):7:5: error: Property `child: AnyChild` on Root has at least one @Forwarded property. Property should instead be of type `ErasedInstantiator<(name: String, title: String), AnyChild>`.
				\(fixtures["Child.swift"]):7:5: note: @Forwarded property `title: String` is declared here
				\(fixtures["Child.swift"]):8:5: note: @Forwarded property `name: String` is declared here
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: AnyChild) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let child: AnyChild
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(title: String, name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let title: String
					    @Forwarded let name: String
					}

					public final class AnyChild {
					    public init(_ child: Child) {}
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
	mutating func run_throwsReceivedCycleErrorFoundThroughSecondLabel_whenFirstLabelOfSameTypeStoppedAtAnUnrelatedReceivedCycle() async {
		// Walking Parent's received properties reaches Loop through `loop` and then through
		// `otherLoop`. The first visit stops at Gate's `loop` (a received cycle that does not
		// involve `parent`) before checking `parent`. The second visit enters the same Loop type
		// under another label, so Gate's `loop` is no longer on the stack and Gate goes on to find `parent`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Gate.swift"]):9:5: error: Dependency received in same chain it is instantiated: @Instantiated parent: Parent -> @Received otherLoop: Loop -> @Received gate: Gate -> @Received parent: Parent
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(parent: Parent, loop: Loop, otherLoop: Loop, gate: Gate) {
					        self.parent = parent
					        self.loop = loop
					        self.otherLoop = otherLoop
					        self.gate = gate
					    }

					    @Instantiated let parent: Parent
					    @Instantiated let loop: Loop
					    @Instantiated let otherLoop: Loop
					    @Instantiated let gate: Gate
					}
					""",
					"""
					@Instantiable
					public struct Parent: Instantiable {
					    public init(loop: Loop, otherLoop: Loop) {
					        self.loop = loop
					        self.otherLoop = otherLoop
					    }

					    @Received let loop: Loop
					    @Received let otherLoop: Loop
					}
					""",
					"""
					@Instantiable
					public struct Loop: Instantiable {
					    public init(gate: Gate) {
					        self.gate = gate
					    }

					    @Received let gate: Gate
					}
					""",
					"""
					@Instantiable
					public struct Gate: Instantiable {
					    public init(loop: Loop, parent: Parent) {
					        self.loop = loop
					        self.parent = parent
					    }

					    @Received let loop: Loop
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
	mutating func run_throwsReceivedCycleErrorFoundOnSecondVisit_whenFirstVisitReachedSharedOnlyAfterAnUnrelatedReceivedCycle() async {
		// Walking Parent's received properties reaches Relay twice. The first visit arrives through
		// `alpha`, where Shared has already stopped at its own `alpha` (a received cycle that does not
		// involve `parent`), so Relay's `shared` stops there too. The second visit arrives through
		// `extra`, with `alpha` no longer on the stack, so Shared goes on to find `parent`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Shared.swift"]):9:5: error: Dependency received in same chain it is instantiated: @Instantiated parent: Parent -> @Received extra: Extra -> @Received relay: Relay -> @Received shared: Shared -> @Received parent: Parent
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(parent: Parent, alpha: Alpha, extra: Extra, shared: Shared, relay: Relay) {
					        self.parent = parent
					        self.alpha = alpha
					        self.extra = extra
					        self.shared = shared
					        self.relay = relay
					    }

					    @Instantiated let parent: Parent
					    @Instantiated let alpha: Alpha
					    @Instantiated let extra: Extra
					    @Instantiated let shared: Shared
					    @Instantiated let relay: Relay
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
					    public init(shared: Shared, relay: Relay) {
					        self.shared = shared
					        self.relay = relay
					    }

					    @Received let shared: Shared
					    @Received let relay: Relay
					}
					""",
					"""
					@Instantiable
					public struct Extra: Instantiable {
					    public init(relay: Relay) {
					        self.relay = relay
					    }

					    @Received let relay: Relay
					}
					""",
					"""
					@Instantiable
					public struct Relay: Instantiable {
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

	// The time limit only turns a hang into a failure; see
	// `run_generatesCodeWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsReceivedCycleErrorWithinTimeLimit_whenEveryReceivedPathFromEarlierSiblingsEndsInReceivedCycle() async {
		// Each layer holds a Left and a Right service that both receive the two services of the
		// next layer, and the last layer's services receive Ping, which receives Pong, which receives
		// Ping. Validating any layer's service walks down to that cycle along every path, and the
		// number of paths doubles with each layer. Root instantiates Ping after every layer, so the
		// walk must remember what lies past the cycle to reach the error Ping reports.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["ping: Ping"]
				: ["left\(layer + 1): Left\(layer + 1)", "right\(layer + 1): Right\(layer + 1)"]
			return ["Left\(layer)", "Right\(layer)"].map { type in
				"""
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(receivedProperties.joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		let rootProperties = (0..<layerCount).flatMap { ["left\($0): Left\($0)", "right\($0): Right\($0)"] } + ["ping: Ping", "pong: Pong"]
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Pong.swift"]):7:5: error: Dependency received in same chain it is instantiated: @Instantiated ping: Ping -> @Received pong: Pong -> @Received ping: Ping
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(\(rootProperties.joined(separator: ", "))) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					\(rootProperties.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
					}
					""",
					"""
					@Instantiable
					public struct Ping: Instantiable {
					    public init(pong: Pong) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let pong: Pong
					}
					""",
					"""
					@Instantiable
					public struct Pong: Instantiable {
					    public init(ping: Ping) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let ping: Ping
					}
					""",
				] + layerFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
		}
	}

	// The time limit only turns a hang into a failure; see
	// `run_generatesCodeWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsReceivedCycleErrorWithinTimeLimit_whenEveryReceivedPathFromEarlierSiblingReturnsToItsFirstReceivedProperty() async {
		// Each layer holds a Left and a Right service that both receive the two services of the
		// next layer, and the last layer's services receive Ping, which receives `left0`. Validating
		// Entry, which receives `left0` and which Root instantiates first, walks every path through
		// the layers back to `left0`, and the number of paths doubles with each layer. Every service
		// past `left0` stops at `left0`, so the walk must remember that stop to reach the error
		// `left0` reports.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["ping: Ping"]
				: ["left\(layer + 1): Left\(layer + 1)", "right\(layer + 1): Right\(layer + 1)"]
			return ["Left\(layer)", "Right\(layer)"].map { type in
				"""
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(receivedProperties.joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		let rootProperties = ["entry: Entry"] + (0..<layerCount).flatMap { ["left\($0): Left\($0)", "right\($0): Right\($0)"] } + ["ping: Ping"]
		let receivedChain = (1..<layerCount).map { " -> @Received left\($0): Left\($0)" }.joined()
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Ping.swift"]):7:5: error: Dependency received in same chain it is instantiated: @Instantiated left0: Left0\(receivedChain) -> @Received ping: Ping -> @Received left0: Left0
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(\(rootProperties.joined(separator: ", "))) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					\(rootProperties.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
					}
					""",
					"""
					@Instantiable
					public struct Entry: Instantiable {
					    public init(left0: Left0) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let left0: Left0
					}
					""",
					"""
					@Instantiable
					public struct Ping: Instantiable {
					    public init(left0: Left0) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let left0: Left0
					}
					""",
				] + layerFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
		}
	}

	// The time limit only turns a hang into a failure; see
	// `run_generatesCodeWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsReceivedCycleErrorWithinTimeLimit_whenEveryReceivedInstantiatorPathFromEarlierSiblingsEndsInReceivedCycle() async {
		// Each layer holds a Left and a Right service that both receive Instantiators of the two
		// services of the next layer, and the last layer's services receive an Instantiator of Ping,
		// which receives one of Pong, which receives one of Ping. Root instantiates every Instantiator,
		// so the number of received paths from any layer to that cycle doubles with each layer.
		let layerCount = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["pingBuilder: Instantiator<Ping>"]
				: ["left\(layer + 1)Builder: Instantiator<Left\(layer + 1)>", "right\(layer + 1)Builder: Instantiator<Right\(layer + 1)>"]
			return ["Left\(layer)", "Right\(layer)"].map { type in
				"""
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(receivedProperties.joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		let rootProperties = (0..<layerCount).flatMap { ["left\($0)Builder: Instantiator<Left\($0)>", "right\($0)Builder: Instantiator<Right\($0)>"] } + ["pingBuilder: Instantiator<Ping>", "pongBuilder: Instantiator<Pong>"]
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Pong.swift"]):7:5: error: Dependency received in same chain it is instantiated: @Instantiated pingBuilder: Instantiator<Ping> -> @Received pongBuilder: Instantiator<Pong> -> @Received pingBuilder: Instantiator<Ping>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(\(rootProperties.joined(separator: ", "))) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					\(rootProperties.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
					}
					""",
					"""
					@Instantiable
					public struct Ping: Instantiable {
					    public init(pongBuilder: Instantiator<Pong>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let pongBuilder: Instantiator<Pong>
					}
					""",
					"""
					@Instantiable
					public struct Pong: Instantiable {
					    public init(pingBuilder: Instantiator<Ping>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let pingBuilder: Instantiator<Ping>
					}
					""",
				] + layerFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
			)
		}
	}

	// The time limit only turns a hang into a failure; see
	// `run_generatesCodeWithinTimeLimit_whenReceivedDependenciesFormDeepChainOfDiamonds`.
	@Test(.timeLimit(.minutes(10)))
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsReceivedCycleErrorWithinTimeLimit_whenEveryReceivedAliasPathFromEarlierSiblingsEndsInReceivedCycleOfLazyCycles() async {
		// Each layer holds a Left and a Right service that instantiate Instantiators of each other and
		// receive aliases, assigned through two other aliases, of the Instantiators of the two services of
		// the next layer. The last layer's services receive the last of a long chain of aliases of Ping's
		// Instantiator, and Ping and Pong receive aliases of each other's. Root declares every alias in
		// reverse order of assignment.
		let layerCount = 40
		let aliasChainLength = 40
		let layerFiles = (0..<layerCount).flatMap { layer in
			let receivedProperties = layer == layerCount - 1
				? ["pingAlias\(aliasChainLength - 1): Instantiator<Ping>"]
				: ["left\(layer + 1)Alias: Instantiator<Left\(layer + 1)>", "right\(layer + 1)Alias: Instantiator<Right\(layer + 1)>"]
			return [("Left\(layer)", "Right\(layer)"), ("Right\(layer)", "Left\(layer)")].map { type, otherType in
				let instantiatedProperty = "inner\(otherType)Builder: Instantiator<\(otherType)>"
				return """
				@Instantiable
				public struct \(type): Instantiable {
				    public init(\(([instantiatedProperty] + receivedProperties).joined(separator: ", "))) {
				        fatalError("SafeDI doesn't inspect the initializer body")
				    }

				    @Instantiated let \(instantiatedProperty)
				\(receivedProperties.map { "    @Received let \($0)" }.joined(separator: "\n"))
				}
				"""
			}
		}
		func alias(_ label: String, of fulfillingLabel: String, type: String) -> (property: String, declaration: String) {
			("\(label): \(type)", "@Received(fulfilledByDependencyNamed: \"\(fulfillingLabel)\", ofType: \(type).self) let \(label): \(type)")
		}
		let rootBuilders = (0..<layerCount).flatMap { ["left\($0)Builder: Instantiator<Left\($0)>", "right\($0)Builder: Instantiator<Right\($0)>"] } + ["pingBuilder: Instantiator<Ping>", "pongBuilder: Instantiator<Pong>"]
		let rootAliases = (0..<layerCount).reversed().flatMap { layer in
			["Left\(layer)", "Right\(layer)"].flatMap { type in
				let label = type.prefix(1).lowercased() + type.dropFirst()
				return [
					alias("\(label)Alias", of: "\(label)Renamed", type: "Instantiator<\(type)>"),
					alias("\(label)Renamed", of: "\(label)Builder", type: "Instantiator<\(type)>"),
				]
			}
		}
			+ (1..<aliasChainLength).reversed().map { alias("pingAlias\($0)", of: "pingAlias\($0 - 1)", type: "Instantiator<Ping>") }
			+ [
				alias("pingAlias0", of: "pingBuilder", type: "Instantiator<Ping>"),
				alias("pongAlias", of: "pongBuilder", type: "Instantiator<Pong>"),
			]
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Pong.swift"]):7:5: error: Dependency received in same chain it is instantiated: @Instantiated pingBuilder: Instantiator<Ping> -> @Received pongAlias: Instantiator<Pong> -> @Received pingAlias\(aliasChainLength - 1): Instantiator<Ping> -> @Received pingBuilder: Instantiator<Ping>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(\((rootBuilders + rootAliases.map(\.property)).joined(separator: ", "))) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					\(rootBuilders.map { "    @Instantiated let \($0)" }.joined(separator: "\n"))
					\(rootAliases.map { "    \($0.declaration)" }.joined(separator: "\n"))
					}
					""",
					"""
					@Instantiable
					public struct Ping: Instantiable {
					    public init(pongAlias: Instantiator<Pong>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let pongAlias: Instantiator<Pong>
					}
					""",
					"""
					@Instantiable
					public struct Pong: Instantiable {
					    public init(pingAlias\(aliasChainLength - 1): Instantiator<Ping>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received let pingAlias\(aliasChainLength - 1): Instantiator<Ping>
					}
					""",
				] + layerFiles,
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
				skipCompileVerification: true,
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
	mutating func run_onCodeWithCircularPropertyDependenciesLazyInitializedAndReceivedThroughAlias_throwsErrorNamingAlias() async {
		// B, built inside `aBuilder`, receives `aBuilder` as `renamedBuilder`. B declares no `aBuilder`, so the
		// error names the alias it would declare as @Instantiated instead.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency cycle detected! @Instantiated `aBuilder: Instantiator<A>` is @Received as `renamedBuilder: Instantiator<A>` in tree created by @Instantiated `aBuilder: Instantiator<A>`. Declare @Received(fulfilledByDependencyNamed:ofType:) `renamedBuilder: Instantiator<A>` on `B` as @Instantiated to fix. Full cycle: Instantiator<A> -> Instantiator<B> -> Instantiator<A>
				\(fixtures["A.swift"]):1:1: note: `A` is part of the cycle
				\(fixtures["B.swift"]):1:1: note: `B` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Instantiated let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Instantiated let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public final class B: Instantiable {
					    public init(renamedBuilder: Instantiator<A>) { self.renamedBuilder = renamedBuilder }
					    @Received(fulfilledByDependencyNamed: "aBuilder", ofType: Instantiator<A>.self) let renamedBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleError_whenSiblingInstantiatorsReceiveEachOther() async {
		// Each Instantiator captures the other when it is created, so neither can be created first.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleError_whenSiblingSendableInstantiatorsReceiveEachOther() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: SendableInstantiator<A> -> @Received bBuilder: SendableInstantiator<B> -> @Received aBuilder: SendableInstantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: SendableInstantiator<A>, bBuilder: SendableInstantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: SendableInstantiator<A>
					    @Instantiated private let bBuilder: SendableInstantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: SendableInstantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: SendableInstantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(aBuilder: SendableInstantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: SendableInstantiator<A>
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
	mutating func run_throwsReceivedCycleError_whenThreeSiblingInstantiatorsReceiveEachOtherInRing() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received cBuilder: Instantiator<C> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, cBuilder: Instantiator<C>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					        self.cBuilder = cBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					    @Instantiated private let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
					    @Received private let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleError_whenSiblingInstantiatorsOfLazilyBuiltParentReceiveEachOther() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(parentBuilder: Instantiator<Parent>) { self.parentBuilder = parentBuilder }
					    @Instantiated private let parentBuilder: Instantiator<Parent>
					}
					""",
					"""
					@Instantiable
					public struct Parent: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleErrorAtDeepestReceiver_whenSiblingInstantiatorIsReceivedBelowOtherSiblingsChildren() async {
		// Only `D`, below `B`, receives `aBuilder`; `B` and `C` receive nothing.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["D.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(c: C, d: D) {
					        self.c = c
					        self.d = d
					    }

					    @Instantiated private let c: C
					    @Instantiated private let d: D
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public struct D: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleErrorAtAlias_whenSiblingInstantiatorIsReceivedUnderAnotherName() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(renamedABuilder: Instantiator<A>) { self.renamedABuilder = renamedABuilder }
					    @Received(fulfilledByDependencyNamed: "aBuilder", ofType: Instantiator<A>.self) private let renamedABuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleErrorAtDeepestReceiver_whenOptionalSiblingInstantiatorIsReceivedBelowOtherSiblingsChildren() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A>? -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>?, bBuilder: Instantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>?
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    public init(aBuilder: Instantiator<A>?) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>?
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
	mutating func run_throwsReceivedCycleErrorAtDeepestReceiver_whenLazyCycleWithoutReceiverPrecedesIt() async {
		// `C` instantiates an Instantiator of itself, so the search for the receiver of `aBuilder`
		// below `B` must leave that cycle to reach `D`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["D.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(cBuilder: Instantiator<C>, d: D) {
					        self.cBuilder = cBuilder
					        self.d = d
					    }

					    @Instantiated private let cBuilder: Instantiator<C>
					    @Instantiated private let d: D
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
					    @Instantiated private let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public struct D: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleErrorAtUnshadowedReceiver_whenEarlierReceiverOfSiblingInstantiatorIsFulfilledByForwardedProperty() async {
		// `E` receives the `aBuilder` that `C` forwards, so only `D` receives Root's `aBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["D.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received bBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(cBuilder: Instantiator<C>, d: D) {
					        self.cBuilder = cBuilder
					        self.d = d
					    }

					    @Instantiated private let cBuilder: Instantiator<C>
					    @Instantiated private let d: D
					}
					""",
					"""
					@Instantiable
					public struct C: Instantiable {
					    public init(aBuilder: Instantiator<A>, e: E) {
					        self.aBuilder = aBuilder
					        self.e = e
					    }

					    @Forwarded private let aBuilder: Instantiator<A>
					    @Instantiated private let e: E
					}
					""",
					"""
					@Instantiable
					public struct D: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public struct E: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleError_whenSiblingInstantiatorReceivesAliasOfSiblingThatReceivesIt() async {
		// `aBuilder` captures `renamedBBuilder`, which is assigned from `bBuilder`, which captures `aBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received renamedBBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(renamedBBuilder: Instantiator<B>, aBuilder: Instantiator<A>, bBuilder: Instantiator<B>) {
					        self.renamedBBuilder = renamedBBuilder
					        self.aBuilder = aBuilder
					        self.bBuilder = bBuilder
					    }

					    @Received(fulfilledByDependencyNamed: "bBuilder", ofType: Instantiator<B>.self) private let renamedBBuilder: Instantiator<B>
					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(renamedBBuilder: Instantiator<B>) { self.renamedBBuilder = renamedBBuilder }
					    @Received private let renamedBBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleError_whenSiblingInstantiatorReceivesAliasOfAliasOfSiblingThatReceivesIt() async {
		// `aBuilder` captures `renamedAgainBBuilder`, which is assigned from `renamedBBuilder`,
		// which is assigned from `bBuilder`, which captures `aBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["B.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received renamedAgainBBuilder: Instantiator<B> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, renamedBBuilder: Instantiator<B>, renamedAgainBBuilder: Instantiator<B>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					    @Received(fulfilledByDependencyNamed: "bBuilder", ofType: Instantiator<B>.self) private let renamedBBuilder: Instantiator<B>
					    @Received(fulfilledByDependencyNamed: "renamedBBuilder", ofType: Instantiator<B>.self) private let renamedAgainBBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(renamedAgainBBuilder: Instantiator<B>) { self.renamedAgainBBuilder = renamedAgainBBuilder }
					    @Received private let renamedAgainBBuilder: Instantiator<B>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(aBuilder: Instantiator<A>) { self.aBuilder = aBuilder }
					    @Received private let aBuilder: Instantiator<A>
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
	mutating func run_throwsAliasCycleError_whenAliasesOnRootFulfillEachOther() async {
		// `y` is assigned from `x`, which is assigned from `y`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root.swift"]):8:5: error: Dependency cycle detected: each @Received(fulfilledByDependencyNamed:ofType:) dependency is fulfilled by the next: y: X -> x: X -> y: X
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(y: X, x: X, user: User) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) private let y: X
					    @Received(fulfilledByDependencyNamed: "y", ofType: X.self) private let x: X
					    @Instantiated private let user: User
					}
					""",
					"""
					public final class X {}

					@Instantiable
					public struct User: Instantiable {
					    public init(x: X) { self.x = x }
					    @Received private let x: X
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
	mutating func run_throwsAliasCycleErrorForCycleAliasLeadsInto_whenAliasesBelowRootFulfillEachOther() async {
		// `w` is assigned from `y`, which is assigned from `x`, which is assigned from `y`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Middle.swift"]):9:5: error: Dependency cycle detected: each @Received(fulfilledByDependencyNamed:ofType:) dependency is fulfilled by the next: y: X -> x: X -> y: X
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(middle: Middle) { self.middle = middle }
					    @Instantiated private let middle: Middle
					}
					""",
					"""
					@Instantiable
					public struct Middle: Instantiable {
					    public init(w: X, y: X, x: X) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Received(fulfilledByDependencyNamed: "y", ofType: X.self) private let w: X
					    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) private let y: X
					    @Received(fulfilledByDependencyNamed: "y", ofType: X.self) private let x: X
					}

					public final class X {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsAliasCycleError_whenAliasIsFulfilledByItself() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Middle.swift"]):4:5: error: Dependency cycle detected: each @Received(fulfilledByDependencyNamed:ofType:) dependency is fulfilled by the next: x: X -> x: X
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(middle: Middle) { self.middle = middle }
					    @Instantiated private let middle: Middle
					}
					""",
					"""
					@Instantiable
					public struct Middle: Instantiable {
					    public init(x: X) { self.x = x }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X.self) private let x: X
					}

					public final class X {}
					""",
				],
				buildSwiftOutputDirectory: true,
				filesToDelete: &filesToDelete,
			)
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsReceivedCycleError_whenInstantiatorReceivesAliasOfItselfDeclaredOnRoot() async {
		// `aBuilder` captures `renamedABuilder`, which is assigned from `aBuilder`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated aBuilder: Instantiator<A> -> @Received renamedABuilder: Instantiator<A> -> @Received aBuilder: Instantiator<A>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, renamedABuilder: Instantiator<A>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Received(fulfilledByDependencyNamed: "aBuilder", ofType: Instantiator<A>.self) private let renamedABuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    public init(renamedABuilder: Instantiator<A>) { self.renamedABuilder = renamedABuilder }
					    @Received private let renamedABuilder: Instantiator<A>
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
	mutating func run_throwsReceivedCycleErrorAtDeepestReceiver_whenConstantIsReceivedBelowItThroughAliasOfItself() async {
		// `a` is built with `c`, which is built with `renamedA`, which is assigned from `a`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated a: A -> @Received renamedA: A -> @Received a: A
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(middle: Middle) { self.middle = middle }
					    @Instantiated private let middle: Middle
					}
					""",
					"""
					@Instantiable
					public struct Middle: Instantiable {
					    public init(a: A, renamedA: A) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated private let a: A
					    @Received(fulfilledByDependencyNamed: "a", ofType: A.self) private let renamedA: A
					}
					""",
					"""
					@Instantiable
					public final class A: Instantiable {
					    public init(c: C) { self.c = c }
					    @Instantiated private let c: C
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(renamedA: A) { self.renamedA = renamedA }
					    @Received private let renamedA: A
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
	mutating func run_throwsReceivedCycleError_whenSiblingInstantiatorIsReceivedInsideLazyCycleOfEarlierSibling() async {
		// `bBuilder` captures `qBuilder`, which `A` receives below `B`'s `innerABuilder`, and `qBuilder`
		// captures `bBuilder`. `A` and `B` instantiate one another lazily, and `aBuilder` precedes them.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["A.swift"]):8:5: error: Dependency received in same chain it is instantiated: @Instantiated qBuilder: Instantiator<Q> -> @Received bBuilder: Instantiator<B> -> @Received qBuilder: Instantiator<Q>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public struct Root: Instantiable {
					    public init(aBuilder: Instantiator<A>, bBuilder: Instantiator<B>, qBuilder: Instantiator<Q>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated private let aBuilder: Instantiator<A>
					    @Instantiated private let bBuilder: Instantiator<B>
					    @Instantiated private let qBuilder: Instantiator<Q>
					}
					""",
					"""
					@Instantiable
					public struct A: Instantiable {
					    public init(innerBBuilder: Instantiator<B>, qBuilder: Instantiator<Q>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated private let innerBBuilder: Instantiator<B>
					    @Received private let qBuilder: Instantiator<Q>
					}
					""",
					"""
					@Instantiable
					public struct B: Instantiable {
					    public init(innerABuilder: Instantiator<A>) { self.innerABuilder = innerABuilder }
					    @Instantiated private let innerABuilder: Instantiator<A>
					}
					""",
					"""
					@Instantiable
					public struct Q: Instantiable {
					    public init(bBuilder: Instantiator<B>) { self.bBuilder = bBuilder }
					    @Received private let bBuilder: Instantiator<B>
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
			Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<User, UIViewController>`.
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
			Property `loggedInViewControllerBuilder: ErasedInstantiator<String, UIViewController>` on LoggedInViewController incorrectly configured. Property should instead be of type `ErasedInstantiator<(user: User, userManager: UserManager), UIViewController>`.
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithIncorrectErasedInstantiatorFirstGeneric_throwsErrorSuggestingNestedForwardedType_whenInstantiableForwardsNestedType() async {
		await assertThrowsError(
			"""
			Property `childBuilder: ErasedInstantiator<Int, AnyChild>` on Child incorrectly configured. Property should instead be of type `ErasedInstantiator<Feature.Configuration, AnyChild>`.
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(childBuilder: ErasedInstantiator<Int, AnyChild>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: ErasedInstantiator<Int, AnyChild>
					}
					""",
					"""
					public enum Feature {
					    public struct Configuration {}
					}

					public final class AnyChild {
					    public init(_ child: Child) {}
					}

					@Instantiable
					public final class Child: Instantiable {
					    public init(configuration: Feature.Configuration) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let configuration: Feature.Configuration
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
	mutating func run_onCodeWithIncorrectSendableErasedInstantiatorFirstGeneric_throwsErrorSuggestingSendableErasedInstantiator() async {
		await assertThrowsError(
			"""
			Property `childBuilder: SendableErasedInstantiator<Int, AnyChild>` on Child incorrectly configured. Property should instead be of type `SendableErasedInstantiator<String, AnyChild>`.
			""",
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(childBuilder: SendableErasedInstantiator<Int, AnyChild>) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Instantiated(fulfilledByType: "Child", erasedToConcreteExistential: true) let childBuilder: SendableErasedInstantiator<Int, AnyChild>
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable, Sendable {
					    public init(name: String) {
					        fatalError("SafeDI doesn't inspect the initializer body")
					    }

					    @Forwarded let name: String
					}

					public final class AnyChild: Sendable {
					    public init(_ child: Child) {}
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
	mutating func run_onCodeWithManyRootsInCycles_throwsErrorOfFirstRootInTypeOrder() async {
		// Every one of the 200 roots builds its own cycle. A set of roots iterates in an order
		// that depends on the process's hash seed, so validating in that order reports
		// `Root000`'s cycle about once in 200 runs.
		let swiftFileContent = (0..<200).map { index in
			let suffix = String(repeating: "0", count: 3 - String(index).count) + String(index)
			return """
			@Instantiable(isRoot: true)
			public struct Root\(suffix): Instantiable {
			    public init(partner: Partner\(suffix)) { self.partner = partner }
			    @Instantiated let partner: Partner\(suffix)
			}
			@Instantiable
			public struct Partner\(suffix): Instantiable {
			    public init(other: Other\(suffix)) { self.other = other }
			    @Instantiated let other: Other\(suffix)
			}
			@Instantiable
			public struct Other\(suffix): Instantiable {
			    public init(partner: Partner\(suffix)) { self.partner = partner }
			    @Instantiated let partner: Partner\(suffix)
			}
			"""
		}.joined(separator: "\n")
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Root000.swift"]):14:5: error: Dependency cycle detected: Partner000 -> Other000 -> Partner000
				\(fixtures["Root000.swift"]):6:1: note: `Partner000` is part of the cycle
				\(fixtures["Root000.swift"]):11:1: note: `Other000` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [swiftFileContent],
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
	mutating func run_throwsError_whenMockScopedFilePathsSpellsOneFileTwoWays() async throws {
		let swiftFile = try writeTemporarySwiftFileInProjectDirectory(named: "SafeDIConfiguration.swift", """
		#SafeDIConfiguration()
		""")

		await assertThrowsError(
			"The manifest’s mockScopedFilePaths lists one file as both './SafeDIConfiguration.swift' and 'SafeDIConfiguration.swift'. A hand-written manifest must list each file once, spelled as its configurationFilePaths and mockGeneration spell it.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [],
				configurationFilePaths: ["SafeDIConfiguration.swift"],
				mockScopedFilePaths: ["SafeDIConfiguration.swift", "./SafeDIConfiguration.swift"],
				projectRoot: swiftFile.deletingLastPathComponent().path,
	mutating func run_throwsError_whenDependencyTreeAndMockEntriesShareOutputFilePath() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		@Instantiable(isRoot: true, generateMock: true)
		public struct Root: Instantiable {
		    public init() {}
		}
		""")
		let outputFilePath = temporaryOutputFilePath(named: "Root+SafeDI.swift")

		await assertThrowsError(
			"The manifest’s dependencyTreeGeneration entry for '\(swiftFile.relativePath)' and its mockGeneration entry for '\(swiftFile.relativePath)' both write '\(outputFilePath)'. A hand-written manifest must name a different file for each.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [.init(inputFilePath: swiftFile.relativePath, outputFilePath: outputFilePath)],
				mockGeneration: [.init(inputFilePath: swiftFile.relativePath, outputFilePath: outputFilePath)],
			))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_doesNotThrow_whenMockScopedFilePathsListsOneFileTwiceWithOneSpelling() async throws {
		let swiftFile = try writeTemporarySwiftFileInProjectDirectory(named: "SafeDIConfiguration.swift", """
		#SafeDIConfiguration()
		""")

		try await generate(swiftFile, manifest: SafeDIToolManifest(
			dependencyTreeGeneration: [],
			configurationFilePaths: ["SafeDIConfiguration.swift"],
			mockScopedFilePaths: ["SafeDIConfiguration.swift", "SafeDIConfiguration.swift"],
			projectRoot: swiftFile.deletingLastPathComponent().path,
		))
	mutating func run_throwsError_whenTwoMockEntriesShareOutputFilePath() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		#SafeDIConfiguration(additionalMocksToGenerate: ["Service"])

		@Instantiable(generateMock: true)
		public struct LocalService: Instantiable {
		    public init() {}
		}
		""")
		let outputFilePath = temporaryOutputFilePath(named: "Service+SafeDIMock.swift")

		await assertThrowsError(
			"The manifest’s mockGeneration entry for '\(swiftFile.relativePath)' and its mockGeneration entry for 'Service' both write '\(outputFilePath)'. A hand-written manifest must name a different file for each.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [],
				mockGeneration: [
					.init(inputFilePath: swiftFile.relativePath, outputFilePath: outputFilePath),
					.init(inputFilePath: "Service", outputFilePath: outputFilePath),
				],
				configurationFilePaths: [swiftFile.relativePath],
				additionalMocksToGenerate: ["Service"],
			))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenMockEntryAndMockConfigurationShareOutputFilePath() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		@Instantiable(generateMock: true)
		public struct Service: Instantiable {
		    public init() {}
		}
		""")
		let outputFilePath = temporaryOutputFilePath(named: "SafeDIMockConfiguration.swift")

		await assertThrowsError(
			"The manifest’s mockGeneration entry for '\(swiftFile.relativePath)' and its mockConfigurationOutputFilePath both write '\(outputFilePath)'. A hand-written manifest must name a different file for each.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [],
				mockGeneration: [.init(inputFilePath: swiftFile.relativePath, outputFilePath: outputFilePath)],
				mockConfigurationOutputFilePath: outputFilePath,
			))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_throwsError_whenTwoEntriesSpellOneOutputFilePathTwoWays() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		@Instantiable(isRoot: true)
		public struct Root: Instantiable {
		    public init() {}
		}
		""")
		let outputFilePath = temporaryOutputFilePath(named: "Root+SafeDI.swift")
		let otherSpelling = (outputFilePath as NSString).deletingLastPathComponent + "/./Root+SafeDI.swift"

		await assertThrowsError(
			"The manifest’s dependencyTreeGeneration entry for '\(swiftFile.relativePath)' and its dependencyTreeGeneration entry for 'OtherRoot.swift' both write '\(outputFilePath)'. A hand-written manifest must name a different file for each.",
		) {
			try await generate(swiftFile, manifest: SafeDIToolManifest(
				dependencyTreeGeneration: [
					.init(inputFilePath: swiftFile.relativePath, outputFilePath: outputFilePath),
					.init(inputFilePath: "OtherRoot.swift", outputFilePath: otherSpelling),
				],
			))
		}
	}

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_writesMock_whenManifestListsOneMockEntryTwice() async throws {
		let swiftFile = try writeTemporarySwiftFile("""
		@Instantiable(generateMock: true)
		public struct Service: Instantiable {
		    public init() {}
		}
		""")
		let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
		filesToDelete.append(outputDirectory)
		let outputFile = outputDirectory.appendingPathComponent("Service+SafeDIMock.swift")
		let entry = SafeDIToolManifest.InputOutputMap(inputFilePath: swiftFile.relativePath, outputFilePath: outputFile.path)

		try await generate(swiftFile, manifest: SafeDIToolManifest(
			dependencyTreeGeneration: [],
			mockGeneration: [entry, entry],
		))

		let mockFileContent = try String(contentsOf: outputFile, encoding: .utf8)
		#expect(mockFileContent == """
		// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
		// Any modifications made to this file will be overwritten on subsequent builds.
		// Please refrain from editing this file directly.

		#if DEBUG
		extension Service {
		    static func mock() -> Service {
		        Service()
		    }
		}
		#endif
		""")
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

	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func run_onCodeWithRequiredReceiveOfOnlyIfAvailableAliasWhoseFulfillingPropertyIsUnavailable_throwsError() async {
		// Nothing provides `missing`, so Child does not create `maybe`, which Grand requires.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grand.swift"]):4:5: error: @Received property `maybe: Greeter?` is not @Instantiated or @Forwarded in chain: Root -> Child -> Grand. `maybe: Greeter?` is created by `Child` only if `missing: DefaultGreeter` is available, and `missing: DefaultGreeter` is not @Instantiated or @Forwarded in chain. Did you mean to receive this property with `onlyIfAvailable: true`?
				\(fixtures["Grand.swift"]):4:5-4:14: fixit: @Received(onlyIfAvailable: true)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					public protocol Greeter {}

					@Instantiable
					public final class DefaultGreeter: Instantiable, Greeter {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(maybe: Greeter?, grand: Grand) { self.maybe = maybe; self.grand = grand }
					    @Received(fulfilledByDependencyNamed: "missing", ofType: DefaultGreeter.self, onlyIfAvailable: true) let maybe: Greeter?
					    @Instantiated let grand: Grand
					}
					""",
					"""
					@Instantiable
					public final class Grand: Instantiable {
					    public init(maybe: Greeter?) { self.maybe = maybe }
					    @Received let maybe: Greeter?
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
	mutating func run_onCodeWithRequiredOptionalReceiveUnderAncestorThatReceivesItOnlyIfAvailable_throwsError_whenNothingProvidesIt() async {
		// Parent receives `user` only if available and nothing provides it, so Parent gets
		// `nil` and there is no `user` to hand to Child, which requires it.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: @Received property `user: User?` is not @Instantiated or @Forwarded in chain: Root -> Parent -> Child. Declare `@Instantiated let user: User?` on `Root` or on another type in the chain to fix.
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(parent: Parent) { self.parent = parent }
					    @Instantiated let parent: Parent
					}
					""",
					"""
					@Instantiable
					public final class Parent: Instantiable {
					    public init(user: User?, child: Child) { self.user = user; self.child = child }
					    @Received(onlyIfAvailable: true) let user: User?
					    @Instantiated let child: Child
					}

					public final class User {}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(user: User?) { self.user = user }
					    @Received let user: User?
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
	mutating func run_onCodeWithRequiredOptionalReceiveOfInstantiatorThatBuildsTheReceiver_throwsError() async {
		// C, built by `cBuilder`, requires `cBuilder: Instantiator<C>?`. The only `cBuilder` is
		// the one still building C, as for a receive of `cBuilder: Instantiator<C>`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["C.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated cBuilder: Instantiator<C> -> @Received cBuilder: Instantiator<C>?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(cBuilder: Instantiator<C>?) { self.cBuilder = cBuilder }
					    @Received let cBuilder: Instantiator<C>?
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
	mutating func run_onCodeWithRequiredOptionalReceiveOfInstantiatorStillBuildingAnAncestor_throwsError() async {
		// D, built inside `cBuilder`, requires `cBuilder: Instantiator<C>?`. The only `cBuilder`
		// is still being built, as for a receive of `cBuilder: Instantiator<C>`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["D.swift"]):4:5: error: Dependency cycle detected! @Instantiated `cBuilder: Instantiator<C>` is @Received in tree created by @Instantiated `cBuilder: Instantiator<C>`. Declare @Received `cBuilder: Instantiator<C>` on `D` as @Instantiated to fix. Full cycle: Instantiator<C> -> D -> Instantiator<C>?
				\(fixtures["C.swift"]):1:1: note: `C` is part of the cycle
				\(fixtures["D.swift"]):1:1: note: `D` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(cBuilder: Instantiator<C>) { self.cBuilder = cBuilder }
					    @Instantiated let cBuilder: Instantiator<C>
					}
					""",
					"""
					@Instantiable
					public final class C: Instantiable {
					    public init(d: D) { self.d = d }
					    @Instantiated let d: D
					}
					""",
					"""
					@Instantiable
					public final class D: Instantiable {
					    public init(cBuilder: Instantiator<C>?) { self.cBuilder = cBuilder }
					    @Received let cBuilder: Instantiator<C>?
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
	mutating func run_onCodeWithRequiredOptionalReceiveUnderAncestorThatReceivesItOnlyIfAvailable_throwsError_whenOnlyProviderIsStillBeingBuilt() async {
		// Parent, built inside `user`, receives `user` only if available and gets `nil`,
		// because `user` is still being built. Child, which requires `user`, is built
		// inside it too, so its receive closes a cycle, as a receive of `user: User` would.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Child.swift"]):4:5: error: Dependency cycle detected: User -> Parent -> Child -> User?
				\(fixtures["User.swift"]):1:1: note: `User` is part of the cycle
				\(fixtures["Parent.swift"]):1:1: note: `Parent` is part of the cycle
				\(fixtures["Child.swift"]):1:1: note: `Child` is part of the cycle
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(user: User) { self.user = user }
					    @Instantiated let user: User
					}
					""",
					"""
					@Instantiable
					public final class User: Instantiable {
					    public init(parent: Parent) { self.parent = parent }
					    @Instantiated let parent: Parent
					}
					""",
					"""
					@Instantiable
					public final class Parent: Instantiable {
					    public init(user: User?, child: Child) { self.user = user; self.child = child }
					    @Received(onlyIfAvailable: true) let user: User?
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(user: User?) { self.user = user }
					    @Received let user: User?
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
	mutating func run_onCodeWithRequiredReceiveOfOnlyIfAvailableAliasWhoseFulfillingPropertyIsUnavailable_throwsError_whenReceiveResolvesToEnclosingAliasThroughAliasThatIsNotCreated() async {
		// Child's alias of `missing` is never created, so Grand's receive of `maybe` resolves to
		// Parent's alias of `absent`, which is not created either.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grand.swift"]):4:5: error: @Received property `maybe: Greeter?` is not @Instantiated or @Forwarded in chain: Root -> Parent -> Child -> Grand. `maybe: Greeter?` is created by `Parent` only if `absent: DefaultGreeter` is available, and `absent: DefaultGreeter` is not @Instantiated or @Forwarded in chain. Did you mean to receive this property with `onlyIfAvailable: true`?
				\(fixtures["Grand.swift"]):4:5-4:14: fixit: @Received(onlyIfAvailable: true)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(parent: Parent) { self.parent = parent }
					    @Instantiated let parent: Parent
					}
					""",
					"""
					public protocol Greeter {}

					@Instantiable
					public final class DefaultGreeter: Instantiable, Greeter {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Parent: Instantiable {
					    public init(maybe: Greeter?, child: Child) { self.maybe = maybe; self.child = child }
					    @Received(fulfilledByDependencyNamed: "absent", ofType: DefaultGreeter.self, onlyIfAvailable: true) let maybe: Greeter?
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(maybe: Greeter?, grand: Grand) { self.maybe = maybe; self.grand = grand }
					    @Received(fulfilledByDependencyNamed: "missing", ofType: DefaultGreeter.self, onlyIfAvailable: true) let maybe: Greeter?
					    @Instantiated let grand: Grand
					}
					""",
					"""
					@Instantiable
					public final class Grand: Instantiable {
					    public init(maybe: Greeter?) { self.maybe = maybe }
					    @Received let maybe: Greeter?
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
	mutating func run_onCodeWithRequiredReceiveOfOnlyIfAvailableAliasWhoseFulfillingPropertyIsUnavailable_throwsError_whenAliasIsErasedToConcreteExistential() async {
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grand.swift"]):4:5: error: @Received property `maybe: AnyGreeter?` is not @Instantiated or @Forwarded in chain: Root -> Child -> Grand. `maybe: AnyGreeter?` is created by `Child` only if `missing: DefaultGreeter` is available, and `missing: DefaultGreeter` is not @Instantiated or @Forwarded in chain. Did you mean to receive this property with `onlyIfAvailable: true`?
				\(fixtures["Grand.swift"]):4:5-4:14: fixit: @Received(onlyIfAvailable: true)
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					public protocol Greeter {}

					public struct AnyGreeter: Greeter {
					    public init(_ greeter: Greeter) { self.greeter = greeter }
					    private let greeter: Greeter
					}

					@Instantiable
					public final class DefaultGreeter: Instantiable, Greeter {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(maybe: AnyGreeter?, grand: Grand) { self.maybe = maybe; self.grand = grand }
					    @Received(fulfilledByDependencyNamed: "missing", ofType: DefaultGreeter.self, erasedToConcreteExistential: true, onlyIfAvailable: true) let maybe: AnyGreeter?
					    @Instantiated let grand: Grand
					}
					""",
					"""
					@Instantiable
					public final class Grand: Instantiable {
					    public init(maybe: AnyGreeter?) { self.maybe = maybe }
					    @Received let maybe: AnyGreeter?
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
	mutating func run_onCodeWithRequiredReceiveOfOnlyIfAvailableAliasWhoseFulfillingPropertyIsUnavailable_throwsErrorWithoutFixIt_whenRequiringPropertyIsAlias() async {
		// Grand renames `maybe` without `onlyIfAvailable`, so it requires `maybe`, which Child does not create.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grand.swift"]):4:5: error: @Received property `maybe: Greeter?` is not @Instantiated or @Forwarded in chain: Root -> Child -> Grand. `maybe: Greeter?` is created by `Child` only if `missing: DefaultGreeter` is available, and `missing: DefaultGreeter` is not @Instantiated or @Forwarded in chain. Did you mean to receive this property with `onlyIfAvailable: true`?
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					public protocol Greeter {}

					@Instantiable
					public final class DefaultGreeter: Instantiable, Greeter {
					    public init() {}
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(maybe: Greeter?, grand: Grand) { self.maybe = maybe; self.grand = grand }
					    @Received(fulfilledByDependencyNamed: "missing", ofType: DefaultGreeter.self, onlyIfAvailable: true) let maybe: Greeter?
					    @Instantiated let grand: Grand
					}
					""",
					"""
					@Instantiable
					public final class Grand: Instantiable {
					    public init(greeter: Greeter?) { self.greeter = greeter }
					    @Received(fulfilledByDependencyNamed: "maybe", ofType: Greeter?.self) let greeter: Greeter?
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
	mutating func run_onCodeWithRequiredReceiveOfOnlyIfAvailableAliasWhoseFulfillingPropertyReceivesTheReceiversAncestor_throwsError() async {
		// Grand requires `maybe`, so Child must create it, which needs `x` built before `child`.
		// But X requires `child`.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["X.swift"]):6:5: error: Dependency received in same chain it is instantiated: @Instantiated child: Child -> @Received maybe: Greeter? -> @Received x: X -> @Received child: Child
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: Child, x: X) { self.child = child; self.x = x }
					    @Instantiated let child: Child
					    @Instantiated let x: X
					}
					""",
					"""
					public protocol Greeter {}

					@Instantiable
					public final class X: Instantiable, Greeter {
					    public init(child: Child) { self.child = child }
					    @Received let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(maybe: Greeter?, grand: Grand) { self.maybe = maybe; self.grand = grand }
					    @Received(fulfilledByDependencyNamed: "x", ofType: X.self, onlyIfAvailable: true) let maybe: Greeter?
					    @Instantiated let grand: Grand
					}
					""",
					"""
					@Instantiable
					public final class Grand: Instantiable {
					    public init(maybe: Greeter?) { self.maybe = maybe }
					    @Received let maybe: Greeter?
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
	mutating func run_onCodeWithRequiredReceiveOfOnlyIfAvailableAliasInsideItsFulfillingProperty_throwsError() async {
		// DefaultGreeter requires `maybe`, which Child can create only once `missing`,
		// the DefaultGreeter being built, exists.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultGreeter.swift"]):6:5: error: Dependency received in same chain it is instantiated: @Instantiated missing: DefaultGreeter -> @Received maybe: Greeter? -> @Received missing: DefaultGreeter
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					public protocol Greeter {}

					@Instantiable
					public final class DefaultGreeter: Instantiable, Greeter {
					    public init(maybe: Greeter?) { self.maybe = maybe }
					    @Received let maybe: Greeter?
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(missing: DefaultGreeter, maybe: Greeter?) { self.missing = missing; self.maybe = maybe }
					    @Instantiated let missing: DefaultGreeter
					    @Received(fulfilledByDependencyNamed: "missing", ofType: DefaultGreeter.self, onlyIfAvailable: true) let maybe: Greeter?
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
	mutating func run_onCodeWithRequiredReceiveOfOnlyIfAvailableAliasInsideItsInstantiatorFulfillingProperty_throwsError() async {
		// Grand requires `maybeBuilder`, which Child can create only once `greeterBuilder`,
		// the Instantiator Child is being built by, exists.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["Grand.swift"]):4:5: error: Dependency received in same chain it is instantiated: @Instantiated greeterBuilder: Instantiator<DefaultGreeter> -> @Received maybeBuilder: Instantiator<DefaultGreeter>? -> @Received greeterBuilder: Instantiator<DefaultGreeter>
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(greeterBuilder: Instantiator<DefaultGreeter>) { self.greeterBuilder = greeterBuilder }
					    @Instantiated let greeterBuilder: Instantiator<DefaultGreeter>
					}
					""",
					"""
					@Instantiable
					public final class DefaultGreeter: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(maybeBuilder: Instantiator<DefaultGreeter>?, grand: Grand) { self.maybeBuilder = maybeBuilder; self.grand = grand }
					    @Received(fulfilledByDependencyNamed: "greeterBuilder", ofType: Instantiator<DefaultGreeter>.self, onlyIfAvailable: true) let maybeBuilder: Instantiator<DefaultGreeter>?
					    @Instantiated let grand: Grand
					}
					""",
					"""
					@Instantiable
					public final class Grand: Instantiable {
					    public init(maybeBuilder: Instantiator<DefaultGreeter>?) { self.maybeBuilder = maybeBuilder }
					    @Received let maybeBuilder: Instantiator<DefaultGreeter>?
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
	mutating func run_onCodeWithReceiveOfAliasInsideItsFulfillingProperty_throwsError() async {
		// DefaultGreeter requires `maybe`, which Child creates from `missing`, the DefaultGreeter being built.
		await assertThrowsError(
			diagnostics: { fixtures in
				"""
				\(fixtures["DefaultGreeter.swift"]):6:5: error: Dependency received in same chain it is instantiated: @Instantiated missing: DefaultGreeter -> @Received maybe: Greeter -> @Received missing: DefaultGreeter
				"""
			},
		) {
			try await executeSafeDIToolTest(
				swiftFileContent: [
					"""
					@Instantiable(isRoot: true)
					public final class Root: Instantiable {
					    public init(child: Child) { self.child = child }
					    @Instantiated let child: Child
					}
					""",
					"""
					public protocol Greeter {}

					@Instantiable
					public final class DefaultGreeter: Instantiable, Greeter {
					    public init(maybe: Greeter) { self.maybe = maybe }
					    @Received let maybe: Greeter
					}
					""",
					"""
					@Instantiable
					public final class Child: Instantiable {
					    public init(missing: DefaultGreeter, maybe: Greeter) { self.missing = missing; self.maybe = maybe }
					    @Instantiated let missing: DefaultGreeter
					    @Received(fulfilledByDependencyNamed: "missing", ofType: DefaultGreeter.self) let maybe: Greeter
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

	/// A new Swift file named `fileName` holding `content`, alone in a new directory a manifest can name as its
	/// project root, which the test deletes.
	private mutating func writeTemporarySwiftFileInProjectDirectory(named fileName: String, _ content: String) throws -> URL {
		let projectDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
		filesToDelete.append(projectDirectory)
		let swiftFile = projectDirectory.appendingPathComponent(fileName)
		try content.write(to: swiftFile, atomically: true, encoding: .utf8)
		return swiftFile
	/// A path named `fileName` in a new directory, for a manifest whose outputs `generate` rejects before writing any.
	private func temporaryOutputFilePath(named fileName: String) -> String {
		URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent(UUID().uuidString)
			.appendingPathComponent(fileName)
			.path
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
