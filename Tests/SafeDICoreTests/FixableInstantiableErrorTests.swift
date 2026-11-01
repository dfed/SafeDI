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
		let error = FixableInstantiableError.mockMethodMissingArguments(methodName: "mock", [
			Property(label: "service", typeDescription: .simple(name: "Service")),
		])
		#expect(error.description == "This `mock()` method has no parameter for `service: Service`. A hand-written mock must take a parameter for each @Instantiated, @Received, or @Forwarded-decorated property; extra parameters with default values are allowed.")
	}

	@Test
	func mockMethodMissingArguments_fixIt_mentionsAddingMockArguments() {
		let error = FixableInstantiableError.mockMethodMissingArguments(methodName: "mock", [
			Property(label: "service", typeDescription: .simple(name: "Service")),
		])
		#expect(error.fixIt.message == "Add `mock()` arguments for service: Service")
	}

	@Test
	func privateOrFilePrivateMockMethod_description_namesTheAccessLevelAndTheFix() {
		let error = FixableInstantiableError.privateOrFilePrivateMockMethod(.fileprivate)
		#expect(error.description == "@Instantiable-decorated type’s `mock()` method must not be `fileprivate`: a generated mock calls it in a generated file, where a `fileprivate` method is not visible. Remove `fileprivate`.")
	}

	@Test
	func privateOrFilePrivateMockMethod_fixIt_mentionsRemovingTheModifier() {
		let error = FixableInstantiableError.privateOrFilePrivateMockMethod(.private)
		#expect(error.fixIt.message == "Remove `private` modifier from `mock()` method")
	}

	@Test
	func mockMethodIncorrectReturnType_description_mentionsMockMethodAndTypeName() {
		let error = FixableInstantiableError.mockMethodIncorrectReturnType(typeName: "MyService")
		#expect(error.description == "@Instantiable-decorated type’s `mock()` method must return `Self` or `MyService`.")
	}

	@Test
	func mockMethodHasEffectSpecifiers_description_namesTheMethodAndTheFix() {
		let error = FixableInstantiableError.mockMethodHasEffectSpecifiers(methodName: "customMock")
		#expect(error.description == "This `customMock()` method must be neither `async` nor `throws`: generated mocks call it synchronously. Remove its effect specifiers.")
	}

	@Test
	func mockMethodHasEffectSpecifiers_fixIt_mentionsRemovingTheEffectSpecifiers() {
		let error = FixableInstantiableError.mockMethodHasEffectSpecifiers(methodName: "mock")
		#expect(error.fixIt.message == "Remove effect specifiers from `mock()`")
	}

	@Test
	func mockMethodIncorrectReturnType_fixIt_mentionsChangingReturnType() {
		let error = FixableInstantiableError.mockMethodIncorrectReturnType(typeName: "MyService")
		#expect(error.fixIt.message == "Change `mock()` return type to `MyService`")
	}

	@Test
	func extensionMockMethodIncorrectReturnType_description_mentionsExtendedTypeAndAdditionalTypes() {
		let error = FixableInstantiableError.extensionMockMethodIncorrectReturnType(typeName: "MyService")
		#expect(error.description == "@Instantiable-decorated extension’s `mock()` method must return `MyService` or a type listed in `fulfillingAdditionalTypes`.")
	}

	@Test
	func mockMethodNonDependencyMissingDefaultValue_description_namesEveryParameter_whenSeveralLackDefaults() {
		let error = FixableInstantiableError.mockMethodNonDependencyMissingDefaultValue([
			Property(label: "extra", typeDescription: .simple(name: "Bool")),
			Property(label: "count", typeDescription: .simple(name: "Int")),
		])
		#expect(error.description == "This `mock()` method’s parameters `extra: Bool`, `count: Int` do not correspond to a dependency, so they must have default values.")
	}

	@Test
	func duplicateMockMethod_description_mentionsAtMostOneMockMethod() {
		let error = FixableInstantiableError.duplicateMockMethod
		#expect(error.description == "@Instantiable-decorated type must have at most one `mock()` method. Remove this duplicate.")
	}

	@Test
	func duplicateMockMethod_fixIt_mentionsRemovingDuplicate() {
		let error = FixableInstantiableError.duplicateMockMethod
		#expect(error.fixIt.message == "Remove duplicate `mock()` method")
	}

	@Test
	func mockMethodNeedsCustomName_description_mentionsAmbiguousSignaturesAndCustomMockName() {
		let error = FixableInstantiableError.mockMethodNeedsCustomName
		#expect(error.description == "@Instantiable-decorated type with `generateMock: true` cannot also have a hand-written `mock()` method because the generated and hand-written methods would have ambiguous signatures. Rename your method and add `customMockName` to `@Instantiable`.")
	}

	@Test
	func mockMethodNeedsCustomName_fixIt_mentionsRenamingAndAddingCustomMockName() {
		let error = FixableInstantiableError.mockMethodNeedsCustomName
		#expect(error.fixIt.message == "Rename method to `customMock` and add `customMockName: \"customMock\"` to `@Instantiable`")
	}

	@Test
	func mockMethodConflictsWithGeneratedMock_description_mentionsConflict() {
		let error = FixableInstantiableError.mockMethodConflictsWithGeneratedMock(customMockName: "customMock")
		#expect(error.description == "This `mock()` method conflicts with the `mock()` that `generateMock: true` generates. This type’s hand-written mock is `customMock`, which `customMockName` names; remove this method or rename it.")
	}

	@Test
	func mockMethodConflictsWithGeneratedMock_fixIt_mentionsRemovingMethod() {
		let error = FixableInstantiableError.mockMethodConflictsWithGeneratedMock(customMockName: "customMock")
		#expect(error.fixIt.message == "Remove this `mock()` method")
	}

	@Test
	func customMockNameWithoutMockGeneration_description_mentionsRequiringGenerateMock() {
		let error = FixableInstantiableError.customMockNameWithoutMockGeneration
		#expect(error.description == "`customMockName` requires `generateMock: true` or `mockOnly: true`.")
	}

	@Test
	func customMockNameWithoutMockGeneration_fixIt_mentionsAddingGenerateMock() {
		let error = FixableInstantiableError.customMockNameWithoutMockGeneration
		#expect(error.fixIt.message == "Add `generateMock: true` or `mockOnly: true` to `@Instantiable`")
	}

	@Test
	func customMockNameMethodNotFound_description_mentionsMissingMethodName() {
		let error = FixableInstantiableError.customMockNameMethodNotFound("customMock")
		#expect(error.description == "`customMockName` names `customMock`, but this declaration has no method named `customMock`. Add a `public static func customMock(…)` method.")
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
		#expect(error.description == "This `mock()` method’s parameter `extra: Bool` does not correspond to a dependency, so it must have a default value.")
	}

	@Test
	func mockMethodNonDependencyMissingDefaultValue_fixIt_mentionsAddingDefaultValues() {
		let error = FixableInstantiableError.mockMethodNonDependencyMissingDefaultValue([
			Property(label: "extra", typeDescription: .simple(name: "Bool")),
		])
		#expect(error.fixIt.message == "Add default values to `mock()` non-dependency parameters for extra: Bool")
	}

	// MARK: mockOnly Tests

	@Test
	func mockOnlyWithGenerateMock_description_mentionsIncompatibleCombination() {
		let error = FixableInstantiableError.mockOnlyWithGenerateMock
		#expect(error.description == "`mockOnly` and `generateMock` cannot both be `true`: a `mockOnly` declaration provides a hand-written mock. To generate a mock, set `generateMock: true` on the production `@Instantiable` declaration instead.")
	}

	@Test
	func mockOnlyWithGenerateMock_fixIt_mentionsRemovingGenerateMock() {
		let error = FixableInstantiableError.mockOnlyWithGenerateMock
		#expect(error.fixIt.message == "Remove `generateMock: true`")
	}

	@Test
	func mockOnlyWithIsRoot_description_mentionsIncompatibleCombination() {
		let error = FixableInstantiableError.mockOnlyWithIsRoot
		#expect(error.description == "`mockOnly` types cannot be marked `isRoot`.")
	}

	@Test
	func mockOnlyWithIsRoot_fixIt_mentionsRemovingIsRoot() {
		let error = FixableInstantiableError.mockOnlyWithIsRoot
		#expect(error.fixIt.message == "Remove `isRoot: true`")
	}

	@Test
	func mockOnlyMissingMockMethod_description_mentionsRequiredMockMethod() {
		let error = FixableInstantiableError.mockOnlyMissingMockMethod(typeName: "MyService", methodName: "mock")
		#expect(error.description == "@Instantiable(mockOnly: true) requires a `static func mock(…) -> MyService` method.")
	}

	@Test
	func mockOnlyMissingMockMethod_fixIt_mentionsAddingMethod() {
		let error = FixableInstantiableError.mockOnlyMissingMockMethod(typeName: "MyService", methodName: "mock")
		#expect(error.fixIt.message == "Add `public static func mock(…) -> MyService` method")
	}

	@Test
	func unlabeledDefaultBeforeUnlabeledParameter_description_mentionsBothParametersAndRemediations() {
		let error = FixableInstantiableError.unlabeledDefaultBeforeUnlabeledParameter(
			defaultedParameter: Property(label: "enabled", typeDescription: .simple(name: "Bool")),
			followingParameter: Property(label: "leaf", typeDescription: .simple(name: "Leaf")),
		)
		#expect(error.description == "Unlabeled parameter `enabled: Bool` has a default value but is followed by unlabeled required parameter `leaf: Leaf`, so a generated `mock()` cannot leave `enabled` out of its call. Add an argument label to `enabled`, move unlabeled parameters with defaults after the required ones, or remove the default.")
	}

	@Test
	func unlabeledDefaultBeforeUnlabeledParameter_fixIt_describesLabelPromotion() {
		let error = FixableInstantiableError.unlabeledDefaultBeforeUnlabeledParameter(
			defaultedParameter: Property(label: "enabled", typeDescription: .simple(name: "Bool")),
			followingParameter: Property(label: "leaf", typeDescription: .simple(name: "Leaf")),
		)
		#expect(error.fixIt.message == "Add argument label `enabled`")
	}

	@Test
	func calleeScopeReferenceInDefaultExpression_description_mentionsParameter() {
		let error = FixableInstantiableError.calleeScopeReferenceInDefaultExpression(parameterLabel: "name", typeName: "MyService")
		#expect(error.description == "The default value of `name` refers to `Self`. A generated `mock()` repeats this default outside `MyService`, where `Self` names a different type. Write `MyService` instead of `Self`, or remove the default.")
	}

	@Test
	func calleeScopeReferenceInDefaultExpression_fixIt_describesRemediation() {
		let error = FixableInstantiableError.calleeScopeReferenceInDefaultExpression(parameterLabel: "name", typeName: "MyService")
		#expect(error.fixIt.message == "Remove the default from `name` or move the referenced value to a file-scoped or module-scoped symbol")
	}

	@Test
	func reservedName_fixIt_namesOnlyTheReservedName_whenNameIsReservedExactly() {
		// The macro offers no fix-it for an exactly reserved name, which has no evident replacement.
		let error = FixableInstantiableError.reservedName(name: "safeDIOverrides", reservation: .mockOverridesParameter)
		#expect(error.fixIt.message == "Rename `safeDIOverrides`")
	}
}
