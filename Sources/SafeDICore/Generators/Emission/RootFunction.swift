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

/// A function a seam call's code declares that captures nothing of the code around it, which the root holding the call
/// can declare once, at its top, for every call that declares it (`RootFunctionHoisting`). Each call of another module's
/// seam declares the dispatchers of the seam's tree, and a call made inside a fill declares those of every seam it calls,
/// so a root that calls a seam from many places declared each dispatcher once per call. A fill that reads nothing of the
/// code around it is one too, so that the fills of a seam's places are declared once however many paths reach them.
struct RootFunctionRecord: Sendable {
	/// What the declaration is written as.
	enum Declaration: Sendable {
		/// A dispatcher's declaration as the call writes it after `key.indentation`, from its keyword on: without that
		/// indentation and the attributes `isSendable` adds (`ScopeGenerator.localFunctionPrefix`).
		case text(String)
		/// A fill's declaration, its attributes included, written after `inPlaceIndentation` where the call declares it. Its
		/// plan holds the root functions its tree declares, which the root declares where it declares the fill.
		case code(GeneratedCode, inPlaceIndentation: String)
		/// A fill's shared body (`ScopeGenerator.sharedFillBodyFunction`), written after `inPlaceIndentation` where the call
		/// declares it, its tree in the path key's layout, and in the type key's where a root declares it at its top, laid out
		/// there once for every fill that calls it.
		case fillBody(FillBodyFunction, inPlaceIndentation: String)
	}

	/// What the function's text is a function of within one root: two records of one root with equal keys have equal text.
	let key: RootFunctionKey
	/// The function's name, which the call allocates and nothing renames.
	let name: String
	let declaration: Declaration
	/// Whether the call declares the function `@Sendable nonisolated`.
	let isSendable: Bool
	/// The names of the root functions the text calls, which are declared with it or not at all.
	let calls: [String]

	/// The declaration, after its indentation, `@Sendable nonisolated` where `isSendable`: a fill's as the call writes it,
	/// whose attributes are its own.
	func spelled(isSendable: Bool) -> GeneratedCode {
		switch declaration {
		case let .text(textWithoutAttributes):
			.text(key.indentation + ScopeGenerator.localFunctionPrefix(isSendable: isSendable) + textWithoutAttributes)
		case let .code(code, inPlaceIndentation):
			.indented(code, by: inPlaceIndentation)
		case let .fillBody(function, inPlaceIndentation):
			.indented(function.pathCode, by: inPlaceIndentation)
		}
	}

	/// The declaration as a root whose statements are written after `indentation` declares it at its top, `@Sendable
	/// nonisolated` where `isSendable` and it is a dispatcher, without the root functions named `declaredNames`, which the
	/// root declares beside it.
	func hoisted(atIndentation indentation: String, isSendable: Bool, omittingRootFunctionsNamed declaredNames: Set<String>) -> GeneratedCode {
		switch declaration {
		case .text:
			// A call's body is indented by the levels around it, so its declarations are written after its own indentation alone.
			.indented(spelled(isSendable: isSendable), by: indentation.hasPrefix(key.indentation) ? String(indentation.dropFirst(key.indentation.count)) : "")
		case let .code(code, _):
			.indented(code, by: indentation)
		case let .fillBody(function, _):
			.indented(function.laidOutCode(omittingRootFunctionsNamed: declaredNames), by: indentation)
		}
	}

	/// Whether the declaration is a fill's code, whose plan holds the root functions its tree declares.
	var declaresCode: Bool {
		switch declaration {
		case .code,
		     .fillBody:
			true
		case .text:
			false
		}
	}

	/// Whether the declaration can be written `@Sendable nonisolated` where it is not: a fill's attributes are its own.
	var canBeDeclaredSendable: Bool {
		switch declaration {
		case .text:
			true
		case .code,
		     .fillBody:
			isSendable
		}
	}
}

/// What a root function's text is a function of, within one root: the called seam, the level of its tree the function
/// returns the struct of, and what of the call around it the text reads. Nothing compares a dispatcher's text; the graph
/// fuzzer checks that equal keys give equal text. A fill's key holds its text.
public struct RootFunctionKey: Hashable, Sendable {
	/// The seam whose tree the function walks.
	let calledSeam: TypeDescription?
	/// The level's key (`ScopeGenerator.FillDispatcher.key`), which names the hole type and family the level is of.
	let level: String
	/// Whether the call declares the function `@Sendable nonisolated`.
	let isSendable: Bool
	/// The fills of the call the function holds the bodies of, by key.
	let inlinedFillKeys: Set<String>
	/// The fills of the call whose members are handed each payload field.
	let fillsTakingPayloadFields: Set<String>
	/// The types a parameter is declared `@escaping` for.
	let typesDeclaredEscaping: Set<TypeDescription>
	/// The labels a call inside a fill binds again beneath the call.
	let labelsHiddenByReenteringCalls: Set<String>
	/// For a dispatcher, the names of the functions its cases call, in case order: a case's target is named where its call
	/// declares it, so two calls of one level can hand a case to fills of two names. Empty for a fill, whose `text` names
	/// them.
	var calledFunctionNames: [String] = []
	/// The indentation the call writes the declaration after, which the body of every scope shares, and the root's
	/// statements too (`ScopeGenerator.rootStatementIndentation`). Empty for a fill, whose plan is indented where it is
	/// written.
	let indentation: String
	/// For a fill, its text without the root functions its plan holds: a fill's text is a function of its call's
	/// position in the root, which nothing else in the key names, so the key is the text itself. `nil` for a dispatcher.
	var text: String?

