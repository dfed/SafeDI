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

extension ScopeGenerator {
	/// Where a generated `mock()` reads a node's entry in its overrides.
	struct MockOverridePath: Sendable {
		/// The overrides themselves, `safeDIOverrides`.
		static let root = MockOverridePath(expression: ReservedName.mockOverridesParameterName, relativeName: "")

		/// The expression that reads the entry: `safeDIOverrides.parent.child`, or, beneath a configuration `mock()`
		/// binds to a local (`DeferredConfigurations`), that local followed by the labels beneath it.
		let expression: String
		/// The labels from the overrides to the entry, joined by `_` (`parent_child`), which name the locals read from the
		/// entry, however `expression` reads it.
		let relativeName: String

		/// The path of the entry labeled `label` inside this one.
		func appending(_ label: String) -> MockOverridePath {
			MockOverridePath(
				expression: "\(expression).\(label)",
				relativeName: relativeName.isEmpty ? label : "\(relativeName)_\(label)",
			)
		}
	}

	/// The fields of an internal mock's `SafeDIOverrides` and `SafeDIMockConfiguration` structs that hold a child's
	/// configuration as an optional defaulting to `nil`, which `mock()` resolves to `.init()` once, at the top of its body,
	/// rather than in the field's default argument.
	///
	/// In a module whose declarations default to the main actor, a type nested in an extension of a type on a global actor
	/// is on that actor too, so the configuration of such a type has an initializer on that actor, which the default
	/// argument of a holder off that actor cannot call: "main actor-isolated default value in a nonisolated context". The
	/// configuration cannot be `nonisolated` instead, since its initializer spells the defaults the configured type
	/// spells, which may read that actor's state. `mock()`, which builds the type, is on its actor wherever the tree
	/// compiles, so it can call the initializer. A field is deferred when:
	/// - the child's type declaration spells a global actor that the declaration of the type whose extension holds the
	///   field does not spell: the mocked type, for `SafeDIOverrides`, or the parent node's type. This reads only the two
	///   types, so a type's `SafeDIMockConfiguration` is the same in every mock; or
	/// - the field is in the `SafeDIOverrides` of a type whose `mock()` is on a global actor only through `mockAttributes`
	///   (decision 53's opt-in for isolation SafeDI cannot see), where every configuration-typed field is deferred, since
	///   the child may be on that actor through a conformance or a superclass.
	///
	/// A module without that default has every configuration nonisolated, so resolving it in `mock()` compiles wherever the
	/// default argument did, and still evaluates the configured type's defaults once per `mock()` call. A public mock's
	/// overrides and configurations are `nonisolated` and hold no configured type's defaults, so none of their fields is
	/// deferred.
	enum DeferredConfigurations {
		/// What holds the configurations of the nodes at one level of a mock's tree: the `SafeDIOverrides` of the mocked
		/// type, or the `SafeDIMockConfiguration` of a node's type.
		struct Holder: Sendable {
			/// The holder of the configurations of the children of the mock root: its `SafeDIOverrides`.
			static func overrides(of instantiable: Instantiable) -> Holder {
				Holder(
					globalActorIsolation: instantiable.declaredGlobalActorIsolation,
					defersEveryConfiguration: instantiable.generatedMockIsGlobalActorIsolatedOnlyThroughMockAttributes,
				)
			}

			/// The holder of the configurations of `node`'s children: its type's `SafeDIMockConfiguration`.
			static func configuration(of node: MockParameterNode) -> Holder {
				Holder(globalActorIsolation: node.globalActorIsolation, defersEveryConfiguration: false)
			}

			/// The global actor the declaration of the type whose extension holds the configurations spells.
			let globalActorIsolation: String?
			/// Whether every configuration-typed field is deferred.
			let defersEveryConfiguration: Bool

			/// Whether the field that holds `child`'s configuration is deferred.
			func defersConfiguration(of child: MockParameterNode) -> Bool {
				guard child.needsConfigurationStruct, child.publicMockCall?.takesOverrides != true else {
					return false
				}
				if defersEveryConfiguration {
					return true
				} else if let childIsolation = child.globalActorIsolation {
					return childIsolation != globalActorIsolation
				} else {
					return false
				}
			}
		}

		/// The locals a `mock()` binds its deferred configurations to, in the order its tree's walk reaches them, which is
		/// the tree's pre-order: a configuration's local is bound before those of the configurations it holds.
		final class Bindings {
			/// - Parameter takenNames: The names declared at the top level of `mock()`'s body that no local may take.
			init(takenNames: Set<String>) {
				self.takenNames = takenNames
			}

			/// Binds the deferred configuration at `path` to a local, and returns the path that reads the local.
			func bind(_ path: MockOverridePath) -> MockOverridePath {
				var name = ReservedName.deferredConfigurationLocalName(relativePath: path.relativeName)
				while !takenNames.insert(name).inserted {
					name = "\(name)_".spelledAsJoinedIdentifier
				}
				lines.append("let \(name) = \(path.expression) ?? .init()")
				return MockOverridePath(expression: name, relativeName: path.relativeName)
			}

			/// The `let` of each local, without indentation, in the order the walk bound them.
			private(set) var lines = [String]()

			private var takenNames: Set<String>
		}

		/// What a walk of one level of a mock's tree needs to read the deferred configurations of its nodes.
		struct Walk {
			let holder: Holder
			let bindings: Bindings

			/// The path from which the walk reads `child`'s entry, which is at `path`.
			func path(of child: MockParameterNode, at path: MockOverridePath) -> MockOverridePath {
				holder.defersConfiguration(of: child) ? bindings.bind(path) : path
			}

			/// The walk of the level beneath `node`.
			func beneath(_ node: MockParameterNode) -> Walk {
				Walk(holder: .configuration(of: node), bindings: bindings)
			}
		}
	}
}
