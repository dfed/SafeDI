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

/// The level functions a call of another module's public mock declares for the builders it fills: one function per level
/// of the called mock's tree and per set of values the routes to that level bind, each returning the level's builder
/// struct. Which places a route fills is decided here, when the code is generated: a place whose fill reads a value no
/// level on the route binds, in a form that provides the one read, is passed up on that route, as the member of the same
/// level of the struct the caller passes up (`up`), never at run time.
struct PublicMockLevelFunctions: Sendable {
	/// One level function.
	struct Function: Sendable {
		/// The dispatcher of the level, whose cases and enum the function follows.
		let dispatcher: ScopeGenerator.FillDispatcher
		let name: String
		/// The values the function takes, by label, each in the form the nearest level on its routes binds it.
		let parameters: [SeamSignature.Hole.Field]
		/// Whether some place beneath the level is passed up on the function's routes: the function then takes the caller's
		/// struct of its level under `PublicMockLevelFunctions.upName`.
		var takesUp = false
		var members = [Member]()
	}

	/// What a member of a level function's struct holds for one case of the level.
	enum Member: Sendable {
		/// The member of the same case of the struct the caller passes up.
		case passedUp(caseName: String)
		/// The fill of the case's place, handed each value it takes beside the payload.
		case fill(caseName: String, target: ScopeGenerator.FillDispatcher.Case.Target, arguments: [Argument], isIdentity: Bool)
		/// The function of the level the case leads to, handed each value it takes.
		case level(caseName: String, functionIndex: Int, arguments: [Argument])
	}

	/// A value a member hands on: the label of the parameter it is handed under, and where the member reads it.
	struct Argument: Sendable {
		let label: String
		/// The payload's field of the label, or the function's own parameter.
		let readsPayload: Bool
		/// The form the value is read in, and the form it is handed on in.
		let heldForm: Property
		let handedForm: Property
	}

	/// The functions, in the order they are first reached.
	private(set) var functions = [Function]()
	/// The name each function takes the caller's struct of its level under.
	let upName: String
	/// The index of the function each root dispatcher's key is handed to with no value bound.
	private(set) var rootFunctionIndexByKey = [String: Int]()