	/// The key with `isSendable` false: what two records of one name must share to be declared once.
	var ignoringSendability: RootFunctionKey {
		RootFunctionKey(
			calledSeam: calledSeam,
			level: level,
			isSendable: false,
			inlinedFillKeys: inlinedFillKeys,
			fillsTakingPayloadFields: fillsTakingPayloadFields,
			typesDeclaredEscaping: typesDeclaredEscaping,
			labelsHiddenByReenteringCalls: labelsHiddenByReenteringCalls,
			calledFunctionNames: calledFunctionNames,
			indentation: indentation,
			text: text,
		)
	}
}

/// Declares each root function of a root's plan once, at the root's top, in the order the plan first reaches it.
///
/// A name is declared at the top only where every record of it in the plan has one key, but for whether it is `@Sendable`,
/// every function it calls is declared there too, and so is every root function its plan holds; every other record is
/// written where the call put it, as it was before. A function reached inside a `@Sendable` function
/// (`GeneratedCode.sendableFunction(_:)`), or called by one declared `@Sendable`, is declared `@Sendable nonisolated`,
/// since a `@Sendable` function calls no function that is not. A dispatcher reached both inside and outside one is
/// declared once, `@Sendable nonisolated`: its text is the same at every record of its key, so it compiles `nonisolated`
/// wherever the one inside compiles, and it captures nothing, so plain code calls it as it called the plain one. A fill's
/// attributes are its own, so a fill that would have to be `@Sendable` and is not stays where its call put it.
///
/// Every record of a name is read, those inside a fill the root declares at its top included, so every function of one
/// name has one text, the root functions it holds aside, each of which is declared once in turn: the root reads one
/// function of each name wherever a call wrote it.
public enum RootFunctionHoisting {
	/// A root function a root's plan reaches: its key, its name, and its text as the root would declare it.
	public struct Occurrence: Sendable {
		public let key: RootFunctionKey
		public let name: String
		public let text: String
	}

	/// Handed every root function each root's plan reaches, once per call that reaches it, in the order the plan reaches
	/// them, so the graph fuzzer can check that equal keys give equal text, which nothing in the generator compares.
	@TaskLocal public static var observer: (@Sendable ([Occurrence]) -> Void)?

	/// The root functions a root's body reaches, read once, and the body with those the root declares at its top.
	struct Hoisting {
		/// Every root function the body reaches, by name.
		let rootFunctionNames: Set<String>
		/// The root functions the root declares at its top, by name.
		let declaredNames: Set<String>
		/// Those declarations, each indented as a statement of the root.
		let declarations: [GeneratedCode]
		/// The body, without the root functions the root declares at its top.
		let body: [GeneratedCode]

		/// The body preceded by the root functions it declares once.
		var hoistedStatements: [GeneratedCode] {
			declarations + body
		}
	}

