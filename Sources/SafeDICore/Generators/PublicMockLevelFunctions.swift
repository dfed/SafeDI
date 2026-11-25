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
/// struct. A route on which no level binds a value a fill reads hands the fill the caller's, which the root level function
/// takes; a case that leads to a level function an enclosing call declares re-enters it (`Member.reentry`), handing it the
/// struct of each level of the caller's it takes, as a case that leads to a level of the call hands it on.
struct PublicMockLevelFunctions: Sendable {
	/// One level function.
	struct Function: Sendable {
		/// The dispatcher of the level, whose cases and enum the function follows.
		let dispatcher: ScopeGenerator.FillDispatcher
		let name: String
		/// The values the function takes, by label, each in the form the nearest level on its routes binds it.
		let parameters: [SeamSignature.Hole.Field]
		/// On a route to a place inside a fill of the call, the struct of the level that the caller's member for the call's case
		/// returns, for each of the caller's levels a fill beneath this level is handed (`FillDispatcher.carriedInnerScopes`).
		let carriedInnerScopes: [ScopeGenerator.FillDispatcher.CarriedInnerScope]
		var members = [Member]()
	}

	/// What a member of a level function's struct holds for one case of the level.
	enum Member: Sendable {
		/// The fill of the case's place, handed each value it takes beside the payload.
		case fill(caseName: String, target: ScopeGenerator.FillDispatcher.Case.Target, arguments: [Argument], isIdentity: Bool)
		/// The function of the level the case leads to, handed each value it takes.
		case level(caseName: String, functionIndex: Int, arguments: [Argument])
		/// The call of the level function an enclosing call declares for the enum the case holds, which the case re-enters,
		/// handed what that function takes: the struct of each level of the caller's it takes, which this function's own struct
		/// of that level's member for the case returns, and the values `call` reads of the re-entering call's own scope.
		case reentry(caseName: String, call: EnclosingLevelCall, carriedArguments: [Argument])

		/// The fill of a member that fills its case's place with nothing but the payload, or `nil`.
		var fillTakingOnlyItsPayload: ScopeGenerator.FillDispatcher.Case.Target? {
			guard case let .fill(_, target, arguments, _) = self, arguments.isEmpty else { return nil }
			return target
		}
	}

	/// A value a member hands on: the label of the parameter it is handed under, and where the member reads it.
	struct Argument: Sendable {
		let label: String
		/// The payload's field of the label, or the function's own parameter.
		let readsPayload: Bool
		/// The form the value is read in, and the form it is handed on in.
		let heldForm: Property
		let handedForm: Property
		/// For the struct of a level of the caller's that a fill inside a fill of the call is handed, the name the function
		/// takes the struct of its own level under, whose member for the case returns it.
		var carriedUpName: String?
	}

	/// A level function an enclosing call declares that a case of this call's re-enters: its name, and what the re-entering
	/// call hands it of the values it takes of the caller's scope, read of the call's own
	/// (`ScopeGeneratorUnderConstruction.enclosingLevelCalls`).
	struct EnclosingLevelCall: Sendable {
		let name: String
		let arguments: [String]
	}

	/// A builder the call passes the root level function of: the label it passes it under, the key of the root dispatcher, and
	/// the struct `carriedStructs` names for each struct of the caller's levels it is handed, by the name a fill takes it under.
	struct Root: Sendable {
		let label: String
		let dispatcherKey: String
		let carriedStructs: [String: String]
	}

	/// What the call hands each value a root level function reads of the caller's scope, by label: the caller's nearest
	/// declaration of the value, its instance where the caller holds it lazily, or `nil` (`ScopeGenerator.FillCallerReads`).
	let callerArgumentByLabel: [String: String]
	/// The functions, in the order they are first reached.
	private(set) var functions = [Function]()
	/// The index of the function each root dispatcher's key is handed to with no value bound.
	private(set) var rootFunctionIndexByKey = [String: Int]()
	/// The root level function each of the call's roots is handed, with the root, by the root's label.
	private var rootFunctionByLabel = [String: (index: Int, root: Root)]()

