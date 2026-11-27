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

/// Mock generation: lowers each mock root's code from its finished generator tree, reading the generators and the
/// module's frozen maps and writing nothing they hold.
public enum MockLowering {
	/// A mock root's code, with the configurations its tree's nodes are configured by, in the order its walk finished them
	/// (`ConfigurationRecord`), from which the configuration structs are lowered.
	public struct Result: Sendable, Equatable {
		let code: String
		let configurations: [ConfigurationRecord]

		init(code: String, configurations: [ConfigurationRecord] = []) {
			self.code = code
			self.configurations = configurations
		}
	}

	/// A configuration a node of a mock's tree is configured by: what the `SafeDIMockConfiguration` of its concrete type,
	/// generated from that node, holds. Recorded per node and construction in the order the walk finishes the nodes,
	/// children first, never keyed by a generator, since one generator can build a type at two places.
	public struct ConfigurationRecord: Sendable, Equatable {
		/// The concrete type the configuration is nested in.
		let concreteType: TypeDescription
		/// Whether the node is built with its type's hand-written mock.
		let usesMockInitializer: Bool
		// A record keeps what spells its fields, which only the record a configuration is generated
		// from spells, once per type rather than once per node.
		/// What spells the configuration's fields for the node's children, in the order its initializer takes them.
		let childFieldSources: [ChildFieldSource]
		// A record keeps the parameters its override closure is handed, not the node's whole
		// `Instantiable`, which building each record would copy.
		/// The parameters of the node's construction that the closure that overrides it is handed.
		let builderParameters: MockLowering.BuilderParameters
		// A public mock's node, whose type's module-level configuration and construction functions are
		// lowered in `MockLowering+PublicConfigurations.swift`.
		/// Where a public mock builds the node, the construction it builds the node's type with: `nil` in an internal mock.
		var publicConstruction: PublicConstructionRecord?
		// The fields for the node's construction's default-valued parameters.
		/// The configuration's fields for the node's construction's default-valued parameters, after its children's.
		var defaultFields: [DefaultField]
		// What the one-way check reads of the node (`MockLowering+OneWay.swift`).
		/// The construction the node builds its type with, as the one-way check reads it.
		var oneWayConstruction: OneWayConstruction?
		// A node beneath a repeated ancestor (`MockLowering+Configurations.swift`).
		/// Where the node is beneath a node whose type repeats one around it, what the module's choice of such a node reads.
		var beneathRepeatedAncestor: BeneathRepeatedAncestor?
		// What a configuration generated from the record makes the shared configuration file import.
		/// The declarations whose modules code that builds the node's type for its property needs imported, where it does
		/// not name them (`FulfillerImports.Fulfiller.fulfillers(building:forPropertyOfType:callingHandWrittenMock:)`).
		var fulfillers = Set<FulfillerImports.Fulfiller>()

		/// The configuration's fields for the node's children, in the order its initializer takes them.
		var childFields: [ChildField] {
			childFieldSources.map(\.childField)
		}

		/// The type of the closure that overrides how the node is built, returning its concrete type.
		var concreteBuilderClosureType: String {
			"(\(builderParameters.spelled)) -> \(concreteType.asSource)"
		}

		/// What spells a child's field: a node the tree builds, spelled when the field is read, or a field already spelled.
		enum ChildFieldSource: Sendable, Equatable {
			/// A node of `concreteType`, bound as `bindingName`, whose field is its configuration where `hasConfiguration`,
			/// else an optional builder closure handed `builderParameters` and returning `propertyType`, `@Sendable` where
			/// `requiresSendable`.
			case built(bindingName: String, hasConfiguration: Bool, requiresSendable: Bool, concreteType: TypeDescription, builderParameters: MockLowering.BuilderParameters, propertyType: TypeDescription)
			case spelled(ChildField)

			var childField: ChildField {
				switch self {
				case let .built(bindingName, hasConfiguration, requiresSendable, concreteType, builderParameters, propertyType):
					let configuredTypeName = concreteType.asSource
					if hasConfiguration {
						let typeSource = "\(configuredTypeName).\(ScopeGenerator.mockConfigurationStructName)"
						return ChildField(name: bindingName, typeSource: typeSource, defaultValue: ".init()", sendableForm: .init(typeSource: typeSource, defaultValue: ".init()", configuredTypeName: configuredTypeName))
					} else {
						let builderClosureType = "(\(builderParameters.spelled)) -> \(propertyType.asInstantiatedTypeSpelledAsDeclared.asSource)"
						return ChildField(name: bindingName, typeSource: "(\(requiresSendable ? "@Sendable " : "")\(builderClosureType))?", defaultValue: "nil", sendableForm: .init(typeSource: "(@Sendable \(builderClosureType))?", defaultValue: "nil", configuredTypeName: nil))
					}
				case let .spelled(childField):
					return childField
				}
			}
		}