	/// The root functions `statements`, the root's body, reaches, and which of them the root declares once at its top,
	/// indented as its statements are, written after `indentation`. The body is read once, and the observer handed what it
	/// reaches.
	static func hoisting(_ statements: [GeneratedCode], indentation: String) -> Hoisting {
		let found = recordsAndConflicts(in: statements, reportsOccurrences: true)
		let records = found.records
		let keyByName = Dictionary(records.map { ($0.name, $0.key) }, uniquingKeysWith: { first, _ in first })
		// A function that calls one kept in place, or holds one, is kept in place too, until none is left to keep.
		func keepingCallers(of kept: Set<String>) -> Set<String> {
			var keptNames = kept
			var keptCount: Int?
			while keptCount != keptNames.count {
				keptCount = keptNames.count
				let callersOfKept = records.filter { record in
					record.calls.contains { keptNames.contains($0) || keyByName[$0] == nil }
						|| found.heldNamesByName[record.name, default: []].contains(where: keptNames.contains)
				}.map(\.name)
				keptNames.formUnion(callersOfKept)
			}
			return keptNames
		}
		// A function a `@Sendable` one calls is `@Sendable` too, until no more is; a fill that cannot be is kept in place.
		func sendableNames(among declared: [RootFunctionRecord]) -> Set<String> {
			var sendableNames = Set(declared.filter(\.isSendable).map(\.name))
			var sendableCount: Int?
			while sendableCount != sendableNames.count {
				sendableCount = sendableNames.count
				for record in declared where sendableNames.contains(record.name) {
					sendableNames.formUnion(record.calls)
				}
			}
			return sendableNames
		}
		// A function made `@Sendable` whose text cannot be is kept in place with its callers, which can change what is
		// `@Sendable`, until none is left. Fills are marked `@Sendable` where they are generated, so the first pass keeps
		// none on every graph the tests and the corpora draw.
		var keptNames = found.conflictingNames
		var unsendable = Set<String>()
		var declared: [RootFunctionRecord]
		var sendable: Set<String>
		repeat {
			keptNames = keepingCallers(of: keptNames.union(unsendable))
			declared = records.filter { !keptNames.contains($0.name) }
			sendable = sendableNames(among: declared)
			unsendable = Set(declared.filter { sendable.contains($0.name) && !$0.canBeDeclaredSendable }.map(\.name))
		} while !unsendable.isEmpty
		let rootFunctionNames = Set(records.map(\.name))
		guard !declared.isEmpty else {
			return Hoisting(rootFunctionNames: rootFunctionNames, declaredNames: [], declarations: [], body: statements)
		}
		let declaredNames = Set(declared.map(\.name))
		// A fill the root declares holds the root functions its tree declares, which the root declares beside it.
		return Hoisting(
			rootFunctionNames: rootFunctionNames,
			declaredNames: declaredNames,
			declarations: declared.map { record in
				.omittingRootFunctions(record.hoisted(atIndentation: indentation, isSendable: sendable.contains(record.name), omittingRootFunctionsNamed: declaredNames), named: declaredNames)
			},
			body: [.omittingRootFunctions(.lines(statements), named: declaredNames)],
		)
	}

	/// The names of the root functions `codes` hold outside every other root function: omitting those omits every root
	/// function the code holds, so the code's text without its root functions omits these alone, read without walking
	/// the plans the root functions hold.
	static func outermostNames(in codes: [GeneratedCode]) -> Set<String> {
		var names = Set<String>()
		var work = codes
		while let code = work.popLast() {
			switch code.node {
			case .text:
				break
			case let .sequence(pieces), let .lines(pieces):
				work.append(contentsOf: pieces)
			case let .indented(inner, _),
			     let .omittingRootFunctions(inner, _),
			     let .sendableFunction(inner):
				work.append(inner)
			case let .place(plan) where plan.code.holdsRootFunction:
				work.append(plan.code)
			case .place:
				break
			case let .rootFunction(record, _):
				names.insert(record.name)
			}
		}
		return names
	}

	/// The root functions `codes` hold, once per name, in the order they are reached, each keyed with the family a
	/// `@Sendable` function around it gives it.
	static func records(in codes: [GeneratedCode]) -> [RootFunctionRecord] {
		recordsAndConflicts(in: codes).records
	}

	/// The root functions `codes` hold that can be declared once wherever they are reached, as `records(in:)` lists them:
	/// none reached with two keys, nor inside a `@Sendable` function where it cannot be declared `@Sendable`, since its
	/// declaration was written for code that is not `@Sendable`.
	static func recordsDeclarableWhereReached(in codes: [GeneratedCode]) -> [RootFunctionRecord] {
		let found = recordsAndConflicts(in: codes)
		return found.records.filter { !found.conflictingNames.contains($0.name) }
	}

