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
import Testing
@testable import SafeDICore
@testable import SafeDIToolLibrary
@testable import SafeDIToolTestSupport

/// A mock's alike places share one plan node (`MockLowering.SharedRecordKey`), and the type key reads the first place's
/// record for all of them, so the key must read every field of each record type it compares: a field it missed would
/// let two places that differ in it share one body.
struct SafeDIToolMockNodeSharingTests: ~Copyable {
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

	/// The two `panelBuilder` places differ only in where their argument is read from: inside the lazy screen's build no
	/// lazy screen is available yet, so its `lazyScreen` is `nil`, and inside the screen's build it is the root's binding.
	/// The key keeps them two nodes, which the type key lays out as one function that takes the argument. As one node,
	/// the second place would read the first one's `nil`, and the root would keep the walk's body.
	@Test
	@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
	mutating func mock_laysOutOneBuilderTakingTheArgument_whenAlikePlacesReadTheArgumentFromNilAndFromABinding() async throws {
		let output = try await executeSafeDIToolTest(
			swiftFileContent: [
				seamFixtureType(named: "Panel", isFinalClass: true, declarations: ["@Received(onlyIfAvailable: true) let lazyScreen: LazilyInstantiated<Screen>?"]),
				seamFixtureType(named: "Screen", isFinalClass: true, declarations: ["@Instantiated let panelBuilder: Instantiator<Panel>"]),
				seamFixtureType(named: "Root", isFinalClass: true, declarations: ["@Instantiated let screen: Screen", "@Instantiated let lazyScreen: LazilyInstantiated<Screen>"])
					.replacingOccurrences(of: "@Instantiable\n", with: "@Instantiable(generateMock: true)\n"),
			],
			buildSwiftOutputDirectory: true,
			filesToDelete: &filesToDelete,
		)

		#expect(output.mockFiles["Root+SafeDIMock.swift"] == generatedFileHeader + """
		#if DEBUG
		extension Root {
		    /// Overrides for the mock dependency tree.
		    struct SafeDIOverrides {
		        init(
		            lazyScreen: Screen.SafeDIMockConfiguration = .init(),
		            screen: Screen.SafeDIMockConfiguration = .init()
		        ) {
		            __safeDI_storage = __safeDI_Storage(
		                lazyScreen: lazyScreen,
		                screen: screen
		            )
		        }

		        var lazyScreen: Screen.SafeDIMockConfiguration { __safeDI_storage.lazyScreen }
		        var screen: Screen.SafeDIMockConfiguration { __safeDI_storage.screen }

		        private let __safeDI_storage: __safeDI_Storage

		        private final class __safeDI_Storage {
		            init(
		                lazyScreen: Screen.SafeDIMockConfiguration,
		                screen: Screen.SafeDIMockConfiguration
		            ) {
		                self.lazyScreen = lazyScreen
		                self.screen = screen
		            }

		            let lazyScreen: Screen.SafeDIMockConfiguration
		            let screen: Screen.SafeDIMockConfiguration
		        }
		    }

		    static func mock(
		        safeDIOverrides: SafeDIOverrides = .init()
		    ) -> Root {
		        func __safeDI_lazyScreen(lazyScreen: LazilyInstantiated<Screen>?, __safeDI_Screen_configuration: Screen.SafeDIMockConfiguration) -> Screen {
		            let panelBuilder = Instantiator<Panel> {
		                __safeDI_panelBuilder(lazyScreen: lazyScreen, __safeDI_Panel_configuration: __safeDI_Screen_configuration.panelBuilder)
		            }
		            return if let safeDIBuilder = __safeDI_Screen_configuration.safeDIBuilder { safeDIBuilder(panelBuilder) } else { Screen(panelBuilder: panelBuilder) }
		        }
		        func __safeDI_panelBuilder(lazyScreen: LazilyInstantiated<Screen>?, __safeDI_Panel_configuration: ((LazilyInstantiated<Screen>?) -> Panel)?) -> Panel {
		            if let safeDIBuilder = __safeDI_Panel_configuration { safeDIBuilder(lazyScreen) } else { Panel(lazyScreen: lazyScreen) }
		        }
		        let lazyScreen = LazilyInstantiated<Screen> {
		            __safeDI_lazyScreen(lazyScreen: nil, __safeDI_Screen_configuration: safeDIOverrides.lazyScreen)
		        }
		        let screen: Screen = __safeDI_lazyScreen(lazyScreen: lazyScreen, __safeDI_Screen_configuration: safeDIOverrides.screen)
		        return Root(screen: screen, lazyScreen: lazyScreen)
		    }
		}
		#endif
		""")
	}

	@Test
	func sharedRecordKey_readsEveryFieldOfBuiltPlaceRecord_whenComparingPlaces() throws {
		let type = TypeDescription.simple(name: "Screen", generics: [])
		var record = BuiltPlaceRecord(
			property: Property(label: "screen", typeDescription: type),
			isErased: false,
			concreteType: type,
			isExtension: false,
			target: .initializer(type),
			arguments: [],
			forwardedProperties: [],
			cycleParameters: [],
			callCycleArguments: [],
			functionName: "__safeDI_screen",
			isSendable: false,
			typesDeclaredEscaping: [],
			lineEnd: "",
			hasFunction: true,
			children: [],
			node: PlanNode(),
		)
		record.passedArguments = []
		let shape = try #require(MockLowering.BuiltRecordShape(record, passedArgumentValues: false))
		let sharingFields = try #require(record.sharingFields)
		// The node is what the key decides, and the box's fields are read through its accessors.
		let recordFields = Self.fieldNames(of: record).subtracting(["node", "sharingFields"]).union(Self.fieldNames(of: sharingFields))
		#expect(recordFields == Self.fieldNames(of: shape))
	}

	@Test
	func sharedRecordKey_readsEveryFieldOfEachRecordItCompares_whenComparingPlaces() {
		let type = TypeDescription.simple(name: "Screen", generics: [])
		let property = Property(label: "screen", typeDescription: type)
		let closer = ClosingPlaceRecord(property: property, isErased: false, isExtension: false, closedOnFunctionName: "__safeDI_screen", forwardedProperties: [], cycleArguments: [])
		#expect(Self.fieldNames(of: closer) == Self.fieldNames(of: MockLowering.ClosingShape(closer)))
		let alias = AliasPlaceRecord(property: property, fulfillingProperty: nil, text: "")
		#expect(Self.fieldNames(of: alias) == Self.fieldNames(of: MockLowering.AliasShape(alias)))
		let alternative = ConstructionAlternative(closure: .passedArgument("screen"), bindingName: nil, requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)
		#expect(Self.fieldNames(of: alternative) == Self.fieldNames(of: MockLowering.AlternativeShape(alternative)))
		let argument = PassedArgument(parameterName: "screen", type: type, value: .passedArgument("screen"), staysOutsideSendableFunctions: false)
		#expect(Self.fieldNames(of: argument) == Self.fieldNames(of: MockLowering.PassedArgumentShape(argument, value: true)))
	}

	@Test
	func sharedRecordKey_differs_whenTwoPlacesDifferInOneField() throws {
		let type = TypeDescription.simple(name: "Screen", generics: [])
		let otherType = TypeDescription.simple(name: "Panel", generics: [])
		let property = Property(label: "screen", typeDescription: type)
		let otherProperty = Property(label: "panel", typeDescription: otherType)
		let read = PlaceRead(argumentLabel: "panel", label: "panel", property: otherProperty, source: .binding(label: "panel"))
		let child = GeneratedCode.place(PlacePlan(code: .text(""), record: .alias(AliasPlaceRecord(property: otherProperty, fulfillingProperty: nil, text: ""))))
		func record(
			property: Property = property,
			isErased: Bool = false,
			concreteType: TypeDescription = type,
			isExtension: Bool = false,
			target: ConstructionTarget = .initializer(type),
			arguments: [PlaceRead] = [],
			forwardedProperties: [Property] = [],
			cycleParameters: [Property] = [],
			callCycleArguments: [PlaceRead] = [],
			functionName: String = "__safeDI_screen",
			isSendable: Bool = false,
			typesDeclaredEscaping: Set<TypeDescription> = [],
			lineEnd: String = "",
			hasFunction: Bool = true,
			children: [GeneratedCode] = [],
			changingSharingFields change: (inout BuiltPlaceRecord) -> Void = { _ in },
		) -> BuiltPlaceRecord {
			var record = BuiltPlaceRecord(
				property: property,
				isErased: isErased,
				concreteType: concreteType,
				isExtension: isExtension,
				target: target,
				arguments: arguments,
				forwardedProperties: forwardedProperties,
				cycleParameters: cycleParameters,
				callCycleArguments: callCycleArguments,
				functionName: functionName,
				isSendable: isSendable,
				typesDeclaredEscaping: typesDeclaredEscaping,
				lineEnd: lineEnd,
				hasFunction: hasFunction,
				children: children,
				node: PlanNode(),
			)
			change(&record)
			return record
		}
		// One record per field of the key, each differing from the first in that field alone.
		let recordsByChangedField = [
			"property": record(property: otherProperty),
			"isErased": record(isErased: true),
			"concreteType": record(concreteType: otherType),
			"isExtension": record(isExtension: true),
			"target": record(target: .instantiate(type)),
			"arguments": record(arguments: [read]),
			"forwardedProperties": record(forwardedProperties: [otherProperty]),
			"cycleParameters": record(cycleParameters: [otherProperty]),
			"callCycleArguments": record(callCycleArguments: [read]),
			"functionName": record(functionName: "__safeDI_screen_Screen"),
			"isSendable": record(isSendable: true),
			"typesDeclaredEscaping": record(typesDeclaredEscaping: [otherType]),
			"lineEnd": record(lineEnd: " // comment"),
			"hasFunction": record(hasFunction: false),
			"children": record(children: [child]),
			"passedArguments": record(changingSharingFields: {
				$0.passedArguments = [PassedArgument(parameterName: "panel", type: otherType, value: .passedArgument("panel"), staysOutsideSendableFunctions: false)]
			}),
			"constructionValue": record(changingSharingFields: {
				$0.constructionValue = ConstructionValue(value: .passedArgument("panel"), resultWrapper: nil)
			}),
			"alternatives": record(changingSharingFields: {
				$0.alternatives = [ConstructionAlternative(closure: .passedArgument("panel"), bindingName: nil, requiresAbsent: [], use: .calledWithNoArguments, resultWrapper: nil)]
			}),
			"argumentValues": record(changingSharingFields: { $0.argumentValues = [0: .passedArgument("panel")] }),
			"functionReturnType": record(changingSharingFields: { $0.functionReturnType = otherType }),
			"nilAlternative": record(changingSharingFields: { $0.nilAlternative = .member("screenIsUnavailable", of: .passedArgument("panel")) }),
		]
		let key = try #require(MockLowering.SharedRecordKey(record()))
		#expect(try #require(MockLowering.SharedRecordKey(record())) == key)
		#expect(Set(recordsByChangedField.keys) == Self.fieldNames(of: key.record))
		for (field, changed) in recordsByChangedField {
			#expect(try #require(MockLowering.SharedRecordKey(changed)) != key, "The key ignores `\(field)`.")
		}
	}

	private static func fieldNames(of value: Any) -> Set<String> {
		Set(Mirror(reflecting: value).children.compactMap(\.label))
	}

	private var filesToDelete: [URL]
}