		/// A field that configures a child of the node: its configuration, or an optional builder closure.
		struct ChildField: Sendable, Equatable {
			let name: String
			let typeSource: String
			let defaultValue: String
			/// The field in a configuration `@Sendable`-typed (`ScopeGenerator.configurationField`'s `parentRequiresSendable`),
			/// or `nil` for a node that has none there.
			var sendableForm: SendableForm?

			/// A child's field in a configuration `@Sendable`-typed: a `@Sendable` closure, which is `Sendable`, or the
			/// child's configuration, `Sendable` where it is `@Sendable`-typed too.
			struct SendableForm: Sendable, Equatable {
				let typeSource: String
				let defaultValue: String
				/// The type whose configuration the field is, which proves it `Sendable` where that configuration is
				/// `@Sendable`-typed; `nil` for a `@Sendable` closure, always `Sendable`.
				let configuredTypeName: String?
			}
		}
	}

	/// A construction a public mock's tree builds a type with, through a function in the type's extension
	/// (`__safeDI_init` or `__safeDI_mock`), from which the type's module-level configuration
	/// (`__safeDI_<Module>_<Type>_MockConfiguration`), its extension's construction functions and the call of a construction
	/// function are lowered (`MockLowering+PublicConfigurations.swift`). Recorded per node in the order the walk finishes the
	/// nodes, as a `ConfigurationRecord` is.
	struct PublicConstructionRecord: Sendable, Equatable {
		/// The concrete type built.
		let concreteType: TypeDescription
		/// Whether the type is built with its hand-written mock (`__safeDI_mock`) rather than its initializer (`__safeDI_init`).
		let usesMockInitializer: Bool
		/// Whether the type is built with an extension's `instantiate(…)`.
		let isExtensionBased: Bool
		/// The name of the hand-written mock method, where it is not `mock`.
		let customMockName: String?
		/// The attributes the initializer or hand-written mock spells, as written, which the construction function repeats.
		let constructionAttributes: String?
		/// What the construction returns: the concrete type, or what a hand-written mock returns.
		let constructionReturnType: TypeDescription
		/// Whether the construction is an actor's initializer, which takes each argument into the actor's isolation: the
		/// construction function takes each `sending`, and so does the builder that overrides it
		/// (`MockLowering.BuilderParameters`).
		let sendsArguments: Bool
		// A node beneath a repeated configured ancestor records only the construction it builds
		// with, which declares a construction function (`ScopeGenerator.collectPublicConstructionNodes`).
		/// Whether the record describes the type's module-level configuration too, as the node that records the
		/// configuration's does.
		var describesConfiguration = true
		// What the construction function and the module-level configuration make the shared file
		// import: the record's own fulfillers, and the mocked type of the root whose walk recorded it.
		/// The declarations whose modules the construction's code needs imported (`ConfigurationRecord.fulfillers`).
		var fulfillers = Set<FulfillerImports.Fulfiller>()
		/// The declaration of the type mocked by the root whose walk recorded the construction, with its module.
		var mockedTypeFulfiller: FulfillerImports.Fulfiller?
		/// The construction's arguments, in the order it takes them.
		let arguments: [Argument]
		/// The types the builder that overrides the construction is handed, one per argument.
		let builderParameterTypes: [TypeDescription]
		/// The members that configure the node's children, in the order a public configuration declares them (inline
		/// order, `ScopeGenerator.inlineOrdered(_:property:)`).
		let childMembers: [ChildMember]
		/// The construction's default-valued parameters, each a member of the type's public configuration, with the default
		/// its type's hand-written mock declares for the same label and type, else its own.
		let defaultFields: [DefaultField]

		/// An argument of the construction: its label, the name its value is bound under, and its type as declared.
		struct Argument: Sendable, Equatable {
			let label: String
			let innerLabel: String
			let typeDescription: TypeDescription
		}