	/// The root functions `codes` hold, once per name, in the order they are reached; the names reached with two keys, or
	/// inside a `@Sendable` function where the function cannot be declared `@Sendable`; and, by name, the names of the root
	/// functions each one's plan holds.
	private static func recordsAndConflicts(in codes: [GeneratedCode], reportsOccurrences: Bool = false) -> (records: [RootFunctionRecord], conflictingNames: Set<String>, heldNamesByName: [String: Set<String>]) {
		let observer = reportsOccurrences ? observer : nil
		var occurrences = [Occurrence]()
		var keyByName = [String: RootFunctionKey]()
		var conflictingNames = Set<String>()
		var heldNamesByName = [String: Set<String>]()
		var records = [RootFunctionRecord]()
		var work = codes.reversed().map { (code: $0, isInsideSendableFunction: false, holdingName: String?.none) }
		var levelsRead = 0
		while let (code, isInsideSendableFunction, holdingName) = work.popLast() {
			levelsRead += 1
			switch code.node {
			case .text:
				break
			case let .sequence(pieces), let .lines(pieces):
				work.append(contentsOf: pieces.reversed().map { ($0, isInsideSendableFunction, holdingName) })
			case let .indented(inner, _),
			     let .omittingRootFunctions(inner, _):
				work.append((inner, isInsideSendableFunction, holdingName))
			case let .place(plan) where plan.code.holdsRootFunction:
				work.append((plan.code, isInsideSendableFunction, holdingName))
			case .place:
				// A place records whether a root function is beneath it, so the walk reads no other place's tree.
				break
			case let .sendableFunction(inner):
				work.append((inner, true, holdingName))
			case let .rootFunction(record, inPlace):
				if let holdingName {
					heldNamesByName[holdingName, default: []].insert(record.name)
				}
				let key = RootFunctionKey(
					calledSeam: record.key.calledSeam,
					level: record.key.level,
					isSendable: record.isSendable || isInsideSendableFunction,
					inlinedFillKeys: record.key.inlinedFillKeys,
					fillsTakingPayloadFields: record.key.fillsTakingPayloadFields,
					typesDeclaredEscaping: record.key.typesDeclaredEscaping,
					labelsHiddenByReenteringCalls: record.key.labelsHiddenByReenteringCalls,
					calledFunctionNames: record.key.calledFunctionNames,
					indentation: record.key.indentation,
					text: record.key.text,
				)
				if observer != nil {
					occurrences.append(Occurrence(key: key, name: record.name, text: record.key.text ?? record.spelled(isSendable: key.isSendable).spelled()))
				}
				if key.isSendable, !record.canBeDeclaredSendable {
					conflictingNames.insert(record.name)
				}
				if let declaredKey = keyByName[record.name] {
					if declaredKey.ignoringSendability != key.ignoringSendability {
						conflictingNames.insert(record.name)
					} else if key.isSendable, !declaredKey.isSendable, let index = records.firstIndex(where: { $0.name == record.name }) {
						// Reached inside a `@Sendable` function too: declared `@Sendable` once for both.
						keyByName[record.name] = key
						records[index] = RootFunctionRecord(key: key, name: record.name, declaration: records[index].declaration, isSendable: true, calls: records[index].calls)
					}
				} else {
					keyByName[record.name] = key
					records.append(RootFunctionRecord(key: key, name: record.name, declaration: record.declaration, isSendable: key.isSendable, calls: record.calls))
				}
				// A fill's plan holds the root functions its tree declares: each is read where every call wrote it.
				if record.declaresCode, inPlace.holdsRootFunction {
					work.append((inPlace, isInsideSendableFunction || record.isSendable, record.name))
				}
			}
		}
		GenerationWork.record(levelsRead, by: .findingRootFunctions)
		observer?(occurrences)
		return (records, conflictingNames, heldNamesByName)
	}
}

/// The function a fill that shares its body calls (`ScopeGenerator.sharedFillBodyFunction`): its declaration line and its body.
struct FillBodyFunction: Sendable {
	/// The function's declaration, from its attributes to its opening brace.
	let declaration: String
	let body: FillBodyLayout
	let isSendable: Bool

	/// The function with its tree in the path key's layout, as a call writes it where the root does not declare it.
	var pathCode: GeneratedCode {
		ScopeGenerator.fillFunction(declaredBy: declaration, body: body.pathStatements, isSendable: isSendable)
	}

	/// The function with its tree in the type key's layout, where the type key lays it out, as a root declares it once,
	/// without the root functions named `declaredNames`, which the root declares beside it.
	func laidOutCode(omittingRootFunctionsNamed declaredNames: Set<String>) -> GeneratedCode {
		ScopeGenerator.fillFunction(declaredBy: declaration, body: body.laidOutStatements(omittingRootFunctionsNamed: declaredNames), isSendable: isSendable)
	}
}

/// The statements of a fill's shared body: the tree of the fill, between what precedes it, `leading`, and what follows it,
/// `trailing`, in a function whose parameters are `outerDeclarations`.
struct FillBodyLayout: Sendable {
	let leading: [GeneratedCode]
	let tree: [GeneratedCode]
	let outerDeclarations: [Property]
	let trailing: [GeneratedCode]

	/// The statements with the tree in the path key's layout.
	var pathStatements: [GeneratedCode] {
		leading + [.lines(tree)] + trailing
	}

	/// The statements with the tree in the type key's layout, where nothing precedes it and the type key lays it out, and in
	/// the path key's otherwise, without the root functions named `declaredNames`, which the root declares beside the body: a
	/// statement the type key keeps in the path key's code is written as text, which no omission around it reaches.
	func laidOutStatements(omittingRootFunctionsNamed declaredNames: Set<String>) -> [GeneratedCode] {
		guard leading.isEmpty,
		      let statements = TypeKeyBody.statements(ofFunctionBody: tree, outerDeclarations: outerDeclarations, omittingRootFunctionsNamed: declaredNames, indentation: ScopeGenerator.standardIndent)
		else { return pathStatements }
		return statements + trailing
	}
}
