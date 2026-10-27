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

import SwiftSyntax

/// A representation of a dependency.
/// e.g. `@Instantiated let myService: MyService`
public struct Dependency: Codable, Hashable, Sendable {
	// MARK: Initialization

	public init(
		property: Property,
		source: Dependency.Source,
		declarationLocation: DeclarationLocation? = nil,
		identifierRange: SourceRange? = nil,
		typeAnnotationRange: SourceRange? = nil,
		bareAttributeRange: SourceRange? = nil,
	) {
		self.property = property
		self.source = source
		self.declarationLocation = declarationLocation
		self.identifierRange = identifierRange
		self.typeAnnotationRange = typeAnnotationRange
		self.bareAttributeRange = bareAttributeRange
		switch source {
		case .received, .forwarded:
			asInstantiatedType = property.typeDescription.asInstantiatedType
		case let .instantiated(fulfillingTypeDescription, _):
			asInstantiatedType = (fulfillingTypeDescription ?? property.typeDescription).asInstantiatedType
		case let .aliased(fulfillingProperty, _, _):
			asInstantiatedType = fulfillingProperty.typeDescription.asInstantiatedType
		}
	}

	// MARK: Public

	/// A representation of the dependency as it is declared on its `@Instantiable` type.
	public let property: Property
	/// The source of the dependency within the dependency tree.
	public let source: Source
	/// The receiver’s type description as an `@Instantiable`-decorated type.
	public let asInstantiatedType: TypeDescription
	/// Where the dependency’s property is declared in source.
	/// `nil` only when the dependency was parsed without a file context – macro expansion walks a detached
	/// declaration – and such values never reach the dependency tree generator, which only consumes
	/// dependencies that `SafeDITool` parsed from files.
	public let declarationLocation: DeclarationLocation?

	/// The source range of the dependency’s identifier token – the property name, or the parameter name of an
	/// extension’s `instantiate` – which a fix-it can replace.
	/// `nil` only when the dependency was parsed without a file context – macro expansion walks a detached
	/// declaration – and such values never reach the dependency tree generator, which only consumes
	/// dependencies that `SafeDITool` parsed from files.
	public let identifierRange: SourceRange?

	/// The source range of the dependency’s type annotation – the property’s type, or the parameter type of an
	/// extension’s `instantiate` – which a fix-it can replace.
	/// `nil` only when the dependency was parsed without a file context – macro expansion walks a detached
	/// declaration – and such values never reach the dependency tree generator, which only consumes
	/// dependencies that `SafeDITool` parsed from files.
	public let typeAnnotationRange: SourceRange?

	/// The source range of the attribute that decorates the dependency’s property – `@Instantiated`, `@Received`,
	/// or `@Forwarded` – recorded only when that attribute is written without arguments, so a fix-it that rewrites
	/// the whole attribute never discards arguments the user wrote.
	/// `nil` when the attribute has arguments, for an extension’s `instantiate` parameter (which has no attribute),
	/// and when the dependency was parsed without a file context – macro expansion walks a detached declaration –
	/// and such values never reach the dependency tree generator.
	public let bareAttributeRange: SourceRange?

	/// A range of source text in the file that declares the dependency, which is the file of its `declarationLocation`.
	/// The range carries no file path of its own: every dependency records three ranges, and module info is
	/// serialized and read back on every build, so repeating the path in each one is measurable.
	public struct SourceRange: Codable, Hashable, Sendable {
		public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
			self.startLine = startLine
			self.startColumn = startColumn
			self.endLine = endLine
			self.endColumn = endColumn
		}

