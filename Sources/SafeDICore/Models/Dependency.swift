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
	///
	/// A range a module records in its `.safedi` file is stored without its lines and columns, as every location there is
	/// (``DeclarationLocation``), so a line moved in a module leaves the file its dependents read unchanged. Read back, it
	/// is ``Span-swift.enum/unlocated(owner:part:)``: the declaration it belongs to and which part of that declaration it
	/// spans, which a run that reads the owner's file again can find.
	public struct SourceRange: Codable, Hashable, Sendable {
		public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
			span = .located(startLine: startLine, startColumn: startColumn, endLine: endLine, endColumn: endColumn)
		}

		/// The range of `part` of the declaration at `owner`, read without its lines and columns.
		public init(owner: DeclarationLocation, part: Part) {
			span = .unlocated(owner: owner, part: part)
		}

		/// The empty range where `location` begins, which an insertion replaces.
		public static func insertionPoint(at location: DeclarationLocation) -> SourceRange {
			if let position = location.position {
				SourceRange(startLine: position.line, startColumn: position.column, endLine: position.line, endColumn: position.column)
			} else {
				SourceRange(owner: location, part: .insertionPoint)
			}
		}

		/// Where the range is.
		public enum Span: Hashable, Sendable {
			/// The one-based line and column of the range’s first character, and those of the character after its last one,
			/// so the end column is exclusive.
			case located(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int)
			/// Read from another module’s `.safedi` file, which stores no line or column: `part` of the declaration that
			/// begins at `owner`, a location ranked in its file.
			case unlocated(owner: DeclarationLocation, part: Part)
		}

		/// The part of its declaration an unlocated range spans: what a run that reads the declaration’s file again finds
		/// the range of.
		public enum Part: String, Codable, Hashable, Sendable, CaseIterable {
			/// The dependency’s identifier (`Dependency.identifierRange`).
			case identifier
			/// The dependency’s type annotation (`Dependency.typeAnnotationRange`).
			case typeAnnotation
			/// The dependency’s attribute, written without arguments (`Dependency.bareAttributeRange`).
			case bareAttribute
			/// The declaration’s access modifier (`AccessDeclaration.modifierRange`).
			case accessModifier
			/// The value of the `@Instantiable` macro’s `generateMock:` argument (`Instantiable.mockGenerationArgumentRange`).
			case mockGenerationArgument
			/// The empty range where the declaration begins (``SourceRange/insertionPoint(at:)``).
			case insertionPoint
		}

		public let span: Span

		/// Coded as `startLine`, `startColumn`, `endLine` and `endColumn` where the range holds them, and otherwise as the
		/// `owner` and `part` it was read with, so `dump` prints either.
		private enum CodingKeys: String, CodingKey {
			case startLine
			case startColumn
			case endLine
			case endColumn
			case owner
			case part
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			span = if let startLine = try container.decodeIfPresent(Int.self, forKey: .startLine) {
				try .located(
					startLine: startLine,
					startColumn: container.decode(Int.self, forKey: .startColumn),
					endLine: container.decode(Int.self, forKey: .endLine),
					endColumn: container.decode(Int.self, forKey: .endColumn),
				)
			} else {
				try .unlocated(
					owner: container.decode(DeclarationLocation.self, forKey: .owner),
					part: container.decode(Part.self, forKey: .part),
				)
			}
		}

		public func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			switch span {
			case let .located(startLine, startColumn, endLine, endColumn):
				try container.encode(startLine, forKey: .startLine)
				try container.encode(startColumn, forKey: .startColumn)
				try container.encode(endLine, forKey: .endLine)
				try container.encode(endColumn, forKey: .endColumn)
			case let .unlocated(owner, part):
				try container.encode(owner, forKey: .owner)
				try container.encode(part, forKey: .part)
			}
		}
	}

	/// The file, line, and column at which a declaration begins.
	///
	/// Read from a module’s `.safedi` file, a location keeps its file and its ``order`` there, and no ``position``: the
	/// file stores no line or column, so a line moved in a module changes no file its dependents read. Two locations
	/// compare and equate by their file and their position when both hold one, and otherwise by their file and their
	/// order, which ranks the location among every location the module recorded in its file: the two agree, so every
	/// comparison a run makes comes out as it would with every position read. Ranks agree with positions only among the
	/// locations of one module’s file. A source file compiled into two modules is ranked in each, so its ranks from two
	/// modules, or a rank beside the run’s own location of that file, say nothing about which comes first. No successful
	/// run is known to compare them: each type is declared by one module, and two modules that declare one name fail the
	/// run.
	public struct DeclarationLocation: Codable, Hashable, Sendable {
		public init(filePath: String, line: Int, column: Int) {
			self.init(filePath: filePath, order: 0, position: Position(line: line, column: column))
		}

		/// A location read from a module’s `.safedi` file, ranked `order` among those the module recorded in its file.
		public init(filePath: String, order: Int) {
			self.init(filePath: filePath, order: order, position: nil)
		}

		private init(filePath: String, order: Int, position: Position?) {
			self.filePath = filePath
			self.order = order
			self.position = position
		}

		/// A line and column in a file.
		public struct Position: Codable, Hashable, Sendable, Comparable {
			public init(line: Int, column: Int) {
				self.line = line
				self.column = column
			}

			/// The one-based line on which the declaration begins (its first attribute).
			public let line: Int
			/// The one-based column.
			public let column: Int

			public static func < (lhs: Position, rhs: Position) -> Bool {
				(lhs.line, lhs.column) < (rhs.line, rhs.column)
			}
		}

		/// The path to the file containing the declaration, exactly as it was provided to the parser.
		public let filePath: String
		/// The location’s rank, from 1, among the distinct locations its module recorded in its file, in source order, where
		/// it was read from a `.safedi` file; 0 where nothing ranked it.
		public let order: Int
		/// The line and column, or `nil` for a location read from a `.safedi` file, which stores none.
		public let position: Position?

		/// This location with its file path respelled by `spelling`.
		public func respellingFilePath(_ spelling: (String) -> String) -> DeclarationLocation {
			DeclarationLocation(filePath: spelling(filePath), order: order, position: position)
		}

		/// Whether the two are one location: by position where both hold one, and otherwise by order. A location holds a
		/// position or a rank, never both, so two locations that equate by order are never one with a position and one
		/// without.
		public static func == (lhs: DeclarationLocation, rhs: DeclarationLocation) -> Bool {
			guard lhs.filePath == rhs.filePath else { return false }
			return if let lhsPosition = lhs.position, let rhsPosition = rhs.position {
				lhsPosition == rhsPosition
			} else {
				lhs.order == rhs.order
			}
		}

		/// Coded as `filePath`, `line` and `column`, as before locations were ranked, with `order` only where the location
		/// is ranked, and without `line` and `column` where it holds no position.
		private enum CodingKeys: String, CodingKey {
			case filePath
			case line
			case column
			case order
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			filePath = try container.decode(String.self, forKey: .filePath)
			order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
			position = if let line = try container.decodeIfPresent(Int.self, forKey: .line) {
				try Position(line: line, column: container.decode(Int.self, forKey: .column))
			} else {
				nil
			}
		}

		public func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(filePath, forKey: .filePath)
			if order != 0 {
				try container.encode(order, forKey: .order)
			}
			if let position {
				try container.encode(position.line, forKey: .line)
				try container.encode(position.column, forKey: .column)
			}
		}

		/// Hashes what `==` compares.
		public func hash(into hasher: inout Hasher) {
			hasher.combine(filePath)
			if let position {
				hasher.combine(position)
			} else {
				hasher.combine(order)
			}
		}

		/// A string that two locations share exactly when they are equal.
		public var identity: String {
			if let position {
				"\(filePath):\(position.line):\(position.column)"
			} else {
				"\(filePath)#\(order)"
			}
		}
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

	// MARK: Internal

	static let instantiatorType = "Instantiator"
	static let erasedInstantiatorType = "ErasedInstantiator"
	static let sendableInstantiatorType = "SendableInstantiator"
	static let sendableErasedInstantiatorType = "SendableErasedInstantiator"
	static let lazilyInstantiatedType = "LazilyInstantiated"
	static let sendableLazilyInstantiatedType = "SendableLazilyInstantiated"
	/// The name of SafeDI's own module, which may qualify the names of its macros and wrappers.
	static let safeDIModuleName = "SafeDI"

	/// Whether `name` is the name of one of SafeDI's wrappers: an instantiator or a lazily instantiated wrapper.
	static func isWrapperTypeName(_ name: String) -> Bool {
		switch name {
		case instantiatorType, erasedInstantiatorType, sendableInstantiatorType, sendableErasedInstantiatorType, lazilyInstantiatedType, sendableLazilyInstantiatedType:
			true
		default:
			false
		}
	}

	/// The associated type of `Instantiable` that names what an `Instantiator` of the conforming type forwards.
	static let forwardedPropertiesType = "ForwardedProperties"
	/// The function type each instantiator declares, nested in it, that it is created with.
	static let wrapperBuilderTypeName = "Builder"
	/// The property of `LazilyInstantiated` and `SendableLazilyInstantiated` that vends the lazily instantiated instance.
	static let lazilyInstantiatedInstancePropertyName = "instance"
}

