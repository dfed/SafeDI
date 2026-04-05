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
	func mockMethodConflictsWithGenerateMock_description_mentionsAmbiguousSignatures() {
		let error = FixableInstantiableError.mockMethodConflictsWithGenerateMock
		#expect(error.description == "@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method when there are no dependencies, because the generated and hand-written methods would have ambiguous signatures.")
	}

	@Test
	func mockMethodConflictsWithGenerateMock_fixIt_mentionsRemovingGenerateMock() {
		let error = FixableInstantiableError.mockMethodConflictsWithGenerateMock
		#expect(error.fixIt.message == "Remove `generateMock: true`")
	}

	@Test
	func mockMethodDependencyHasDefaultValue_description_mentionsDefaultValuesAndGenerateMock() {
		let error = FixableInstantiableError.mockMethodDependencyHasDefaultValue([
			Property(label: "service", typeDescription: .simple(name: "Service")),
		])
		#expect(error.description == "@Instantiable-decorated type's `mock()` method must not have default values on dependency parameters when `generateMock` is `true`. Default values would create ambiguity with the generated mock method.")
	}

	@Test
	func mockMethodDependencyHasDefaultValue_fixIt_mentionsRemovingDefaultValues() {
		let error = FixableInstantiableError.mockMethodDependencyHasDefaultValue([
			Property(label: "service", typeDescription: .simple(name: "Service")),
		])
		#expect(error.fixIt.message == "Remove default values from mock() dependency parameters for service: Service")
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
