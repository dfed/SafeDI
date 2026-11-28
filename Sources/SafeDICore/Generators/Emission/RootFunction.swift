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
/// so a root that calls a seam from many places declared each dispatcher once per call.
struct RootFunctionRecord: Sendable {
	/// What the function's text is a function of within one root: two records of one root with equal keys have equal text.
	let key: RootFunctionKey
	/// The function's name, which the call allocates and nothing renames.
	let name: String
	/// The declaration as the call writes it after `key.indentation`, from its keyword on: without that indentation and the
	/// attributes `isSendable` adds (`ScopeGenerator.localFunctionPrefix`).
	let textWithoutAttributes: String
	/// Whether the call declares the function `@Sendable nonisolated`.
	let isSendable: Bool
	/// The names of the root functions the text calls, which are declared with it or not at all.
	let calls: [String]

	/// The declaration, after its indentation, `@Sendable nonisolated` where `isSendable`.
	func spelled(isSendable: Bool) -> String {
		key.indentation + ScopeGenerator.localFunctionPrefix(isSendable: isSendable) + textWithoutAttributes
	}
}

/// What a root function's text is a function of, within one root: the called seam, the level of its tree the function
/// returns the struct of, and what of the call around it the text reads. Nothing compares the text itself; the graph
/// fuzzer checks that equal keys give equal text.
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
	/// The indentation the call writes the declaration after, which the body of every scope shares, and the root's
	/// statements too (`ScopeGenerator.rootStatementIndentation`).
	let indentation: String

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
			indentation: indentation,
		)
	}
}

/// Declares each root function of a root's plan once, at the root's top, in the order the plan first reaches it.
///
/// A name is declared at the top only where every record of it in the plan has one key, but for whether it is `@Sendable`,
/// and every function it calls is declared there too; every other record is written where the call put it, as it was
/// before. A function reached inside a `@Sendable` function (`GeneratedCode.sendableFunction(_:)`), or called by one
/// declared `@Sendable`, is declared `@Sendable nonisolated`, since a `@Sendable` function calls no function that is not.
/// A name reached both inside and outside one is declared once, `@Sendable nonisolated`: its text is the same at every
/// record of its key, so it compiles `nonisolated` wherever the one inside compiles, and it captures nothing, so plain
/// code calls it as it called the plain one.
public enum RootFunctionHoisting {
	/// A root function a root's plan reaches: its key, its name, and its text as the root would declare it.
	public struct Occurrence: Sendable {
		public let key: RootFunctionKey
		public let name: String
		public let text: String
	}

	/// Handed every root function each root's plan reaches, once per call that reaches it, in the order the plan reaches
	/// them, so the graph fuzzer can check that equal keys give equal text, which nothing in the generator compares.
	@TaskLocal public static var observer: TaskLocalFunction<@Sendable ([Occurrence]) -> Void>?

	/// `statements`, the root's body, whose statements are written after `indentation`, preceded by the root functions it
	/// declares once, each indented as a statement of the root.
	static func hoisted(_ statements: [GeneratedCode], indentation: String) -> [GeneratedCode] {
		let (records, conflictingNames) = recordsAndConflicts(in: statements, reportsOccurrences: true)
		let keyByName = Dictionary(records.map { ($0.name, $0.key) }, uniquingKeysWith: { first, _ in first })
		// A function that calls one kept in place is kept in place too, until none is left to keep.
		var keptNames = conflictingNames
		var keptCount: Int?
		while keptCount != keptNames.count {
			keptCount = keptNames.count
			let callersOfKept = records.filter { $0.calls.contains { keptNames.contains($0) || keyByName[$0] == nil } }.map(\.name)
			keptNames.formUnion(callersOfKept)
		}
		let declared = records.filter { !keptNames.contains($0.name) }
		guard !declared.isEmpty else { return statements }
		// A function a `@Sendable` one calls is `@Sendable` too, until no more is.
		var sendableNames = Set(declared.filter(\.isSendable).map(\.name))
		var sendableCount: Int?
		while sendableCount != sendableNames.count {
			sendableCount = sendableNames.count
			for record in declared where sendableNames.contains(record.name) {
				sendableNames.formUnion(record.calls)
			}
		}
		// A call's body is indented by the levels around it, so its declarations are written after its own indentation alone.
		return declared.map { record in
			.indented(.text(record.spelled(isSendable: sendableNames.contains(record.name))), by: indentation.hasPrefix(record.key.indentation) ? String(indentation.dropFirst(record.key.indentation.count)) : "")
		}
			+ [.omittingRootFunctions(.lines(statements), named: Set(declared.map(\.name)))]
	}

