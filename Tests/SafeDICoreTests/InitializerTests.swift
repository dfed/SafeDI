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

import Testing
@testable import SafeDICore

struct InitializerTests {
	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsNotPublicOrOpen() {
		let initializer = Initializer(
			isPublicOrOpen: false,
			arguments: [],
		)

		#expect(throws: Initializer.GenerationError.inaccessibleInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
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
	func createMockInitializerArgumentList_passesNilForUnavailableDependency() throws {
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

		let result = try initializer.createMockInitializerArgumentList(
			given: dependencies,
			unavailableProperties: unavailable,
		)

		#expect(result == "service: service, optionalDep: nil")
	}

	@Test
	func createMockInitializerArgumentList_throwsForUnexpectedNonDefaultArgument() {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "service",
					typeDescription: .simple(name: "Service"),
					defaultValueExpression: nil,
				),
				.init(
					innerLabel: "unknown",
					typeDescription: .simple(name: "Unknown"),
					defaultValueExpression: nil,
				),
			],
		)
		let dependencies: [Dependency] = [
			.init(
				property: .init(label: "service", typeDescription: .simple(name: "Service")),
				source: .received(onlyIfAvailable: false),
			),
		]

		#expect(throws: Initializer.GenerationError.unexpectedArgument("unknown: Unknown"), performing: {
			try initializer.createMockInitializerArgumentList(given: dependencies)
		})
	}

	@Test
	func createMockInitializerArgumentList_includesNonDependencyDefaultValuedArguments() throws {
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

		let result = try initializer.createMockInitializerArgumentList(given: dependencies)

		#expect(result == "service: service, flag: flag")
	}

	@Test
	func createMockInitializerArgumentList_includesDependencyWithDefaultValue() throws {
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

		let result = try initializer.createMockInitializerArgumentList(given: dependencies)

		// All args included: deps (with or without defaults) + non-dep defaults.
		#expect(result == "service: service, crossModuleDependency: crossModuleDependency, flag: flag")
	}
}
