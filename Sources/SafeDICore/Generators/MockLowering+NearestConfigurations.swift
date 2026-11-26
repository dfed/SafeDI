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

extension MockLowering {
	/// The configurations of the places a closer closes on, handed down to it as passed arguments of every function between,
	/// one list per configuration parameter, so that every function of a type takes the same parameters whatever path
	/// reaches it: the nearest place of each closed-on type's configuration, or `nil` where no place of it is above.
	///
	/// It holds, for the length of one root's `recordBuiltPlaces()`, each function's list and what each call hands it.
	struct NearestConfigurations {
		/// The configuration parameters a function taking `key` hands on, in the order the walk first reaches a place of each.
		let parametersByKey: [String: [ConfigurationParameter]]
		/// The configuration parameter of the function each built place with a function declares, by the place's path.
		let ownParameterByPath: [[Int]: ConfigurationParameter]
		/// Whether each configuration's value stays outside `@Sendable` functions, by its parameter's name.
		let staysOutsideSendableFunctionsByName: [String: Bool]

		/// The name of the parameter a function takes the nearest configuration of `parameter` under.
		static func nearestName(of parameter: ConfigurationParameter) -> String {
			nearestName(ofParameterNamed: parameter.name)
		}

		/// The name of the parameter a function takes the nearest configuration of the parameter named `name` under, which
		/// `ConfigurationParameterNames` claims together with `name`.
		static func nearestName(ofParameterNamed name: String) -> String {
			"\(name)_nearest".spelledAsJoinedIdentifier
		}

		/// The type a function takes the nearest configuration of `parameter` as: optional, since a path can reach the
		/// function with no place of that type above.
		static func nearestType(of parameter: ConfigurationParameter) -> TypeDescription {
			parameter.readsConfigurationStruct ? .optional(parameter.type) : parameter.type
		}

		/// What a call made in the function of the place at `callerPath`, or at the root where it is one place long,
		/// hands the nearest configuration of `parameter`: the caller's own, the one the caller was handed, or `nil` at the
		/// root. A function's list holds every parameter a function it calls takes but its own
		/// (`nearestConfigurations(childPathsByParent:)`), so a caller below the root was handed each one it hands on.
		func nearestValue(of parameter: ConfigurationParameter, calledFrom callerPath: [Int]) -> ValuePath {
			guard let callerParameter = ownParameterByPath[callerPath] else {
				return .spliced([.text("nil")])
			}
			return .passedArgument(callerParameter == parameter ? parameter.name : Self.nearestName(of: parameter))
		}

		/// The nearest configuration of `parameter` a function of the place at `callerPath` was handed, where it takes one.
		func nearestRead(of parameter: ConfigurationParameter, calledFrom callerPath: [Int]) -> ValuePath? {
			guard let callerParameter = ownParameterByPath[callerPath], callerParameter != parameter,
			      parametersByKey[callerParameter.name, default: []].contains(parameter)
			else { return nil }
			return .passedArgument(Self.nearestName(of: parameter))
		}

		/// The passed arguments a call made at `path` hands the nearest configurations the function of `calleeParameter`
		/// takes.
		func nearestArguments(ofCallTo calleeParameter: ConfigurationParameter, at path: [Int]) -> [PassedArgument] {
			let callerPath = Array(path.dropLast())
			return parametersByKey[calleeParameter.name, default: []].map { parameter in
				PassedArgument(
					parameterName: Self.nearestName(of: parameter),
					type: Self.nearestType(of: parameter),
					value: nearestValue(of: parameter, calledFrom: callerPath),
					staysOutsideSendableFunctions: staysOutsideSendableFunctionsByName[parameter.name] ?? true,
				)
			}
		}

		/// What a closer at `path` hands the configuration of the place it closes on, `closedOn`: the nearest place of its
		/// type's, which its function was handed, or a fresh one where none is above.
		func closedOnValue(of closedOn: ConfigurationParameter, at path: [Int], parentField: ValuePath?) -> ValuePath? {
			let callerPath = Array(path.dropLast())
			guard let callerParameter = ownParameterByPath[callerPath] else { return nil }
			if callerParameter == closedOn {
				return .passedArgument(closedOn.name)
			} else if let parentField {
				return .spliced([.value(.passedArgument(Self.nearestName(of: closedOn))), .text(" ?? "), .value(parentField)])
			} else {
				return MockLowering.Walk.nearestFirst(.passedArgument(Self.nearestName(of: closedOn)), orElse: closedOn.read(isProvided: false), own: closedOn)
			}
		}
	}
}

