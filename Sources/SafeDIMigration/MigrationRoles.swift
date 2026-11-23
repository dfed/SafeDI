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

import Foundation

/// What each parameter of every `mock()` SafeDI 2.x generates stands for: the one input the rewriter takes besides the
/// sources. Only SafeDI's analysis of the dependency tree knows these roles, so whatever writes this file owns that
/// analysis, and the rewriter owns only syntax. The format is described in `designs/3.0-spikes/migrate-roles-schema.md`.
public struct MigrationRoles: Codable, Equatable, Sendable {
	public init(formatVersion: Int = 0, mockedTypes: [MockedType], labelRedeclarations: [SourceSite] = []) {
		self.formatVersion = formatVersion
		self.mockedTypes = mockedTypes
		self.labelRedeclarations = labelRedeclarations
	}

	public init(contentsOf data: Data) throws {
		self = try JSONDecoder().decode(MigrationRoles.self, from: data)
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		formatVersion = try container.decode(Int.self, forKey: .formatVersion)
		mockedTypes = try container.decode([MockedType].self, forKey: .mockedTypes)
		labelRedeclarations = try container.decodeIfPresent([SourceSite].self, forKey: .labelRedeclarations) ?? []
	}

	public let formatVersion: Int
	public let mockedTypes: [MockedType]
	/// Each declaration that redeclares a label beneath a declaration of the same label on one branch of a tree, which
	/// 3.0 rejects. Only the tree analysis that writes this file can find them; the rewriter reports each.
	public let labelRedeclarations: [SourceSite]

	/// A type whose `mock()` SafeDI 2.x generates.
	public struct MockedType: Codable, Equatable, Sendable {
		public init(type: String, module: String? = nil, isPublic: Bool = false, takesOverrides: Bool, parameters: [Parameter]) {
			self.type = type
			self.module = module
			self.isPublic = isPublic
			self.takesOverrides = takesOverrides
			self.parameters = parameters
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			type = try container.decode(String.self, forKey: .type)
			module = try container.decodeIfPresent(String.self, forKey: .module)
			isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
			takesOverrides = try container.decode(Bool.self, forKey: .takesOverrides)
			parameters = try container.decode([Parameter].self, forKey: .parameters)
		}

		/// The concrete type as SafeDI spells it: nested types dotted, never module-qualified.
		public let type: String
		/// The module that generates the mock, which tells two types of one name apart.
		public let module: String?
		/// Whether the mock is `generateMock: .public`.
		public let isPublic: Bool
		/// Whether 2.x `mock()` takes `safeDIOverrides:`.
		public let takesOverrides: Bool
		/// Every parameter of `mock()` but `safeDIOverrides`, in signature order.
		public let parameters: [Parameter]
	}

	/// One parameter of a generated `mock()`.
	public struct Parameter: Codable, Equatable, Sendable {
		public init(
			label: String,
			role: Role,
			isSendableAutoclosure: Bool = false,
			isClosureType: Bool = false,
			isOptionalType: Bool = false,
			fieldLabel: String? = nil,
			hasFlatParameter: Bool = true,
			overridesField: String? = nil,
			fakeLabel: String? = nil,
			hasConfiguration: Bool = true,
		) {
			self.label = label
			self.role = role
			self.isSendableAutoclosure = isSendableAutoclosure
			self.isClosureType = isClosureType
			self.isOptionalType = isOptionalType
			self.fieldLabel = fieldLabel
			self.hasFlatParameter = hasFlatParameter
			self.overridesField = overridesField
			self.fakeLabel = fakeLabel
			self.hasConfiguration = hasConfiguration
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			label = try container.decode(String.self, forKey: .label)
			role = try container.decode(Role.self, forKey: .role)
			isSendableAutoclosure = try container.decodeIfPresent(Bool.self, forKey: .isSendableAutoclosure) ?? false
			isClosureType = try container.decodeIfPresent(Bool.self, forKey: .isClosureType) ?? false
			isOptionalType = try container.decodeIfPresent(Bool.self, forKey: .isOptionalType) ?? false
			fieldLabel = try container.decodeIfPresent(String.self, forKey: .fieldLabel)
			hasFlatParameter = try container.decodeIfPresent(Bool.self, forKey: .hasFlatParameter) ?? true
			overridesField = try container.decodeIfPresent(String.self, forKey: .overridesField)
			fakeLabel = try container.decodeIfPresent(String.self, forKey: .fakeLabel)
			hasConfiguration = try container.decodeIfPresent(Bool.self, forKey: .hasConfiguration) ?? true
		}

		/// The 2.x argument label, as a call writes it.
		public let label: String
		public let role: Role
		/// For `uncovered`: 2.x takes it as a `@Sendable` autoclosure, already evaluated once per construction.
		public let isSendableAutoclosure: Bool
		/// For `uncovered`: the dependency's own type is a closure that takes nothing, so a closure literal argument
		/// compiles before and after the rewrite with another meaning.
		public let isClosureType: Bool
		/// For `rootDefault`: whether the initializer parameter's own type is optional.
		public let isOptionalType: Bool
		/// For `rootDefault`: the 3.0 configuration field's label, where it is not `label`.
		public let fieldLabel: String?
		/// For `receivedBuildable`: whether 2.x `mock()` takes a flat `label: T? = nil` for it (a public mock does).
		public let hasFlatParameter: Bool
		/// For `receivedBuildable`: the 2.x `SafeDIOverrides` field that configures the same dependency.
		public let overridesField: String?
		/// For `publicMockBuilder`: the 3.0 `fake()` label, the place's property label (sub-decision 1, Dan 2026-11-23),
		/// where it is not `label`.
		public let fakeLabel: String?
		/// For `receivedBuildable`: whether the dependency's type has anything to configure. Where it has nothing,
		/// 3.0 keeps a plain `label: T? = nil` (sub-decision 4, Dan 2026-11-23).
		public let hasConfiguration: Bool
	}

	/// What a parameter stands for; see the schema's table of roles.
	public enum Role: String, Codable, Equatable, Sendable, CaseIterable {
		/// A `@Forwarded` property of the mocked type. Unchanged.
		case forwarded
		/// A received value no node of the tree builds. Unchanged.
		case outsideValue
		/// An `@Instantiated` dependency nothing in the tree can build: a builder `() -> T` in 3.0.
		case uncovered
		/// The mocked type's own default-valued initializer parameter: a `safeDIOverrides` field in 3.0.
		case rootDefault
		/// A received dependency the mock builds: one `SafeDIReceived` parameter in 3.0.
		case receivedBuildable
		/// A builder a seam's own internal mock takes for its holes. Unchanged.
		case holeBuilder
		/// A builder a public mock takes. Unchanged.
		case publicMockBuilder
	}
}

/// A place in a source file.
public struct SourceSite: Codable, Comparable, Hashable, Sendable {
	public init(path: String, line: Int, column: Int) {
		self.path = path
		self.line = line
		self.column = column
	}

	public let path: String
	public let line: Int
	public let column: Int

	public static func < (lhs: SourceSite, rhs: SourceSite) -> Bool {
		(lhs.path, lhs.line, lhs.column) < (rhs.path, rhs.line, rhs.column)
	}
}
