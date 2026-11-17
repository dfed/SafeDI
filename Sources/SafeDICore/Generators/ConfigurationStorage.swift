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

/// The fields a generated configuration – a mock's `SafeDIOverrides`, a type's `SafeDIMockConfiguration`, or a public
/// mock's module-level configuration – keeps in one immutable final class, which the configuration reads each field from
/// through a computed property. Every builder function of a mock captures the overrides, and a configuration that held
/// the configurations beneath it by value was copied whole into each, so the code the compiler emitted grew with the
/// square of the mock's paths. Held by reference, a copy is one reference however deep the tree.
///
/// The class is `Sendable` exactly when SafeDI proves each field's type `Sendable`, so a configuration whose fields are
/// all `Sendable` stays `Sendable`, as it was when it stored them. It has the configuration's isolation, as a nested type
/// does, and is `private`, so that how a configuration stores its fields is not part of what callers see.
struct ConfigurationStorage {
	/// A field the storage holds.
	struct Field {
		/// The field's name, which is also the label of the initializer parameter that sets it.
		let name: String
		/// The type the field is stored as and read as.
		let typeSource: String
		/// The type the storage's initializer takes the field as: `typeSource`, spelled `@escaping` where it is a function
		/// type that is not optional.
		let parameterTypeSource: String
		/// What precedes `var` on the property that reads the field: its access level and a space, or nothing.
		let accessPrefix: String
		/// The documentation of the property that reads the field, when it has one.
		let documentation: String?
		/// Whether SafeDI proves the field's type `Sendable`: a `@Sendable` closure, or a configuration whose storage is
		/// `Sendable`.
		let isProvenSendable: Bool
	}

	/// The fields, in the order the configuration's initializers take them.
	let fields: [Field]

	/// The statement that sets the storage to `values`, one for each field in order, indented by `indent`.
	func initialization(to values: [String], indent: String) -> [String] {
		var lines = ["\(indent)\(ReservedName.configurationStoragePropertyName) = \(ReservedName.configurationStorageTypeName)("]
		// A call spells a keyword label without backticks, which Swift warns about where a call escapes one.
		lines.append(zip(fields, values).map { field, value in
			"\(indent)\(ScopeGenerator.standardIndent)\(field.name.spelledAsArgumentLabel): \(value)"
		}.joined(separator: ",\n"))
		lines.append("\(indent))")
		return lines
	}

	/// The computed property that reads each field from the storage, indented by `indent`.
	func readers(indent: String) -> [String] {
		var lines = [String]()
		for field in fields {
			if let documentation = field.documentation {
				lines.append("\(indent)/// \(documentation)")
			}
			lines.append("\(indent)\(field.accessPrefix)var \(field.name.spelledAsMemberDeclarationName): \(field.typeSource) { \(ReservedName.configurationStoragePropertyName).\(field.name) }")
		}
		return lines
	}

	/// The stored property that holds the storage and the storage's class, indented by `indent`.
	func declarations(indent: String) -> [String] {
		let memberIndent = "\(indent)\(ScopeGenerator.standardIndent)"
		let parameterIndent = "\(memberIndent)\(ScopeGenerator.standardIndent)"
		let sendableConformance = fields.allSatisfy(\.isProvenSendable) ? ": Sendable" : ""
		var lines = [
			"\(indent)private let \(ReservedName.configurationStoragePropertyName): \(ReservedName.configurationStorageTypeName)",
			"",
			"\(indent)private final class \(ReservedName.configurationStorageTypeName)\(sendableConformance) {",
			"\(memberIndent)init(",
		]
		// A field is named as a label: declared as a member's name is spelled, `Type` and `Protocol` in backticks, and set from
		// a parameter named apart from `self`.
		lines.append(fields.map { "\(parameterIndent)\($0.name.spelledAsAssigningParameter(labeled: $0.name)): \($0.parameterTypeSource)" }.joined(separator: ",\n"))
		lines.append("\(memberIndent)) {")
		lines.append(contentsOf: fields.map { "\(parameterIndent)self.\($0.name) = \($0.name.spelledAsAssigningParameterName)" })
		lines.append("\(memberIndent)}")
		lines.append("")
		lines.append(contentsOf: fields.map { "\(memberIndent)let \($0.name.spelledAsMemberDeclarationName): \($0.typeSource)" })
		lines.append("\(indent)}")
		return lines
	}
}