extension Dependency {
	/// The by-value property with which types further down the tree receive the instance of the lazily
	/// instantiated property this dependency puts in scope. `nil` when it puts none in scope: a received
	/// dependency declares nothing, whichever type it is.
	var lazilyInstantiatedInstanceProperty: Property? {
		switch source {
		case .instantiated:
			property.asLazilyInstantiatedInstanceProperty
		case .aliased, .forwarded:
			property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding
		case .received:
			nil
		}
	}

	/// The dependency’s property, followed by `lazilyInstantiatedInstanceProperty` when there is one.
	var receivableProperties: [Property] {
		if let lazilyInstantiatedInstanceProperty {
			[property, lazilyInstantiatedInstanceProperty]
		} else {
			[property]
		}
	}
}

extension Dependency.Source {
	/// Whether the dependency is `@Received` under its declared label and type. An aliased dependency is not: the
	/// generated code binds it from its fulfilling property. Cycle validation counts a required alias as receiving
	/// that property; see `DependencyTreeGenerator.closingReceive(of:in:)`.
	var isReceived: Bool {
		switch self {
		case .received:
			true
		case .instantiated, .aliased, .forwarded:
			false
		}
	}

	/// Whether the dependency is `@Instantiated`.
	var isInstantiated: Bool {
		switch self {
		case .instantiated:
			true
		case .received, .aliased, .forwarded:
			false
		}
	}
}

extension Dependency {
	/// Whether the dependency is `@Instantiated(onlyIfAvailable: true)`: instantiated where a production declaration the
	/// module reads fulfills its type (`DependencyTreeGenerator.instantiates(_:)`), and `nil` where none does. Read from
	/// the property's type, since the macro accepts an optional `@Instantiated` property only with that argument: the
	/// argument is stored nowhere, so no `.safedi` file or cache carries it.
	public var isInstantiatedOnlyIfAvailable: Bool {
		source.isInstantiated && property.typeDescription.isOptional
	}
}

extension Dependency {
	/// Whether the dependency receives an instantiator of any kind, received or through an alias, which a loop of builders
	/// can rebind (`ReceivedBuilderLoops`).
	var receivesInstantiator: Bool {
		let receivedProperty: Property
		switch source {
		case .received:
			receivedProperty = property
		case let .aliased(fulfillingProperty, _, _):
			receivedProperty = fulfillingProperty
		case .instantiated, .forwarded:
			return false
		}
		switch receivedProperty.propertyType {
		case .instantiator, .erasedInstantiator, .sendableInstantiator, .sendableErasedInstantiator:
			return true
		case .constant, .lazilyInstantiated, .sendableLazilyInstantiated:
			return false
		}
	}
}