extension MockLowering.Walk {
	/// The nearest configurations every function of the walk's places hands on, found as a fixed point over the places:
	/// a function takes each one a closer among its places closes on, each one a place among them built again by a cycle
	/// reads, and each one a function it calls takes, but its own.
	mutating func nearestConfigurations(childPathsByParent: [[Int]: [[Int]]]) -> MockLowering.NearestConfigurations {
		var ownParameterByPath = [[Int]: MockLowering.ConfigurationParameter]()
		var staysOutsideSendableFunctionsByName = [String: Bool]()
		var firstReachedIndexByName = [String: Int]()
		var closedOnParameterByPath = [[Int]: MockLowering.ConfigurationParameter]()
		for (index, path) in placePathsInWalkOrder.enumerated() {
			if let call = builtPlaceCalls[path], call.inputs.hasFunction {
				let node = call.nodeConfiguration
				let parameter = configurationParameter(of: node)
				ownParameterByPath[path] = parameter
				if firstReachedIndexByName[parameter.name] == nil {
					firstReachedIndexByName[parameter.name] = index
					staysOutsideSendableFunctionsByName[parameter.name] = node.hasConfiguration ? !sendableConfigurationTypeNames.contains(node.instantiable.concreteInstantiable.asSource) : !node.requiresSendable
				}
			} else if case let .closer(record)? = closerAndDefaultRecords[path], let argument = record.passedArguments.first {
				closedOnParameterByPath[path] = MockLowering.ConfigurationParameter(name: argument.parameterName, type: argument.type)
			}
		}
		// What a function's list joins is the same at every place of its type, so the places are read once, into what each
		// type's functions take of their own places and which types' functions they call, and the fixed point runs over the
		// types: a mock that enters a lazy cycle has thousands of places of a dozen types.
		var ownParameterByName = [String: MockLowering.ConfigurationParameter]()
		var directParametersByName = [String: Set<MockLowering.ConfigurationParameter>]()
		var calledNamesByName = [String: Set<String>]()
		for path in placePathsInWalkOrder {
			guard let own = ownParameterByPath[path] else { continue }
			ownParameterByName[own.name] = own
			for child in childPathsByParent[path] ?? [] {
				if let childParameter = ownParameterByPath[child] {
					calledNamesByName[own.name, default: []].insert(childParameter.name)
					// A place a cycle builds again, with no field in its parent's configuration, reads the nearest
					// place of its type's configuration, as a closer on that place would hand it.
					if builtPlaceConfigurationContexts[child]?.nearestIsProvided == true {
						directParametersByName[own.name, default: []].insert(childParameter)
					}
				} else if let closedOn = closedOnParameterByPath[child] {
					directParametersByName[own.name, default: []].insert(closedOn)
					calledNamesByName[own.name, default: []].insert(closedOn.name)
				}
			}
			// A member of a loop of builders calls, through the closers its function begins with, the functions of the
			// members it rebinds (`MockLowering+LoopPlaces.swift`).
			for rebinding in loopRebindings[path] ?? [] {
				if let rebound = ownParameterByPath[rebinding.memberPath] {
					calledNamesByName[own.name, default: []].insert(rebound.name)
				}
			}
		}
		var parametersByName = [String: Set<MockLowering.ConfigurationParameter>]()
		var changed = true
		while changed {
			changed = false
			for (name, own) in ownParameterByName {
				var parameters = parametersByName[name, default: []]
				let countBefore = parameters.count
				parameters.formUnion(directParametersByName[name, default: []])
				for calledName in calledNamesByName[name, default: []] {
					parameters.formUnion(parametersByName[calledName, default: []])
				}
				parameters.remove(own)
				if parameters.count != countBefore {
					parametersByName[name] = parameters
					changed = true
				}
			}
		}
		return MockLowering.NearestConfigurations(
			parametersByKey: parametersByName.mapValues { parameters in
				parameters.sorted { (firstReachedIndexByName[$0.name] ?? .max) < (firstReachedIndexByName[$1.name] ?? .max) }
			},
			ownParameterByPath: ownParameterByPath,
			staysOutsideSendableFunctionsByName: staysOutsideSendableFunctionsByName,
		)
	}
}
