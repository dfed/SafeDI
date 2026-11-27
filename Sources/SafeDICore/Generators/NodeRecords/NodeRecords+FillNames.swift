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

/// The names a seam call's code gives its fills' and dispatchers' functions, and the parameter each fill takes its case's
/// values under, made from the call's fills and dispatchers by key: the names the tree gives them, which nothing before
/// this step reads (every other record of the call names a fill or a dispatcher by its key).
///
/// One allocator names a call's functions, apart from what encloses the call: the names of the fills and dispatchers
/// enclosing it, and those the seam whose tree holds it binds for its builders; none for a root's call. It claims each
/// fill's stem in the order the call's hole arguments list the fills, once per case, so every place of a case shares the
/// first place's function, then each dispatcher's stem in the order the call declares them. Nothing decided after the
/// names (which fills are written inline, which dispatchers the root declares) renames one.
struct FillNames: Sendable {
	/// A fill of the call, in the order the call's hole arguments list them.
	struct Fill: Sendable {
		init(caseKey: String, functionNameStem: String, labelsReadOrDeclared: some Sequence<String>) {
			self.caseKey = caseKey
			self.functionNameStem = functionNameStem
			self.labelsReadOrDeclared = Set(labelsReadOrDeclared)
		}

		/// The case the fill fills (`ScopeGenerator.fillCaseKey(of:)`), which every place of the case shares.
		let caseKey: String
		/// What the allocator is asked to claim for the fill's function (`ScopeGenerator.fillFunctionName(of:)`).
		let functionNameStem: String
		/// Each label the fill's tree reads and each name it declares, which its scope parameter is named apart from.
		let labelsReadOrDeclared: Set<String>
	}

	/// A dispatcher of the call, in the order the call declares them.
	struct Dispatcher: Sendable {
		/// The dispatcher's key (`FillDispatcher.key`).
		let key: String
		/// What the allocator is asked to claim for the dispatcher's function (`FillDispatcher.functionNameStem`).
		let functionNameStem: String
	}

	/// A fill's function and scope parameter, by the fill's case.
	struct NamedFill: Equatable, Sendable {
		let caseKey: String
		let functionName: String
		let scopeParameterName: String
	}

	/// A dispatcher's function, by the dispatcher's key.
	struct NamedDispatcher: Equatable, Sendable {
		let key: String
		let functionName: String
	}

	/// - Parameters:
	///   - reservedNames: The names enclosing the call, which no function of the call takes: for a call in a seam's tree,
	///     those the seam binds for its builders (`RootScopeInfo.SeamTree.namesBoundForBuilders`), and for a call inside a
	///     fill, the names of the fills and dispatchers enclosing it.
	///   - fills: The call's fills, in the order its hole arguments list them, without those an enclosing call fills.
	///   - dispatchers: The call's dispatchers, in the order it declares them, without those an enclosing call declares.
	init(reserving reservedNames: some Sequence<String>, fills: [Fill], dispatchers: [Dispatcher]) {
		self.reservedNames = Array(reservedNames)
		var names = GeneratedNameAllocator(reserving: Set(self.reservedNames))
		var namedFills = [NamedFill]()
		var fillIndexByCaseKey = [String: Int]()
		for fill in fills where fillIndexByCaseKey[fill.caseKey] == nil {
			fillIndexByCaseKey[fill.caseKey] = namedFills.count
			namedFills.append(NamedFill(
				caseKey: fill.caseKey,
				functionName: names.claim(fill.functionNameStem),
				scopeParameterName: Self.scopeParameterName(apartFrom: fill.labelsReadOrDeclared),
			))
		}
		self.fills = namedFills
		self.fillIndexByCaseKey = fillIndexByCaseKey
		self.dispatchers = dispatchers.map { NamedDispatcher(key: $0.key, functionName: names.claim($0.functionNameStem)) }
		dispatcherIndexByKey = Dictionary(self.dispatchers.enumerated().map { ($0.element.key, $0.offset) }, uniquingKeysWith: { first, _ in first })
	}

	/// The names enclosing the call, which no function of the call takes.
	let reservedNames: [String]
	/// The call's fills, one per case, in the order the call names them.
	let fills: [NamedFill]
	/// The call's dispatchers, in the order it declares them.
	let dispatchers: [NamedDispatcher]

	/// The function of the fill of the case of `caseKey`, `nil` for a case the call does not fill.
	func functionName(ofFill caseKey: String) -> String? {
		fillIndexByCaseKey[caseKey].map { fills[$0].functionName }
	}

	/// The dispatcher of `key`'s function, `nil` for a dispatcher the call does not declare.
	func functionName(ofDispatcher key: String) -> String? {
		dispatcherIndexByKey[key].map { dispatchers[$0].functionName }
	}

	/// The parameter the fill of the case of `caseKey` takes its case's values under, `nil` for a case the call does not fill.
	func scopeParameterName(ofFill caseKey: String) -> String? {
		fillIndexByCaseKey[caseKey].map { fills[$0].scopeParameterName }
	}

	/// `scope`, with `_` appended while `labels` holds it: a fill's parameter is named apart from what its tree reads or
	/// declares by name, which it would hide.
	static func scopeParameterName(apartFrom labels: Set<String>) -> String {
		var name = "scope"
		while labels.contains(name) {
			name += "_"
		}
		return name
	}

	private let fillIndexByCaseKey: [String: Int]
	private let dispatcherIndexByKey: [String: Int]
}

/// A seam call's names for its fills' and dispatchers' functions as the call claims them, in claiming order, beside the
/// same names made from the call's fills and dispatchers alone (`FillNames`).
public struct FillNamesObservation: Sendable {
	public let claimed: [String]
	public let fromRecords: [String]

	/// Called with each call that fills a builder as it names its functions, when set: by the tests, never by the tool.
	@TaskLocal public static var observer: (@Sendable (FillNamesObservation) -> Void)?
}
