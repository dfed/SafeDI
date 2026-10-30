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

/// A name that SafeDI’s generated code introduces into a scope where it also binds, or refers to, the names it is
/// given: property labels, `fulfilledByDependencyNamed:` names, `instantiate(…)` parameter names, and the argument
/// labels a generated `mock()` takes. A name SafeDI is given that is reserved would collide with the generated one,
/// so the `@Instantiable` macro rejects it.
///
/// Generated code spells each of these names through this type, so a name cannot be generated without being reserved.
public enum ReservedName: Hashable, Sendable {
	/// A name that begins with `builderFunctionNamePrefix`, the prefix of each builder function a generated `init()`
	/// or `mock()` declares (`__safeDI_<label>`, next to the `let <label>` it builds), of the locals a `@Sendable`
	/// builder function captures, and of the local a `mock()` reads each `@Sendable` autoclosure parameter into.
	case builderFunctionName
	/// `mockOverridesParameterName`, the parameter through which a generated `mock()` takes its overrides. A mock
	/// parameter of the same name redeclares it, and a binding of the same name in the mock's body hides it from the
	/// reads of the overrides that follow.
	case mockOverridesParameter
	/// `configurationBuilderPropertyName`, the property and initializer parameter of each generated
	/// `SafeDIMockConfiguration` that overrides how its type is built, beside one property for each dependency the
	/// configured type instantiates and each of its default-valued parameters, which a name of the same spelling
	/// redeclares.
	case configurationBuilderProperty
	/// The name of a type that generated code constructs by name (`Instantiator<T>(…)`). A binding of the same name
	/// hides the type from the code generated in its scope.
	case constructedType(String)

	// MARK: Initialization

	/// The reserved name `name` collides with, or `nil` when it collides with none.
	public init?(reserving name: String) {
		if name.utf8.starts(with: Self.builderFunctionNamePrefix.utf8) {
			self = .builderFunctionName
		} else if name == Self.mockOverridesParameterName {
			self = .mockOverridesParameter
		} else if name == Self.configurationBuilderPropertyName {
			self = .configurationBuilderProperty
		} else if Self.constructedTypeNames.contains(name) {
			self = .constructedType(name)
		} else {
			return nil
		}
	}

	// MARK: Public

	/// The prefix of the name of each builder function generated code declares. The prefix keeps these names out of
	/// the namespace of the names SafeDI is given.
	public static let builderFunctionNamePrefix = "__safeDI_"
	/// The name of the parameter through which a generated `mock()` takes its overrides. Callers of a generated
	/// `mock()` spell it, so it never changes.
	public static let mockOverridesParameterName = "safeDIOverrides"
	/// The name of the property, and initializer parameter, of each generated `SafeDIMockConfiguration` that
	/// overrides how its type is built, and of the binding of that override in a construction expression.
	public static let configurationBuilderPropertyName = "safeDIBuilder"

	/// `name`, which must begin with `builderFunctionNamePrefix`, without the prefix.
	public static func removingBuilderFunctionNamePrefix(from name: String) -> String {
		String(String.UnicodeScalarView(name.unicodeScalars.dropFirst(builderFunctionNamePrefix.unicodeScalars.count)))
	}

	// MARK: Internal

	/// The names of the types generated code constructs by name: the wrapper of each kind of property that is not
	/// a constant, which generated code builds with its builder function.
	static let constructedTypeNames = Set(Property.PropertyType.allCases.compactMap(\.wrapperTypeName))
}