	/// The level functions of a call whose dispatchers are `dispatchers` and whose fills take `fillParametersByKey` beside
	/// their case's payload, for the root dispatchers of `rootKeys`.
	init(
		dispatchers: [ScopeGenerator.FillDispatcher],
		fillParametersByKey: [String: [SeamSignature.Hole.Field]],
		rootKeys: [String],
		reservedNames: Set<String>,
	) {
		let dispatchersByKey = Dictionary(dispatchers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		// The labels each dispatcher's targets read that its cases' payloads do not carry and their types do not bind later.
		var relevantLabelsByKey = [String: Set<String>]()
		var changed = true
		while changed {
			changed = false
			for dispatcher in dispatchers {
				for dispatcherCase in dispatcher.cases {
					guard let target = dispatcherCase.target else { continue }
					let read = fillParametersByKey[target.key].map { Set($0.map(\.property.label)) } ?? relevantLabelsByKey[target.key] ?? []
					let carried = Set((dispatcherCase.values ?? []).map(\.property.label))
					for label in read.subtracting(carried).subtracting(dispatcherCase.labelsBoundLater) where relevantLabelsByKey[dispatcher.key, default: []].insert(label).inserted {
						changed = true
					}
				}
			}
		}
		// The parameter the functions take the caller's struct under, apart from every value they take.
		var allLabels = Set(fillParametersByKey.values.flatMap { $0.map(\.property.label) })
		for dispatcher in dispatchers {
			for dispatcherCase in dispatcher.cases {
				allLabels.formUnion((dispatcherCase.values ?? []).map(\.property.label))
			}
		}
		var upNames = GeneratedNameAllocator(reserving: allLabels)
		upName = upNames.claim("up")

		var names = GeneratedNameAllocator(reserving: reservedNames.union(dispatchers.map(\.functionName)))
		var indexBySpecialization = [String: Int]()
		var usedBaseNames = Set<String>()
		/// The index of the function of `dispatcher` given `environment`, the values the routes to it bind, by label.
		func function(of dispatcher: ScopeGenerator.FillDispatcher, given environment: [String: SeamSignature.Hole.Field]) -> Int {
			let relevant = relevantLabelsByKey[dispatcher.key] ?? []
			let parameters = environment.filter { relevant.contains($0.key) }.values.sorted { $0.property < $1.property }
			let specialization = ([dispatcher.key] + parameters.map { "\($0.property.label): \($0.property.typeDescription.asSource)" }).joined(separator: "\u{1F}")
			if let index = indexBySpecialization[specialization] {
				return index
			}
			let name = usedBaseNames.insert(dispatcher.functionName).inserted ? dispatcher.functionName : names.claim(dispatcher.functionName)
			let index = functions.count
			indexBySpecialization[specialization] = index
			functions.append(Function(dispatcher: dispatcher, name: name, parameters: parameters))
			let ownEnvironment = Dictionary(parameters.map { ($0.property.label, $0) }, uniquingKeysWith: { first, _ in first })
			var members = [Member]()
			for dispatcherCase in dispatcher.cases {
				guard let target = dispatcherCase.target else {
					members.append(.passedUp(caseName: dispatcherCase.name))
					continue
				}
				let payloadFields = Dictionary((dispatcherCase.values ?? []).map { ($0.property.label, $0) }, uniquingKeysWith: { first, _ in first })
				if let fillParameters = fillParametersByKey[target.key] {
					// The fill takes each value it reads beside the payload from this function's own parameter, where the routes bind it in
					// a form that provides the one read; otherwise the place is passed up on these routes.
					var arguments = [Argument]()
					var isAvailable = true
					for parameter in fillParameters {
						let label = parameter.property.label
						guard !dispatcherCase.labelsBoundLater.contains(label),
						      let held = ownEnvironment[label],
						      CycleParameter.forms(providedBy: held.property).contains(parameter.property)
						else {
							isAvailable = false
							break
						}
						arguments.append(Argument(label: label, readsPayload: false, heldForm: held.property, handedForm: parameter.property))
					}
					if isAvailable {
						members.append(.fill(caseName: dispatcherCase.name, target: target, arguments: arguments, isIdentity: arguments.allSatisfy { $0.heldForm == $0.handedForm }))
					} else {
						members.append(.passedUp(caseName: dispatcherCase.name))
					}
				} else if let targetDispatcher = dispatchersByKey[target.key] {
					// The level beneath is handed the values this case's payload carries, and those this function takes that the
					// case's type does not bind later.
					var childEnvironment = ownEnvironment
					for label in dispatcherCase.labelsBoundLater {
						childEnvironment[label] = nil
					}
					for (label, field) in payloadFields {
						childEnvironment[label] = field
					}
					let childIndex = function(of: targetDispatcher, given: childEnvironment)
					let arguments = functions[childIndex].parameters.map { parameter in
						Argument(label: parameter.property.label, readsPayload: payloadFields[parameter.property.label] != nil, heldForm: parameter.property, handedForm: parameter.property)
					}
					members.append(.level(caseName: dispatcherCase.name, functionIndex: childIndex, arguments: arguments))
				} else {
					members.append(.passedUp(caseName: dispatcherCase.name))
				}
			}
			functions[index].members = members
			return index
		}
		for key in rootKeys {
			guard rootFunctionIndexByKey[key] == nil, let dispatcher = dispatchersByKey[key] else { continue }
			rootFunctionIndexByKey[key] = function(of: dispatcher, given: [:])
		}
		// A function takes the caller's struct where a member passes a place up, or hands it to a level beneath that does.
		changed = true
		while changed {
			changed = false
			for index in functions.indices where !functions[index].takesUp {
				let takesUp = functions[index].members.contains { member in
					switch member {
					case .passedUp:
						true
					case let .level(_, functionIndex, _):
						functions[functionIndex].takesUp
					case .fill:
						false
					}
				}
				if takesUp {
					functions[index].takesUp = true
					changed = true
				}
			}
		}
	}

	/// The call of the root level function of the dispatcher of `key`, handed `up` where it takes the caller's struct.
	func rootCall(ofDispatcherKeyed key: String, up: String?) -> String? {
		guard let index = rootFunctionIndexByKey[key] else { return nil }
		let function = functions[index]
		return function.takesUp ? "\(function.name)(\(upName.spelledAsArgumentLabel): \(up ?? ""))" : "\(function.name)()"
	}

	/// The fills a member holds the body of: those every member that calls them hands each value in the form the fill
	/// takes it, under its own label.
	var keysOfFillsCalledWithOwnValues: Set<String> {
		var called = Set<String>()
		var notIdentity = Set<String>()
		for function in functions {
			for member in function.members {
				guard case let .fill(_, target, _, isIdentity) = member else { continue }
				called.insert(target.key)
				if !isIdentity {
					notIdentity.insert(target.key)
				}
			}
		}
		return called.subtracting(notIdentity)
	}

	/// The declaration of each function, indented by `indent`, `@Sendable` where `sendableKeys` holds its dispatcher's key.
	/// A member whose fill is in `inlinedFills` holds the fill's body; a fill in `fillsReturningWrapperBuilders` is handed
	/// each field of the payload it reads (`fillMemberParameterFieldsByKey`), never the payload.
	func declarations(
		indent: String,
		sendableKeys: Set<String>,
		inlinedFills: [String: ScopeGenerator.FillDispatcher.InlinedFill],
		fillsReturningWrapperBuilders: Set<String>,
		fillMemberParameterFieldsByKey: [String: [SeamSignature.Hole.Field]],
		typesDeclaredEscaping: Set<TypeDescription>,
	) -> [String] {
		let memberIndent = indent + ScopeGenerator.standardIndent
		return functions.map { function in
			let dispatcher = function.dispatcher
			let labels = Set(function.parameters.map(\.property.label) + [upName])
			func name(_ base: String) -> String {
				var name = base
				while labels.contains(name) {
					name += "_"
				}
				return name
			}
			let valuesName = name("values")
			let scopeName = name("scope")
			func argumentText(_ argument: Argument, payloadName: String) -> String {
				let source = argument.readsPayload ? "\(payloadName).\(argument.label.spelledAsMemberReference)" : argument.label
				// The instance of a `LazilyInstantiated` the routes bind, where the target reads the value: read where the member is
				// called, which is where the place is built.
				let value = argument.heldForm == argument.handedForm || argument.handedForm == argument.heldForm.asOptionalProperty
					? source
					: "\(source).\(Dependency.lazilyInstantiatedInstancePropertyName)"
				return "\(argument.label.spelledAsArgumentLabel): \(value)"
			}
			var members = [[String]]()
			for member in function.members {
				switch member {
				case let .passedUp(caseName):
					members.append(["\(caseName.spelledAsArgumentLabel): \(upName).\(caseName.spelledAsMemberReference)"])
				case let .fill(caseName, target, arguments, _):
					if let inlinedFill = inlinedFills[target.key] {
						let binding = inlinedFill.carriesPayload && inlinedFill.readsScope ? "scope" : "_"
						members.append(["\(caseName.spelledAsArgumentLabel): { \(binding) in"] + inlinedFill.body.map { String($0.dropFirst(memberIndent.count)) } + ["}"])
					} else if fillsReturningWrapperBuilders.contains(target.key) {
						let extraLabels = Set(arguments.map(\.label))
						let payloadArguments = (fillMemberParameterFieldsByKey[target.key] ?? []).filter { !extraLabels.contains($0.property.label) }.map { field in
							"\(field.property.label.spelledAsArgumentLabel): \(valuesName).\(field.property.label.spelledAsMemberReference)"
						}
						let allArguments = payloadArguments + arguments.map { argumentText($0, payloadName: valuesName) }
						members.append(["\(caseName.spelledAsArgumentLabel): { \(payloadArguments.isEmpty ? "_" : valuesName) in \(target.name)(\(allArguments.joined(separator: ", "))) }"])
					} else {
						let carriesPayload = dispatcher.cases.first { $0.name == caseName }?.carriesPayload ?? false
						let bound = carriesPayload ? [scopeName] : []
						let allArguments = bound + arguments.map { argumentText($0, payloadName: scopeName) }
						members.append(["\(caseName.spelledAsArgumentLabel): { \(carriesPayload ? scopeName : "_") in \(target.name)(\(allArguments.joined(separator: ", "))) }"])
					}
				case let .level(caseName, functionIndex, arguments):
					let child = functions[functionIndex]
					var allArguments = arguments.map { argumentText($0, payloadName: valuesName) }
					let readsValues = arguments.contains(where: \.readsPayload) || child.takesUp
					if child.takesUp {
						allArguments.append("\(upName.spelledAsArgumentLabel): \(upName).\(caseName.spelledAsMemberReference)(\(valuesName))")
					}
					members.append(["\(caseName.spelledAsArgumentLabel): { \(readsValues ? valuesName : "_") in \(child.name)(\(allArguments.joined(separator: ", "))) }"])
				}
			}
			let builderType = TypeDescription.nested(name: ReservedName.builderStructTypeName, parentType: dispatcher.enumType, generics: [dispatcher.returnType])
			var parameterList = [String]()
			if function.takesUp {
				parameterList.append("\(upName.spelledAsArgumentLabel): \(builderType.asSource)")
			}
			parameterList += function.parameters.map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let isSendable = sendableKeys.contains(dispatcher.key)
			var lines = ["\(indent)\(ScopeGenerator.localFunctionPrefix(isSendable: isSendable, isNonisolated: true))func \(function.name)(\(parameterList.joined(separator: ", "))) -> \(builderType.asSource) {"]
			// Laid out as a seam's caller lays out a level function (`FillDispatcher.structDeclaration`).
			if members.allSatisfy({ $0.count == 1 }) {
				lines.append("\(memberIndent).init(\(members.map { $0[0] }.joined(separator: ", ")))")
			} else if members.count == 1 {
				let memberLines = members[0]
				lines.append("\(memberIndent).init(\(memberLines[0])")
				lines += memberLines.dropFirst().dropLast().map { "\(memberIndent)\($0)" }
				lines.append("\(memberIndent)\(memberLines[memberLines.count - 1]))")
			} else {
				lines.append("\(memberIndent).init(")
				for (index, member) in members.enumerated() {
					let separator = index == members.count - 1 ? "" : ","
					lines += member.dropLast().map { "\(memberIndent)\(ScopeGenerator.standardIndent)\($0)" }
					lines.append("\(memberIndent)\(ScopeGenerator.standardIndent)\(member[member.count - 1])\(separator)")
				}
				lines.append("\(memberIndent))")
			}
			lines.append("\(indent)}")
			return lines.joined(separator: "\n")
		}
	}
}
