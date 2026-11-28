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
	/// A module info file the Bazel rule writes stores a range’s lines and columns in a positions file of their own
	/// (`--module-info-positions-in-own-file`), which a dependent opens only to report a diagnostic, so a line moved in a
	/// module leaves the module info file its dependents read unchanged. Read without that file, the range is
	/// ``Placement-swift.enum/storedElsewhere``: only a diagnostic prints a range, and a run that would print one reads the
	/// positions files and runs again.
	public struct SourceRange: Codable, Hashable, Sendable {
		public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
			placement = .here(startLine: startLine, startColumn: startColumn, endLine: endLine, endColumn: endColumn)
		}

		public init(placement: Placement) {
			self.placement = placement
		}

		/// The empty range where `location` begins, which an insertion replaces.
		public static func insertionPoint(at location: DeclarationLocation) -> SourceRange {
			switch location.placement {
			case let .here(line, column):
				SourceRange(startLine: line, startColumn: column, endLine: line, endColumn: column)
			case .storedElsewhere:
				SourceRange(placement: .storedElsewhere)
			}
		}

		/// Where the range’s lines and columns are.
		public enum Placement: Codable, Hashable, Sendable {
			/// The one-based line and column of the range’s first character, and those of the character after its last one,
			/// so the end column is exclusive.
			case here(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int)
			/// In the positions file of the module info file the range was read from, which the run did not read.
			case storedElsewhere
		}

		public let placement: Placement

		/// Coded as `startLine`, `startColumn`, `endLine` and `endColumn`, as before ranges could be stored elsewhere, and
		/// as nothing where they are, so `dump` prints a module info file that stores its positions with it as it always has.
		private enum CodingKeys: String, CodingKey {
			case startLine
			case startColumn
			case endLine
			case endColumn
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			placement = if let startLine = try container.decodeIfPresent(Int.self, forKey: .startLine) {
				try .here(
					startLine: startLine,
					startColumn: container.decode(Int.self, forKey: .startColumn),
					endLine: container.decode(Int.self, forKey: .endLine),
					endColumn: container.decode(Int.self, forKey: .endColumn),
				)
			} else {
				.storedElsewhere
			}
		}

		public func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			if case let .here(startLine, startColumn, endLine, endColumn) = placement {
				try container.encode(startLine, forKey: .startLine)
				try container.encode(startColumn, forKey: .startColumn)
				try container.encode(endLine, forKey: .endLine)
				try container.encode(endColumn, forKey: .endColumn)
			}
		}
	}

	/// The file, line, and column at which a declaration begins.
	///
	/// Read from a module info file the Bazel rule writes, a location keeps its file and its ``order`` there, and its line
	/// and column are ``Placement-swift.enum/storedElsewhere``, in the file’s positions file (``SourceRange`` says why).
	/// Two locations compare and equate by their file and their line and column when both hold them, and otherwise by
	/// their file and their order, which ranks the location among every location the module recorded in its file: the
	/// two agree, so every comparison a run makes comes out as it would with every position read. Ranks agree with
	/// positions only among the locations of one module info file. A source file compiled into two modules is ranked in
	/// each, so its ranks from two modules, or a rank beside the run’s own unranked location of that file, say nothing
	/// about which comes first. No successful run is known to compare them: each type is declared by one module, and
	/// two modules that declare one name fail the run, which then reads every position.
	public struct DeclarationLocation: Codable, Hashable, Sendable {
		public init(filePath: String, line: Int, column: Int) {
			self.filePath = filePath
			order = 0
			placement = .here(line: line, column: column)
		}

		public init(filePath: String, order: Int, placement: Placement) {
			self.filePath = filePath
			self.order = order
			self.placement = placement
		}

		/// Where the location’s line and column are.
		public enum Placement: Codable, Hashable, Sendable {
			/// The one-based line on which the declaration begins (its first attribute), and the one-based column.
			case here(line: Int, column: Int)
			/// In the positions file of the module info file the location was read from, which the run did not read.
			case storedElsewhere
		}

		/// The path to the file containing the declaration, exactly as it was provided to the parser.
		public let filePath: String
		/// The location’s rank, from 1, among the distinct locations its module recorded in its file, in source order, where
		/// a module info file stores positions in a positions file of their own; 0 where nothing ranked it.
		public let order: Int
		/// Where the location’s line and column are.
		public let placement: Placement

		/// This location with its file path respelled by `spelling`.
		public func respellingFilePath(_ spelling: (String) -> String) -> DeclarationLocation {
			DeclarationLocation(filePath: spelling(filePath), order: order, placement: placement)
		}

		/// Whether the two are one location: by line and column where both hold them, and otherwise by order. A module info
		/// file writes each location it ranks either with its line and column or without them, never both, so two locations
		/// that equate by order are never one with them and one without.
		public static func == (lhs: DeclarationLocation, rhs: DeclarationLocation) -> Bool {
			guard lhs.filePath == rhs.filePath else { return false }
			return switch (lhs.placement, rhs.placement) {
			case (.here, .here):
				lhs.placement == rhs.placement
			case (.here, .storedElsewhere), (.storedElsewhere, .here), (.storedElsewhere, .storedElsewhere):
				lhs.order == rhs.order
			}
		}

		/// Coded as `filePath`, `line` and `column`, as before locations were ranked, with `order` only where a module info
		/// file ranked the location, and without `line` and `column` where they are stored elsewhere, so `dump` prints a
		/// module info file that stores its positions with it as it always has.
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
			placement = if let line = try container.decodeIfPresent(Int.self, forKey: .line) {
				try .here(line: line, column: container.decode(Int.self, forKey: .column))
			} else {
				.storedElsewhere
			}
		}

		public func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(filePath, forKey: .filePath)
			if order != 0 {
				try container.encode(order, forKey: .order)
			}
			if case let .here(line, column) = placement {
				try container.encode(line, forKey: .line)
				try container.encode(column, forKey: .column)
			}
		}

		/// Hashes what `==` compares.
		public func hash(into hasher: inout Hasher) {
			hasher.combine(filePath)
			switch placement {
			case .here:
				hasher.combine(placement)
			case .storedElsewhere:
				hasher.combine(order)
			}
		}

		/// The line and column, or `nil` where they are stored elsewhere, which only a run that did not read another
		/// module’s positions file sees.
		public var lineAndColumn: (line: Int, column: Int)? {
			if case let .here(line, column) = placement {
				(line, column)
			} else {
				nil
			}
		}

		/// A string that two locations share exactly when they are equal.
		public var identity: String {
			switch placement {
			case let .here(line, column):
				"\(filePath):\(line):\(column)"
			case .storedElsewhere:
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