	/// The level functions of a call whose dispatchers are `dispatchers` and whose fills take `fillParametersByKey` beside
	/// their case's payload, for `roots`. A root level function takes each value of `callerReads` its routes read, as a
	/// seam's root dispatcher reads the caller's declaration of it: a route on which no level binds a value a fill reads
	/// hands the fill the caller's, so the place is filled there, as production fills it.
	/// - Parameter enclosingLevelCalls: For each case's target that is a level function an enclosing call declares, by its
	///   dispatcher's key, the function and the values the call that re-enters it hands it
	///   (`ScopeGeneratorUnderConstruction.enclosingLevelCalls`): a builder the called mock holds of a type whose places the
	///   enclosing call fills. The case hands it, beside them, this function's own struct of each level of the caller's the
	///   re-entered function takes (`FillDispatcher.Case.Target.reusedCarriedInnerScopes`), so a level function on a route to
	///   such a case takes it.
	/// - Parameter callerReads: The field each value the call's fills read of the caller's scope is taken as, by label, and
	///   what the call hands it (`ScopeGenerator.FillCallerReads`).
	init(
		dispatchers: [ScopeGenerator.FillDispatcher],
		fillParametersByKey: [String: [SeamSignature.Hole.Field]],
		roots: [Root],
		reservedNames: Set<String>,
		callerReads: [String: (field: SeamSignature.Hole.Field, argument: String)],
		enclosingLevelCalls: [String: EnclosingLevelCall],
	) {
		callerArgumentByLabel = callerReads.mapValues(\.argument)
		let dispatchersByKey = Dictionary(dispatchers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
		// The labels each dispatcher's targets read that its cases' payloads do not carry and their types do not bind later.
		var relevantLabelsByKey = [String: Set<String>]()
		var changed = true
		while changed {
			changed = false
			for dispatcher in dispatchers {
				for dispatcherCase in dispatcher.cases {
					guard let target = dispatcherCase.target else { continue }
					// A case that re-enters a level function an enclosing call declares hands it the struct of each level of the
					// caller's it takes, as a case that leads to a level of this call does: this function's own struct of that level.
					if enclosingLevelCalls[target.key] != nil {
						for reused in target.reusedCarriedInnerScopes {
							guard let carried = dispatcher.carriedInnerScopes.first(where: { $0.type == reused.type }) else { continue }
							if relevantLabelsByKey[dispatcher.key, default: []].insert(carried.name).inserted {
								changed = true
							}
						}
					}
					let read = fillParametersByKey[target.key].map { Set($0.map(\.property.label)) } ?? relevantLabelsByKey[target.key] ?? []
					let carried = Set((dispatcherCase.values ?? []).map(\.property.label))
					for label in read.subtracting(carried).subtracting(dispatcherCase.labelsBoundLater) where relevantLabelsByKey[dispatcher.key, default: []].insert(label).inserted {
						changed = true
					}
				}
			}
		}

		var names = GeneratedNameAllocator(reserving: reservedNames.union(dispatchers.map(\.functionName)))
		var indexBySpecialization = [String: Int]()
		var usedBaseNames = Set<String>()
		/// The index of the function of `dispatcher` given `environment`, the values the routes to it bind, by label, and the
		/// level whose members are still to be built where the function is new.
		func function(of dispatcher: ScopeGenerator.FillDispatcher, given environment: [String: SeamSignature.Hole.Field]) -> (index: Int, level: LevelUnderConstruction?) {
			let relevant = relevantLabelsByKey[dispatcher.key] ?? []
			let parameters = environment.filter { relevant.contains($0.key) }.values.sorted { $0.property < $1.property }
			let specialization = ([dispatcher.key] + parameters.map { "\($0.property.label): \($0.property.typeDescription.asSource)" }).joined(separator: "\u{1F}")
			if let index = indexBySpecialization[specialization] {
				return (index, nil)
			}
			let name = usedBaseNames.insert(dispatcher.functionName).inserted ? dispatcher.functionName : names.claim(dispatcher.functionName)
			let index = functions.count
			indexBySpecialization[specialization] = index
			let relevantCarried = dispatcher.carriedInnerScopes.filter { relevant.contains($0.name) }
			functions.append(Function(dispatcher: dispatcher, name: name, parameters: parameters, carriedInnerScopes: relevantCarried))
			return (index, LevelUnderConstruction(
				index: index,
				dispatcher: dispatcher,
				relevantCarried: relevantCarried,
				carriedByName: Dictionary(relevantCarried.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }),
				ownEnvironment: Dictionary(parameters.map { ($0.property.label, $0) }, uniquingKeysWith: { first, _ in first }),
			))
		}
		/// Builds the members of `level` and of every new level its cases lead to, depth first in case order, as a walk that
		/// recursed into each case's level would: the levels can be as deep as the called mock's tree, so those in progress are
		/// held on an explicit stack, not the thread's, whose half megabyte on Apple platforms a few hundred levels of recursion
		/// overflowed. A case that leads to a new level adds its member before the level beneath is built, since the member reads only the function's
		/// parameters and carried structs, which `function(of:given:)` sets.
		func buildMembers(startingAt level: LevelUnderConstruction) {
			var levelsInProgress = [level]
			while var level = levelsInProgress.popLast() {
				var levelBeneath: LevelUnderConstruction?
				while levelBeneath == nil, level.nextCaseIndex < level.dispatcher.cases.count {
					let dispatcherCase = level.dispatcher.cases[level.nextCaseIndex]
					level.nextCaseIndex += 1
					// A call declares level functions only for the builders it fills, and it fills every place of such a builder
					// (`DependencyTreeGenerator.holesFilled(byCallsOf:in:)` decides per hole type, and a gate passes a hole type up
					// whole), so every case of their dispatchers has a target, which is a fill, a level of this call, or a level an
					// enclosing call declares: no input reaches the `continue`, nor a case that emits no member.
					guard let target = dispatcherCase.target else { continue }
					let payloadFields = Dictionary((dispatcherCase.values ?? []).map { ($0.property.label, $0) }, uniquingKeysWith: { first, _ in first })
					if let fillParameters = fillParametersByKey[target.key] {
						// The fill takes each value it reads beside the payload from this function's own parameter: a value no level on the
						// routes binds is the caller's, which the root level function takes (`callerReads`). A label the case's type binds
						// later is never one of them: the payload carries each value the type builds before the place, and a value it builds
						// after the place, which a fill reads, is production's error (`DependencyTreeGenerator.validateFills`). Nor does a level
						// bind a value in a form that does not provide the one the fill reads: that is production's hidden-receive error.
						let arguments = fillParameters.compactMap { parameter -> Argument? in
							let label = parameter.property.label
							if let carried = level.carriedByName[label] {
								return Argument(label: label, readsPayload: true, heldForm: parameter.property, handedForm: parameter.property, carriedUpName: carried.upName)
							}
							return level.ownEnvironment[label].map { Argument(label: label, readsPayload: false, heldForm: $0.property, handedForm: parameter.property) }
						}
						level.members.append(.fill(caseName: dispatcherCase.name, target: target, arguments: arguments, isIdentity: arguments.allSatisfy { $0.heldForm == $0.handedForm && $0.carriedUpName == nil }))
					} else if let targetDispatcher = dispatchersByKey[target.key] {
						// The level beneath is handed the values this case's payload carries, and those this function takes that the
						// case's type does not bind later.
						var childEnvironment = level.ownEnvironment
						for label in dispatcherCase.labelsBoundLater {
							childEnvironment[label] = nil
						}
						for (label, field) in payloadFields {
							childEnvironment[label] = field
						}
						let (childIndex, newLevel) = function(of: targetDispatcher, given: childEnvironment)
						var arguments = functions[childIndex].carriedInnerScopes.compactMap { childCarried in
							level.carriedByName[childCarried.name].map { carried in
								let property = Property(label: childCarried.name, typeDescription: childCarried.type)
								return Argument(label: childCarried.upName, readsPayload: true, heldForm: property, handedForm: property, carriedUpName: carried.upName)
							}
						}
						arguments += functions[childIndex].parameters.map { parameter in
							Argument(label: parameter.property.label, readsPayload: payloadFields[parameter.property.label] != nil, heldForm: parameter.property, handedForm: parameter.property)
						}
						level.members.append(.level(caseName: dispatcherCase.name, functionIndex: childIndex, arguments: arguments))
						levelBeneath = newLevel
					} else if let call = enclosingLevelCalls[target.key] {
						// The re-entered function takes each struct under its own name for it, in its own order.
						let carriedArguments = target.reusedCarriedInnerScopes.compactMap { reused in
							level.relevantCarried.first { $0.type == reused.type }.map { carried in
								let property = Property(label: carried.name, typeDescription: carried.type)
								return Argument(label: reused.upName, readsPayload: true, heldForm: property, handedForm: property, carriedUpName: carried.upName)
							}
						}
						level.members.append(.reentry(caseName: dispatcherCase.name, call: call, carriedArguments: carriedArguments))
					}
				}
				if let levelBeneath {
					levelsInProgress.append(level)
					levelsInProgress.append(levelBeneath)
				} else {
					functions[level.index].members = level.members
				}
			}
		}
		for root in roots {
			guard rootFunctionIndexByKey[root.dispatcherKey] == nil, let dispatcher = dispatchersByKey[root.dispatcherKey] else { continue }
			let (index, level) = function(of: dispatcher, given: callerReads.mapValues(\.field))
			rootFunctionIndexByKey[root.dispatcherKey] = index
			if let level {
				buildMembers(startingAt: level)
			}
		}
		for root in roots {
			rootFunctionByLabel[root.label] = rootFunctionIndexByKey[root.dispatcherKey].map { (index: $0, root: root) }
		}
	}

