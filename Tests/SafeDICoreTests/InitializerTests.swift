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

import SwiftParser
import SwiftSyntax
import Testing
@testable import SafeDICore

struct InitializerTests {
	@Test(arguments: [
		("init() {}", nil),
		("nonisolated init() {}", "nonisolated"),
		("@MainActor init() {}", "@MainActor"),
		("@available(iOS 17, *) init() {}", nil),
	] as [(String, String?)])
	func init_recordsSpelledIsolation_whenInitializerSpellsModifierOrGlobalActor(source: String, spelledIsolation: String?) throws {
		// A public mock's construction function mirrors the isolation the initializer it calls spells.
		let initializer = try #require(Parser.parse(source: source).statements.first.flatMap { InitializerDeclSyntax($0.item) })
		#expect(Initializer(initializer).spelledIsolation == spelledIsolation)
	}

	@Test
	func init_recordsSpelledIsolation_whenFunctionSpellsGlobalActor() throws {
		let function = try #require(Parser.parse(source: "@MainActor static func mock() -> T { T() }").statements.first.flatMap { FunctionDeclSyntax($0.item) })
		#expect(Initializer(function).spelledIsolation == "@MainActor")
	}

	@Test
	func init_readsGeneratedParameterTypeAsFunctionParameter_forEverySpellingOfAPropertyType() throws {
		// A seam's generated initializer spells each parameter with `asFunctionParamterSyntax`, and the tree that calls
		// it matches its arguments as it matches a parsed initializer's, so the type a parsed generated initializer
		// records must be the property type's `asFunctionParameter`: `@escaping` on a closure, and on an attributed
		// closure before its attributes, nothing on any other spelling.
		let spellings = [
			"() -> Void",
			"(Int) -> String",
			"() async throws -> Void",
			"@Sendable () -> Void",
			"@MainActor () -> Void",
			"(() -> Void)?",
			"(@Sendable () -> Void)?",
			"(Int, Bool)",
			"(onTap: () -> Void, count: Int)",
			"any P",
			"(any Error) -> Void",
			"Feature.User",
			"[String]",
			"Result<Int, any Error>",
			"ErasedInstantiator<() -> Void, AnyX>",
			"Instantiator<X>",
			"LazilyInstantiated<any Service>",
		]
		for spelling in spellings {
			let type = try #require(Parser.parse(source: "let x: \(spelling)").statements.first?.item.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type).typeDescription
			let parameter = Property(label: "x", typeDescription: type).asFunctionParamterSyntax.description
			let initializerSyntax = try #require(Parser.parse(source: "init(\(parameter)) {}").statements.first?.item.as(InitializerDeclSyntax.self))
			#expect(Initializer(initializerSyntax).arguments.map(\.typeDescription) == [type.asFunctionParameter], "\(spelling) is generated as `\(parameter)`")
		}
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsPrivateOrFilePrivate() {
		for accessLevel in [AccessLevel.private, .fileprivate] {
			let initializer = Initializer(
				access: AccessDeclaration(level: accessLevel),
				arguments: [],
			)

			#expect(throws: Initializer.GenerationError.inaccessibleInitializer(accessLevel), performing: {
				try initializer.validate(fulfilling: [])
			})
		}
	}

	@Test
	func isValid_returnsTrue_whenInitializerIsInternalOrPackage() {
		for accessLevel in [AccessLevel.internal, .package] {
			let initializer = Initializer(
				access: AccessDeclaration(level: accessLevel),
				arguments: [],
			)

			#expect(initializer.isValid(forFulfilling: []))
		}
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsOptional() {
		let initializer = Initializer(
			isOptional: true,
			arguments: [],
		)

		#expect(throws: Initializer.GenerationError.optionalInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsAsync() {
		let initializer = Initializer(
			isAsync: true,
			arguments: [],
		)

		#expect(throws: Initializer.GenerationError.asyncInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerThrows() {
		let initializer = Initializer(
			doesThrow: true,
			arguments: [],
		)

		#expect(throws: Initializer.GenerationError.throwingInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerHasGenericParameters() {
		let initializer = Initializer(
			hasGenericParameter: true,
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "Variant"),
					defaultValueExpression: nil,
				),
			],
		)

		#expect(throws: Initializer.GenerationError.genericParameterInInitializer, performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant"),
						),
						source: .forwarded,
					),
				],
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerHasGenericWhereClause() {
		let initializer = Initializer(
			hasGenericWhereClause: true,
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "Variant"),
					defaultValueExpression: nil,
				),
			],
		)

		#expect(throws: Initializer.GenerationError.whereClauseOnInitializer, performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant"),
						),
						source: .forwarded,
					),
				],
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerHasUnexpectedArgument() {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "Variant"),
					defaultValueExpression: nil,
				),
			],
		)

		#expect(throws: Initializer.GenerationError.unexpectedArgument("variant: Variant"), performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentsAndDependenciesExist() {
		let initializer = Initializer(arguments: [])

		#expect(throws: Initializer.GenerationError.missingArguments([.init(label: "variant", typeDescription: .simple(name: "Variant"))]), performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant"),
						),
						source: .forwarded,
					),
				],
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentLabel() {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "someVariant",
					typeDescription: .simple(name: "Variant"),
					defaultValueExpression: nil,
				),
			],
		)

		#expect(throws: Initializer.GenerationError.unexpectedArgument("someVariant: Variant"), performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant"),
						),
						source: .forwarded,
					),
				],
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentType() {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "NotThatVariant"),
					defaultValueExpression: nil,
				),
			],
		)

		#expect(throws: Initializer.GenerationError.unexpectedArgument("variant: NotThatVariant"), performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant"),
						),
						source: .forwarded,
					),
				],
			)
		})
	}

	// MARK: createMockInitializerArgumentList

	@Test
	func createMockInitializerArgumentList_passesNilForUnavailableDependency() {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "service",
					typeDescription: .simple(name: "Service"),
					defaultValueExpression: nil,
				),
				.init(
					innerLabel: "optionalDep",
					typeDescription: .optional(.simple(name: "OptionalDep")),
					defaultValueExpression: nil,
				),
			],
		)
		let dependencies: [Dependency] = [
			.init(
				property: .init(label: "service", typeDescription: .simple(name: "Service")),
				source: .received(onlyIfAvailable: false),
			),
			.init(
				property: .init(label: "optionalDep", typeDescription: .optional(.simple(name: "OptionalDep"))),
				source: .received(onlyIfAvailable: true),
			),
		]
		let unavailable: Set<Property> = [
			.init(label: "optionalDep", typeDescription: .optional(.simple(name: "OptionalDep"))),
		]

		let result = initializer.createMockInitializerArgumentList(
			given: dependencies,
			unavailableProperties: unavailable,
		)

		#expect(result == "service: service, optionalDep: nil")
	}

	@Test
	func createMockInitializerArgumentList_includesNonDependencyDefaultValuedArguments() {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "service",
					typeDescription: .simple(name: "Service"),
					defaultValueExpression: nil,
				),
				.init(
					innerLabel: "flag",
					typeDescription: .simple(name: "Bool"),
					defaultValueExpression: "false",
				),
			],
		)
		let dependencies: [Dependency] = [
			.init(
				property: .init(label: "service", typeDescription: .simple(name: "Service")),
				source: .received(onlyIfAvailable: false),
			),
		]

		let result = initializer.createMockInitializerArgumentList(given: dependencies)

		#expect(result == "service: service, flag: flag")
	}

	@Test
	func createMockInitializerArgumentList_includesDependencyWithDefaultValue() {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "service",
					typeDescription: .simple(name: "Service"),
					defaultValueExpression: nil,
				),
				.init(
					innerLabel: "crossModuleDependency",
					typeDescription: .simple(name: "CrossModuleType"),
					defaultValueExpression: ".mock()",
				),
				.init(
					innerLabel: "flag",
					typeDescription: .simple(name: "Bool"),
					defaultValueExpression: "false",
				),
			],
		)
		let dependencies: [Dependency] = [
			.init(
				property: .init(label: "service", typeDescription: .simple(name: "Service")),
				source: .received(onlyIfAvailable: false),
			),
			.init(
				property: .init(label: "crossModuleDependency", typeDescription: .simple(name: "CrossModuleType")),
				source: .instantiated(fulfillingTypeDescription: nil, erasedToConcreteExistential: false),
			),
		]

		let result = initializer.createMockInitializerArgumentList(given: dependencies)

		// All args included: deps (with or without defaults) + non-dep defaults.
		#expect(result == "service: service, crossModuleDependency: crossModuleDependency, flag: flag")
	}
}
