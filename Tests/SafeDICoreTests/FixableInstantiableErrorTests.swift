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

struct FixableInstantiableErrorTests {
	@Test
	func mockMethodMissingArguments_description_mentionsMockMethodAndProperties() {
		let error = FixableInstantiableError.mockMethodMissingArguments([
			Property(label: "service", typeDescription: .simple(name: "Service")),
		])
		#expect(error.description.contains("mock()"))
		#expect(error.description.contains("must have a parameter"))
	}

	@Test
	func mockMethodMissingArguments_fixIt_mentionsAddingMockArguments() {
		let error = FixableInstantiableError.mockMethodMissingArguments([
			Property(label: "service", typeDescription: .simple(name: "Service")),
		])
		#expect(error.fixIt.message.contains("Add mock() arguments for"))
		#expect(error.fixIt.message.contains("service: Service"))
	}

	@Test
	func mockMethodNotPublic_description_mentionsMockMethodVisibility() {
		let error = FixableInstantiableError.mockMethodNotPublic
		#expect(error.description.contains("mock()"))
		#expect(error.description.contains("must be `public` or `open`"))
	}

	@Test
	func mockMethodNotPublic_fixIt_mentionsAddingPublicModifier() {
		let error = FixableInstantiableError.mockMethodNotPublic
		#expect(error.fixIt.message.contains("Add `public` modifier to mock() method"))
	}

	@Test
	func mockMethodIncorrectReturnType_description_mentionsMockMethodAndTypeName() {
		let error = FixableInstantiableError.mockMethodIncorrectReturnType(typeName: "MyService")
		#expect(error.description == "@Instantiable-decorated type's `mock()` method must return `Self` or `MyService`.")
	}

	@Test
	func mockMethodIncorrectReturnType_fixIt_mentionsChangingReturnType() {
		let error = FixableInstantiableError.mockMethodIncorrectReturnType(typeName: "MyService")
		#expect(error.fixIt.message == "Change mock() return type to `MyService`")
	}

	@Test
	func duplicateMockMethod_description_mentionsAtMostOneMockMethod() {
		let error = FixableInstantiableError.duplicateMockMethod
		#expect(error.description == "@Instantiable-decorated type must have at most one `mock()` method. Remove this duplicate.")
	}

	@Test
	func duplicateMockMethod_fixIt_mentionsRemovingDuplicate() {
		let error = FixableInstantiableError.duplicateMockMethod
		#expect(error.fixIt.message == "Remove duplicate mock() method")
	}

	@Test
	func mockMethodNeedsCustomName_description_mentionsAmbiguousSignaturesAndCustomMockName() {
		let error = FixableInstantiableError.mockMethodNeedsCustomName
		#expect(error.description.contains("generateMock: true"))
		#expect(error.description.contains("ambiguous signatures"))
		#expect(error.description.contains("customMockName"))
	}

	@Test
	func mockMethodNeedsCustomName_fixIt_mentionsRenamingAndAddingCustomMockName() {
		let error = FixableInstantiableError.mockMethodNeedsCustomName
		#expect(error.fixIt.message == "Rename method to `customMock` and add `customMockName: \"customMock\"` to `@Instantiable`")
	}

	@Test
	func mockMethodConflictsWithGeneratedMock_description_mentionsConflict() {
		let error = FixableInstantiableError.mockMethodConflictsWithGeneratedMock
		#expect(error.description == "@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method. The generated `mock()` would conflict with this method. Remove it or rename it.")
	}

	@Test
	func mockMethodConflictsWithGeneratedMock_fixIt_mentionsRemovingMethod() {
		let error = FixableInstantiableError.mockMethodConflictsWithGeneratedMock
		#expect(error.fixIt.message == "Remove this `mock()` method")
	}

	@Test
	func customMockNameWithoutGenerateMock_description_mentionsRequiringGenerateMock() {
		let error = FixableInstantiableError.customMockNameWithoutGenerateMock
		#expect(error.description == "`customMockName` requires `generateMock: true`.")
	}

	@Test
	func customMockNameWithoutGenerateMock_fixIt_mentionsAddingGenerateMock() {
		let error = FixableInstantiableError.customMockNameWithoutGenerateMock
		#expect(error.fixIt.message == "Add `generateMock: true` to `@Instantiable`")
	}

	@Test
	func customMockNameMethodNotFound_description_mentionsMissingMethodName() {
		let error = FixableInstantiableError.customMockNameMethodNotFound("customMock")
		#expect(error.description == "No method named `customMock` found. Add a `public static func customMock(…)` method.")
	}

	@Test
	func customMockNameMethodNotFound_fixIt_mentionsAddingMethod() {
		let error = FixableInstantiableError.customMockNameMethodNotFound("customMock")
		#expect(error.fixIt.message == "Add `public static func customMock(…)` method")
	}

	@Test
	func mockMethodNonDependencyMissingDefaultValue_description_mentionsNonDependencyParameters() {
		let error = FixableInstantiableError.mockMethodNonDependencyMissingDefaultValue([
			Property(label: "extra", typeDescription: .simple(name: "Bool")),
		])
		#expect(error.description == "@Instantiable-decorated type's `mock()` method has non-dependency parameters without default values. Parameters that do not correspond to a dependency must have default values.")
	}

	@Test
	func mockMethodNonDependencyMissingDefaultValue_fixIt_mentionsAddingDefaultValues() {
		let error = FixableInstantiableError.mockMethodNonDependencyMissingDefaultValue([
			Property(label: "extra", typeDescription: .simple(name: "Bool")),
		])
		#expect(error.fixIt.message == "Add default values to mock() non-dependency parameters for extra: Bool")
	}
}