	/// A level function whose members are being built: the cases of its dispatcher still to visit, and what each member reads
	/// of the function.
	private struct LevelUnderConstruction {
		let index: Int
		let dispatcher: ScopeGenerator.FillDispatcher
		/// The structs of the caller's levels the function is handed (`Function.carriedInnerScopes`), and by name.
		let relevantCarried: [ScopeGenerator.FillDispatcher.CarriedInnerScope]
		let carriedByName: [String: ScopeGenerator.FillDispatcher.CarriedInnerScope]
		/// The function's parameters, by label.
		let ownEnvironment: [String: SeamSignature.Hole.Field]
		var nextCaseIndex = 0
		var members = [Member]()
	}

	/// What a call inside a fill that re-enters a level function hands it beside the structs of the caller's levels.
	struct Reentry: Equatable, Sendable {
		/// The values the function takes of the caller's scope, which the re-entering call reads of its own scope, as the
		/// call of the function reads them of the caller's: the nearest declaration enclosing it, so the place is filled with
		/// what inline reads there.
		let parameters: [Property]
	}

	/// What a call that re-enters the level function of a dispatcher whose key is in `keys` hands it, by the dispatcher's
	/// key, where it hands it anything beside the structs of the caller's levels: the function a call names by the
	/// dispatcher's name, its root level function or, for a dispatcher of an enum the called mock holds of another module's
	/// public mock (`.inner`), which no case's payload reaches with a value, the level function of its first routes.
	func levelReentries(amongKeys keys: Set<String>) -> [String: Reentry] {
		var reentries = [String: Reentry]()
		for function in functions where keys.contains(function.dispatcher.key) && function.name == function.dispatcher.functionName && !function.parameters.isEmpty {
			reentries[function.dispatcher.key] = Reentry(parameters: function.parameters.map(\.property))
		}
		return reentries
	}