		/// A member of a public configuration, or of a public mock's `SafeDIOverrides`, that configures one child.
		struct ChildMember: Sendable, Equatable {
			/// The member's name, which is also its initializer parameter's label.
			let name: String
			/// The concrete type the child builds, whose module a closure member's access admits.
			let concreteType: TypeDescription
			let source: Source

			/// What the member holds.
			enum Source: Sendable, Equatable {
				/// The `SafeDIOverrides` of the public mock another module generated, which the child calls.
				case calledMockOverrides(typeSource: String, defaultValue: String)
				/// The child's own module-level configuration where `isConfigured` and the module names one, or else an
				/// optional closure of `builderClosureType`, `@Sendable` where `requiresSendable` or the configuration
				/// holding it is, as visible as `accessTypes`.
				case built(isConfigured: Bool, builderClosureType: String, requiresSendable: Bool, accessTypes: [TypeDescription])
			}
		}
	}

	/// A mock root's lowering beside the code the emitter generated for it with its configuration merged in.
	public struct LoweredRoot: Sendable {
		let mockedType: TypeDescription
		let lowered: Result
		let emittedMergedCode: String
		// A mock of a type of another module extends that type, whose module a configuration of the
		// mock's tree in the shared file needs imported.
		/// The mocked type's declaration, with its module, where SafeDI knows one.
		var mockedTypeFulfiller: FulfillerImports.Fulfiller?
	}
}

extension ScopeGenerator {
	/// This mock root's code, lowered from its finished generator tree. The walk rethrows what the steps it shares with the
	/// emitter throw. `worldRoot` is the root of the mock root's world, where a test observes node records
	/// (`nodeRecordsMockStatements(of:worldRoot:bindsOnlyNodes:rootBindings:outerDeclarations:)`).
	func lowerMockRoot(context: MockContext, worldRoot: ConstructionScope? = nil) async throws -> MockLowering.Result {
		// A mock root's scope is always a root's.
		guard case let .root(instantiable, _) = scopeData else { return MockLowering.Result(code: "") }
		if instantiable.generateMock == .public, let publicMockContext = context.publicMockContext {
			// A public mock's root (`MockLowering+PublicMocks.swift`).
			return try await lowerPublicMockRoot(of: instantiable, publicMockContext: publicMockContext, context: context)
		} else if propertiesToGenerate.isEmpty,
		          instantiable.dependencies.isEmpty,
		          (instantiable.mockInitializer ?? instantiable.initializer)?.arguments.contains(where: \.hasDefaultValue) == false
		{
			return MockLowering.Result(code: Self.mockWithoutTree(of: instantiable, context: context))
		} else {
			return try await lowerMockRootWithTree(of: instantiable, context: context, worldRoot: worldRoot)
		}
	}

	/// The mock of a type whose `mock()` takes no parameter and builds nothing but the type: one call of its hand-written
	/// mock, its `instantiate()` or its initializer.
	// The mocked type's own receives only if available that nothing above provides, passed `nil`.
	static func mockWithoutTree(of instantiable: Instantiable, context: MockContext, passingNilTo unavailableProperties: Set<Property> = []) -> String {
		let typeName = instantiable.concreteInstantiable.asSource
		let mockAttributesPrefix = instantiable.mockAttributes.isEmpty ? "" : "\(instantiable.mockAttributes) "
		let returnType = (instantiable.mockCallReturnType ?? instantiable.concreteInstantiable).asSource
		let argumentList = (instantiable.mockInitializer ?? instantiable.initializer)?
			.createMockInitializerArgumentList(given: instantiable.dependencies, unavailableProperties: unavailableProperties)
			// A type whose declaration the macro rejects is built with the comment that says so.
			?? Instantiable.incorrectlyConfiguredComment
		let construction = if instantiable.mockInitializer != nil {
			"\(typeName).\(instantiable.customMockName ?? InstantiableVisitor.mockMethodName)(\(argumentList))"
		} else if instantiable.declarationType.isExtension {
			"\(typeName).\(InstantiableVisitor.instantiateMethodName)(\(argumentList))"
		} else {
			"\(typeName)(\(argumentList))"
		}
		let code = """
		extension \(typeName) {
		    \(mockAttributesPrefix)static func mock() -> \(returnType) {
		        \(construction)
		    }
		}
		"""
		return if let mockConditionalCompilation = context.mockConditionalCompilation {
			"#if \(mockConditionalCompilation)\n\(code)\n#endif"
		} else {
			code
		}
	}
}