		/// The one-based line of the first character of the range.
		public let startLine: Int
		/// The one-based column of the first character of the range.
		public let startColumn: Int
		/// The one-based line of the character after the last one in the range.
		public let endLine: Int
		/// The one-based column of the character after the last one in the range, so the end column is exclusive.
		public let endColumn: Int
	}

	/// The file, line, and column at which a declaration begins.
	public struct DeclarationLocation: Codable, Hashable, Sendable {
		public init(filePath: String, line: Int, column: Int) {
			self.filePath = filePath
			self.line = line
			self.column = column
		}

		/// The path to the file containing the declaration, exactly as it was provided to the parser.
		public let filePath: String
		/// The one-based line on which the declaration begins (its first attribute).
		public let line: Int
		/// The one-based column at which the declaration begins (its first attribute).
		public let column: Int
	}

	public enum Source: Codable, Hashable, Sendable {
		case instantiated(fulfillingTypeDescription: TypeDescription?, erasedToConcreteExistential: Bool)
		case received(onlyIfAvailable: Bool)
		case aliased(fulfillingProperty: Property, erasedToConcreteExistential: Bool, onlyIfAvailable: Bool)
		case forwarded

		public init?(node: AttributeListSyntax.Element) {
			if let instantiatedMacro = node.instantiatedMacro {
				self = .instantiated(
					fulfillingTypeDescription: instantiatedMacro.fulfillingTypeDescription,
					erasedToConcreteExistential: instantiatedMacro.erasedToConcreteExistentialValue,
				)
			} else if let receivedMacro = node.receivedMacro {
				if let fulfillingPropertyName = receivedMacro.fulfillingPropertyName,
				   let fulfillingTypeDescription = receivedMacro.fulfillingTypeDescription
				{
					self = .aliased(
						fulfillingProperty: Property(
							label: fulfillingPropertyName,
							typeDescription: fulfillingTypeDescription,
						),
						erasedToConcreteExistential: receivedMacro.erasedToConcreteExistentialValue,
						onlyIfAvailable: receivedMacro.onlyIfAvailableValue,
					)
				} else {
					self = .received(onlyIfAvailable: receivedMacro.onlyIfAvailableValue)
				}
			} else if node.forwardedMacro != nil {
				self = .forwarded
			} else {
				return nil
			}
		}

		public var fulfillingProperty: Property? {
			switch self {
			case let .aliased(fulfillingProperty, _, _):
				fulfillingProperty
			case .instantiated, .received, .forwarded:
				nil
			}
		}

		public static let instantiatedRawValue = "Instantiated"
		public static let receivedRawValue = "Received"
		public static let forwardedRawValue = "Forwarded"
	}

	/// The prefix of the names SafeDI generates beside the names it is given: each builder function in a
	/// generated `init()` or `mock()` is `__safeDI_<label>`, declared next to the `let <label>` it builds.
	/// A name SafeDI is given that began with the prefix could share its name with such a function, so the
	/// `@Instantiable` macro rejects it (`isReservedName(_:)`).
	public static let reservedNamePrefix = "__safeDI_"

	/// Whether `name` begins with `reservedNamePrefix`. The comparison is byte for byte, as generated code
	/// spells the name it prefixes.
	public static func isReservedName(_ name: String) -> Bool {
		name.utf8.starts(with: reservedNamePrefix.utf8)
	}

	/// `name` without its leading `reservedNamePrefix`. `name` must begin with the prefix.
	public static func removingReservedNamePrefix(from name: String) -> String {
		String(String.UnicodeScalarView(name.unicodeScalars.dropFirst(reservedNamePrefix.unicodeScalars.count)))
	}

	// MARK: Internal

	static let instantiatorType = "Instantiator"
	static let erasedInstantiatorType = "ErasedInstantiator"
	static let sendableInstantiatorType = "SendableInstantiator"
	static let sendableErasedInstantiatorType = "SendableErasedInstantiator"
	static let lazilyInstantiatedType = "LazilyInstantiated"
	static let sendableLazilyInstantiatedType = "SendableLazilyInstantiated"
	/// The property of `LazilyInstantiated` and `SendableLazilyInstantiated` that vends the lazily instantiated instance.
	static let lazilyInstantiatedInstancePropertyName = "instance"
}
