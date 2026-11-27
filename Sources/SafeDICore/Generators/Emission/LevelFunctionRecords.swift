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

/// The level functions a call of another module's public mock declares (`PublicMockLevelFunctions`), as values the engine
/// spells: every decision of a function's text is a field, so the spelling reads no text but the bodies of the fills it
/// inlines, which are the fills' own, and the names, which are allocated apart from the records.
struct LevelFunctionRecords: Hashable, Sendable {
	/// The functions, in the order the call first reaches them.
	let functions: [LevelFunctionRecord]
	/// The name of each function, by its index in `functions`.
	let functionNames: [String]
	/// The name of each fill a member calls, by the fill's key.
	let fillNames: [String: String]

	/// Each function, indented by `indent`: a member of a fill in `inlinedFillBodies`, by the fill's key, holds that body.
	func declarations(indent: String, inlinedFillBodies: [String: [String]]) -> [String] {
		let memberIndent = indent + ScopeGenerator.standardIndent
		return functions.enumerated().map { index, function in
			var names = GeneratedNameAllocator(reserving: Set(function.parameters.map(\.label) + function.carriedInnerScopes.map(\.label)))
			let valuesName = names.claim("values")
			let scopeName = names.claim("scope")
			var members = [[String]]()
			for member in function.members {
				switch member {
				case let .fill(caseName, fillKey, arguments, form):
					switch form {
					case let .inlined(bindsScope):
						members.append(["\(caseName.spelledAsArgumentLabel): { \(bindsScope ? "scope" : "_") in"] + (inlinedFillBodies[fillKey] ?? []).map { String($0.dropFirst(memberIndent.count)) } + ["}"])
					case let .takesPayloadFields(payloadLabels):
						let payloadArguments = payloadLabels.map { "\($0.spelledAsArgumentLabel): \(valuesName).\($0.spelledAsMemberReference)" }
						let allArguments = payloadArguments + arguments.map { $0.spelled(payloadName: valuesName, caseName: caseName) }
						let readsValues = !payloadLabels.isEmpty || arguments.contains { $0.carriedUpName != nil }
						members.append(["\(caseName.spelledAsArgumentLabel): { \(readsValues ? valuesName : "_") in \(fillNames[fillKey] ?? fillKey)(\(allArguments.joined(separator: ", "))) }"])
					case let .called(carriesPayload):
						let bound = carriesPayload ? [scopeName] : []
						let allArguments = bound + arguments.map { $0.spelled(payloadName: scopeName, caseName: caseName) }
						let readsScope = carriesPayload || arguments.contains { $0.carriedUpName != nil }
						members.append(["\(caseName.spelledAsArgumentLabel): { \(readsScope ? scopeName : "_") in \(fillNames[fillKey] ?? fillKey)(\(allArguments.joined(separator: ", "))) }"])
					}
				case let .level(caseName, functionIndex, arguments):
					let allArguments = arguments.map { $0.spelled(payloadName: valuesName, caseName: caseName) }
					let readsValues = arguments.contains(where: \.readsPayload)
					members.append(["\(caseName.spelledAsArgumentLabel): { \(readsValues ? valuesName : "_") in \(functionNames[functionIndex])(\(allArguments.joined(separator: ", "))) }"])
				case let .reentry(caseName, functionName, spelledArguments, carriedArguments):
					let allArguments = carriedArguments.map { $0.spelled(payloadName: valuesName, caseName: caseName) } + spelledArguments
					members.append(["\(caseName.spelledAsArgumentLabel): { \(carriedArguments.isEmpty ? "_" : valuesName) in \(functionName)(\(allArguments.joined(separator: ", "))) }"])
				}
			}
			var parameterList = function.carriedInnerScopes.map { "\($0.label.spelledAsArgumentLabel): \($0.type.asSource)" }
			parameterList += function.parameters.map { "\($0.label.spelledAsArgumentLabel): \($0.type.asSource)" }
			var lines = ["\(indent)\(ScopeGenerator.localFunctionPrefix(isSendable: function.isSendable))func \(functionNames[index])(\(parameterList.joined(separator: ", "))) -> \(function.builderType.asSource) {"]
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
				for (memberIndex, member) in members.enumerated() {
					let separator = memberIndex == members.count - 1 ? "" : ","
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

/// One level function: the level's builder struct it returns, what it takes, and a member per case of its level.
struct LevelFunctionRecord: Hashable, Sendable {
	/// The key of the dispatcher whose level the function is.
	let dispatcherKey: String
	/// The level's builder struct.
	let builderType: TypeDescription
	let isSendable: Bool
	/// The struct of each of the caller's levels the function takes, under its `up` name, typed as this level's struct
	/// carrying it (`FillDispatcher.carried(_:through:)`).
	let carriedInnerScopes: [Parameter]
	/// The values the function takes, by label, each typed as a function's parameter spells it.
	let parameters: [Parameter]
	let members: [LevelMember]

	/// A parameter: its label and the type its declaration spells.
	struct Parameter: Hashable, Sendable {
		let label: String
		let type: TypeDescription
	}
}

/// What a member of a level function's struct holds for one case of the level (`PublicMockLevelFunctions.Member`).
enum LevelMember: Hashable, Sendable {
	/// The fill of the case's place, by the fill's key, handed each value it takes beside the payload, in `form`.
	case fill(caseName: String, fillKey: String, arguments: [LevelArgument], form: FillForm)
	/// The function of the level the case leads to, by its index, handed each value it takes.
	case level(caseName: String, functionIndex: Int, arguments: [LevelArgument])
	/// The re-entry of a level function an enclosing call declares, by its name, handed the values the re-entering call
	/// reads of its own scope, spelled until calls inside fills are planned, and the structs of the caller's levels.
	case reentry(caseName: String, functionName: String, spelledArguments: [String], carriedArguments: [LevelArgument])

	/// How a member holds a fill.
	enum FillForm: Hashable, Sendable {
		/// The fill's body inlined, binding the case's payload as `scope` where the body reads it.
		case inlined(bindsScope: Bool)
		/// A call of the fill handed each of these payload fields by label.
		case takesPayloadFields(payloadLabels: [String])
		/// A call of the fill handed the payload where the case carries one.
		case called(carriesPayload: Bool)
	}
}

/// A value a member hands on (`PublicMockLevelFunctions.Argument`): the label of the parameter it is handed under, and
/// where the member reads it.
struct LevelArgument: Hashable, Sendable {
	let label: String
	/// The payload's field of the label, or the function's own parameter.
	let readsPayload: Bool
	/// Whether the member hands the instance of the `LazilyInstantiated` it reads: the routes bind the wrapper where the
	/// target reads the value.
	let readsInstance: Bool
	/// For the struct of a level of the caller's that a fill inside a fill of the call is handed, the name the function takes
	/// the struct of its own level under, whose member for the case returns it.
	let carriedUpName: String?

	/// `label: value`, read of the payload bound as `payloadName`, for the case `caseName`.
	func spelled(payloadName: String, caseName: String) -> String {
		if let carriedUpName {
			return "\(label.spelledAsArgumentLabel): \(carriedUpName).\(caseName.spelledAsMemberReference)(\(payloadName))"
		}
		let source = readsPayload ? "\(payloadName).\(label.spelledAsMemberReference)" : label
		return "\(label.spelledAsArgumentLabel): \(readsInstance ? "\(source).\(Dependency.lazilyInstantiatedInstancePropertyName)" : source)"
	}
}