	/// The root functions `codes` hold, once per name, in the order they are reached, each keyed with the family a
	/// `@Sendable` function around it gives it.
	static func records(in codes: [GeneratedCode]) -> [RootFunctionRecord] {
		recordsAndConflicts(in: codes).records
	}

	/// The root functions `codes` hold, once per name, in the order they are reached, and the names reached with two keys.
	private static func recordsAndConflicts(in codes: [GeneratedCode], reportsOccurrences: Bool = false) -> (records: [RootFunctionRecord], conflictingNames: Set<String>) {
		let observer = reportsOccurrences ? observer : nil
		var occurrences = [Occurrence]()
		var keyByName = [String: RootFunctionKey]()
		var conflictingNames = Set<String>()
		var records = [RootFunctionRecord]()
		var work = codes.reversed().map { (code: $0, isInsideSendableFunction: false) }
		var levelsRead = 0
		while let (code, isInsideSendableFunction) = work.popLast() {
			levelsRead += 1
			switch code.node {
			case .text:
				break
			case let .sequence(pieces), let .lines(pieces):
				work.append(contentsOf: pieces.reversed().map { ($0, isInsideSendableFunction) })
			case let .indented(inner, _),
			     let .omittingRootFunctions(inner, _):
				work.append((inner, isInsideSendableFunction))
			case let .place(plan) where plan.code.holdsRootFunction:
				work.append((plan.code, isInsideSendableFunction))
			case .place:
				// A place records whether a root function is beneath it, so the walk reads no other place's tree.
				break
			case let .sendableFunction(inner):
				work.append((inner, true))
			case let .rootFunction(record, _):
				let key = RootFunctionKey(
					calledSeam: record.key.calledSeam,
					level: record.key.level,
					isSendable: record.isSendable || isInsideSendableFunction,
					inlinedFillKeys: record.key.inlinedFillKeys,
					fillsTakingPayloadFields: record.key.fillsTakingPayloadFields,
					typesDeclaredEscaping: record.key.typesDeclaredEscaping,
					labelsHiddenByReenteringCalls: record.key.labelsHiddenByReenteringCalls,
					indentation: record.key.indentation,
				)
				if observer != nil {
					occurrences.append(Occurrence(key: key, name: record.name, text: record.spelled(isSendable: key.isSendable)))
				}
				if let declaredKey = keyByName[record.name] {
					if declaredKey.ignoringSendability != key.ignoringSendability {
						conflictingNames.insert(record.name)
					} else if key.isSendable, !declaredKey.isSendable, let index = records.firstIndex(where: { $0.name == record.name }) {
						// Reached inside a `@Sendable` function too: declared `@Sendable` once for both.
						keyByName[record.name] = key
						records[index] = RootFunctionRecord(key: key, name: record.name, textWithoutAttributes: records[index].textWithoutAttributes, isSendable: true, calls: records[index].calls)
					}
				} else {
					keyByName[record.name] = key
					records.append(RootFunctionRecord(key: key, name: record.name, textWithoutAttributes: record.textWithoutAttributes, isSendable: key.isSendable, calls: record.calls))
				}
			}
		}
		GenerationWork.record(levelsRead, by: .findingRootFunctions)
		observer?(occurrences)
		return (records, conflictingNames)
	}
}