	/// The members of the root level function of the dispatcher of `key`, or `nil` where no function is.
	func rootMembers(ofDispatcherKeyed key: String) -> [Member]? {
		rootFunctionIndexByKey[key].map { functions[$0].members }
	}

	/// What the call passes each of its roots, by label: the call of the root level function, handed `nil` for each label
	/// of `labelsBuiltAfterCall`, which the caller builds after the call, as the fills read it.
	func rootCallsByLabel(passingNilFor labelsBuiltAfterCall: Set<String>) -> [String: String] {
		rootFunctionByLabel.mapValues { rootCall(of: functions[$0.index], for: $0.root, passingNilFor: labelsBuiltAfterCall) }
	}

	/// The call of `function`, a root level function, handed the struct `root.carriedStructs` names for each struct of the
	/// caller's levels it is handed, by the name a fill takes it under, and `nil` for each label of `labelsBuiltAfterCall`.
	private func rootCall(of function: Function, for root: Root, passingNilFor labelsBuiltAfterCall: Set<String>) -> String {
		var arguments = [String]()
		for carried in function.carriedInnerScopes {
			// The `""` is never emitted: the call records a struct in `root.carriedStructs` for each struct its dispatcher
			// carries (`ScopeGeneratorUnderConstruction.builderCallArguments`), and the function carries a subset of those, but
			// no type holds that pairing. 2.3.1's emitter rewrite replaces this code and drops the fallback.
			arguments.append("\(carried.upName.spelledAsArgumentLabel): \(root.carriedStructs[carried.name] ?? "")")
		}
		// Every value a root level function takes is one the call's fills read of the caller's scope.
		for parameter in function.parameters {
			let label = parameter.property.label
			let argument = labelsBuiltAfterCall.contains(label) ? nil : callerArgumentByLabel[label]
			arguments.append("\(label.spelledAsArgumentLabel): \(argument ?? "nil")")
		}
		return "\(function.name)(\(arguments.joined(separator: ", ")))"
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
	/// A member whose fill is in `inlinedFills` holds the fill's body; a fill in `fillsTakingPayloadFields` is handed
	/// each field of the payload it reads (`fillMemberParameterFieldsByKey`), never the payload.
	func declarations(
		indent: String,
		sendableKeys: Set<String>,
		inlinedFills: [String: ScopeGenerator.FillDispatcher.InlinedFill],
		fillsTakingPayloadFields: Set<String>,
		fillMemberParameterFieldsByKey: [String: [SeamSignature.Hole.Field]],
		typesDeclaredEscaping: Set<TypeDescription>,
	) -> [String] {
		let memberIndent = indent + ScopeGenerator.standardIndent
		return functions.map { function in
			let dispatcher = function.dispatcher
			var names = GeneratedNameAllocator(reserving: Set(function.parameters.map(\.property.label) + function.carriedInnerScopes.map(\.upName)))
			let valuesName = names.claim("values")
			let scopeName = names.claim("scope")
			func argumentText(_ argument: Argument, payloadName: String, caseName: String) -> String {
				if let carriedUpName = argument.carriedUpName {
					return "\(argument.label.spelledAsArgumentLabel): \(carriedUpName).\(caseName.spelledAsMemberReference)(\(payloadName))"
				}
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
				case let .fill(caseName, target, arguments, _):
					if let inlinedFill = inlinedFills[target.key] {
						let binding = inlinedFill.carriesPayload && inlinedFill.readsScope ? "scope" : "_"
						members.append(["\(caseName.spelledAsArgumentLabel): { \(binding) in"] + inlinedFill.body.map { String($0.dropFirst(memberIndent.count)) } + ["}"])
					} else if fillsTakingPayloadFields.contains(target.key) {
						let extraLabels = Set(arguments.map(\.label))
						let payloadArguments = (fillMemberParameterFieldsByKey[target.key] ?? []).filter { !extraLabels.contains($0.property.label) }.map { field in
							"\(field.property.label.spelledAsArgumentLabel): \(valuesName).\(field.property.label.spelledAsMemberReference)"
						}
						let allArguments = payloadArguments + arguments.map { argumentText($0, payloadName: valuesName, caseName: caseName) }
						let readsValues = !payloadArguments.isEmpty || arguments.contains { $0.carriedUpName != nil }
						members.append(["\(caseName.spelledAsArgumentLabel): { \(readsValues ? valuesName : "_") in \(target.name)(\(allArguments.joined(separator: ", "))) }"])
					} else {
						let carriesPayload = dispatcher.cases.first { $0.name == caseName }?.carriesPayload ?? false
						let bound = carriesPayload ? [scopeName] : []
						let allArguments = bound + arguments.map { argumentText($0, payloadName: scopeName, caseName: caseName) }
						let readsScope = carriesPayload || arguments.contains { $0.carriedUpName != nil }
						members.append(["\(caseName.spelledAsArgumentLabel): { \(readsScope ? scopeName : "_") in \(target.name)(\(allArguments.joined(separator: ", "))) }"])
					}
				case let .level(caseName, functionIndex, arguments):
					let child = functions[functionIndex]
					let allArguments = arguments.map { argumentText($0, payloadName: valuesName, caseName: caseName) }
					let readsValues = arguments.contains(where: \.readsPayload)
					members.append(["\(caseName.spelledAsArgumentLabel): { \(readsValues ? valuesName : "_") in \(child.name)(\(allArguments.joined(separator: ", "))) }"])
				case let .reentry(caseName, call, carriedArguments):
					let allArguments = carriedArguments.map { argumentText($0, payloadName: valuesName, caseName: caseName) } + call.arguments
					members.append(["\(caseName.spelledAsArgumentLabel): { \(carriedArguments.isEmpty ? "_" : valuesName) in \(call.name)(\(allArguments.joined(separator: ", "))) }"])
				}
			}
			let builderType = ReservedName.levelType(ofEnum: dispatcher.enumType, built: dispatcher.returnType)
			var parameterList = [String]()
			for carried in function.carriedInnerScopes {
				let carriedType = ReservedName.levelType(ofEnum: dispatcher.enumType, built: ScopeGenerator.FillDispatcher.carried(carried.type, through: dispatcher.returnType))
				parameterList.append("\(carried.upName.spelledAsArgumentLabel): \(carriedType.asSource)")
			}
			parameterList += function.parameters.map { "\($0.property.label.spelledAsArgumentLabel): \($0.property.typeDescription.asFunctionParameter(amongTypesDeclaredEscaping: typesDeclaredEscaping).asSource)" }
			let isSendable = sendableKeys.contains(dispatcher.key)
			var lines = ["\(indent)\(ScopeGenerator.localFunctionPrefix(isSendable: isSendable))func \(function.name)(\(parameterList.joined(separator: ", "))) -> \(builderType.asSource) {"]
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
