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
	func generateSafeDIInitializer_throwsWhenInitializerIsNotPublicOrOpen() throws {
		let initializer = Initializer(
			isPublicOrOpen: false,
			arguments: []
		)

		#expect(throws: Initializer.GenerationError.inaccessibleInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsOptional() throws {
		let initializer = Initializer(
			isOptional: true,
			arguments: []
		)

		#expect(throws: Initializer.GenerationError.optionalInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsAsync() throws {
		let initializer = Initializer(
			isAsync: true,
			arguments: []
		)

		#expect(throws: Initializer.GenerationError.asyncInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerThrows() throws {
		let initializer = Initializer(
			doesThrow: true,
			arguments: []
		)

		#expect(throws: Initializer.GenerationError.throwingInitializer, performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerHasGenericParameters() throws {
		let initializer = Initializer(
			hasGenericParameter: true,
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "Variant"),
					hasDefaultValue: false
				),
			]
		)

		#expect(throws: Initializer.GenerationError.genericParameterInInitializer, performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant")
						),
						source: .forwarded
					),
				]
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerHasGenericWhereClause() throws {
		let initializer = Initializer(
			hasGenericWhereClause: true,
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "Variant"),
					hasDefaultValue: false
				),
			]
		)

		#expect(throws: Initializer.GenerationError.whereClauseOnInitializer, performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant")
						),
						source: .forwarded
					),
				]
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerHasUnexpectedArgument() throws {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "Variant"),
					hasDefaultValue: false
				),
			]
		)

		#expect(throws: Initializer.GenerationError.unexpectedArgument("variant: Variant"), performing: {
			try initializer.validate(fulfilling: [])
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentsAndDependenciesExist() throws {
		let initializer = Initializer(arguments: [])

		#expect(throws: Initializer.GenerationError.missingArguments([.init(label: "variant", typeDescription: .simple(name: "Variant"))]), performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant")
						),
						source: .forwarded
					),
				]
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentLabel() throws {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "someVariant",
					typeDescription: .simple(name: "Variant"),
					hasDefaultValue: false
				),
			]
		)

		#expect(throws: Initializer.GenerationError.unexpectedArgument("someVariant: Variant"), performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant")
						),
						source: .forwarded
					),
				]
			)
		})
	}

	@Test
	func generateSafeDIInitializer_throwsWhenInitializerIsMissingArgumentType() throws {
		let initializer = Initializer(
			arguments: [
				.init(
					innerLabel: "variant",
					typeDescription: .simple(name: "NotThatVariant"),
					hasDefaultValue: false
				),
			]
		)

		#expect(throws: Initializer.GenerationError.unexpectedArgument("variant: NotThatVariant"), performing: {
			try initializer.validate(
				fulfilling: [
					.init(
						property: .init(
							label: "variant",
							typeDescription: .simple(name: "Variant")
						),
						source: .forwarded
					),
				]
			)
		})
	}
}
