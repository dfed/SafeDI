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

#if canImport(Glibc)
	import Glibc
#elseif canImport(Darwin)
	import Darwin
#endif

/// SHADOW EXPERIMENT, never merged: answers each place's question "what is the nearest declaration of this label?" from
/// one level per type and the route graph between the levels, with a memoized (level, label) query, and compares the
/// answers with the per-site lists the seam computes today. Nothing generated reads it. Enabled by the environment
/// variable `SAFEDI_SHADOW_REPORT`, the path of a file each computation appends one JSON line to.
public enum SeamRouteQueryShadow {
	public static let reportPath: String? = {
		guard let value = getenv("SAFEDI_SHADOW_REPORT") else { return nil }
		return String(cString: value)
	}()

	public static var isEnabled: Bool {
		reportPath != nil
	}

	/// A level as the route graph keys it: the type it builds and the property it leads through, the seam's root apart, a fill
	/// keyed by the type it builds beneath it.
	struct NodeKey: Hashable {
		let builtType: TypeDescription?
		let nextProperty: Property?
		let isSeamRoot: Bool
		let isInFill: Bool
		let filledType: TypeDescription?
	}

	/// What a place reads of a label: a field, a declaration it carries no field of, or nothing (the caller's scope).
	struct Outcome: Hashable {
		enum Kind: String, Hashable {
			case field
			case uncarried
			case none
		}

		let property: Property?
		let kind: Kind

		var description: String {
			switch kind {
			case .none: "none"
			case .field: "field \(property?.asSource ?? "")"
			case .uncarried: "uncarried \(property?.asSource ?? "")"
			}
		}
	}

	public struct Report: Sendable {
		public var seamType = ""
		public var places = 0
		public var nodes = 0
		public var edges = 0
		public var levelConflicts = 0
		public var levelConflictsOnlyInFunctionFacts = 0
		public var cases = 0
		public var queries = 0
		public var memoEntries = 0
		public var graphCycles = 0
		public var mismatches = 0
		public var routeDependentAnswers = 0
		public var mismatchSamples = [String]()
		public var conflictSamples = [String]()
		public var queryNanoseconds: Int64 = 0
		public var graphNanoseconds: Int64 = 0
		public var perSiteWalkNanoseconds: Int64 = 0
	}

	static func nanoseconds(_ duration: Duration) -> Int64 {
		duration.components.seconds * 1_000_000_000 + duration.components.attoseconds / 1_000_000_000
	}

	public static func report(of placeLevels: SeamPlaceLevels) -> Report {
		var report = Report()
		report.seamType = placeLevels.seamType.asSource
		report.places = placeLevels.places.count
		report.perSiteWalkNanoseconds = nanoseconds(placeLevels.perSiteWalkDuration)

		// The graph: one level per key, the first met; parents by key. Built here from the per-site levels, which a real
		// implementation would read from each type's declarations once.
		let graphStart = ContinuousClock.now
		var indexByKey = [NodeKey: Int]()
		var levels = [SeamPlaceLevels.Level]()
		var parents = [Set<Int>]()
		var placeNodes = [[Int]]()
		for place in placeLevels.places {
			var nodes = [Int]()
			for (index, level) in place.levels.enumerated() {
				let key = NodeKey(
					builtType: level.builtType,
					nextProperty: level.nextProperty,
					isSeamRoot: index == place.levels.count - 1,
					isInFill: level.isInFill,
					filledType: level.builtType == nil && index > 0 ? place.levels[index - 1].builtType : nil,
				)
				if let existing = indexByKey[key] {
					let first = levels[existing]
					if first.declarations != level.declarations || first.opensSendableFunction != level.opensSendableFunction {
						report.levelConflicts += 1
						let functionFacts = { (declarations: [SeamPlaceLevels.Level.Declaration]) in
							declarations.filter { !$0.isCycleParameter && !$0.isReboundByBuilderFunction }
						}
						if functionFacts(first.declarations) == functionFacts(level.declarations), first.opensSendableFunction == level.opensSendableFunction {
							report.levelConflictsOnlyInFunctionFacts += 1
						} else if report.conflictSamples.count < 3 {
							report.conflictSamples.append("level \(level.builtType?.asSource ?? "fill") before \(level.nextProperty?.asSource ?? "-") at \(place.sitePath.map(\.label).joined(separator: ".")): \(describe(first)) vs \(describe(level))")
						}
					}
					nodes.append(existing)
				} else {
					indexByKey[key] = levels.count
					nodes.append(levels.count)
					levels.append(level)
					parents.append([])
				}
			}
			for (index, node) in nodes.enumerated() where index + 1 < nodes.count {
				parents[node].insert(nodes[index + 1])
			}
			placeNodes.append(nodes)
		}
		report.nodes = levels.count
		report.edges = parents.reduce(0) { $0 + $1.count }
		// Each level's nearest declaration of each label: within a level, the later one.
		let declarationByLabelByNode = levels.map { level in
			var declarationByLabel = [String: SeamPlaceLevels.Level.Declaration]()
			for declaration in level.declarations {
				declarationByLabel[declaration.property.label] = declaration
			}
			return declarationByLabel
		}
		report.graphNanoseconds = nanoseconds(ContinuousClock.now - graphStart)

		// The cases: places grouped by their owner's level and whether the site opens a `@Sendable` function.
		struct CaseKey: Hashable {
			let node: Int
			let siteOpensSendableFunction: Bool
		}
		var placeIndicesByCase = [CaseKey: [Int]]()
		var caseOrder = [CaseKey]()
		for (index, place) in placeLevels.places.enumerated() {
			guard let owner = placeNodes[index].first else { continue }
			let key = CaseKey(node: owner, siteOpensSendableFunction: place.siteOpensSendableFunction)
			if placeIndicesByCase[key] == nil {
				caseOrder.append(key)
			}
			placeIndicesByCase[key, default: []].append(index)
		}
		report.cases = caseOrder.count

		// Today's answers per case and label, gathered first so the query's time is its own.
		struct Question: Hashable {
			let caseKey: CaseKey
			let label: String
		}
		var todaysAnswers = [Question: Set<Outcome>]()
		var questions = [Question]()
		for caseKey in caseOrder {
			let placeIndices = placeIndicesByCase[caseKey] ?? []
			var labels = [String]()
			var seenLabels = Set<String>()
			for placeIndex in placeIndices {
				for level in placeLevels.places[placeIndex].levels {
					for declaration in level.declarations where seenLabels.insert(declaration.property.label).inserted {
						labels.append(declaration.property.label)
					}
				}
			}
			for label in labels {
				var outcomes = Set<Outcome>()
				for placeIndex in placeIndices {
					let place = placeLevels.places[placeIndex]
					if let field = place.carriedFields.last(where: { $0.label == label }) {
						outcomes.insert(Outcome(property: field, kind: .field))
					} else if let uncarried = place.carriedUncarriedProperties.last(where: { $0.label == label }) {
						outcomes.insert(Outcome(property: uncarried, kind: .uncarried))
					} else {
						outcomes.insert(Outcome(property: nil, kind: .none))
					}
				}
				let question = Question(caseKey: caseKey, label: label)
				todaysAnswers[question] = outcomes
				questions.append(question)
			}
		}

		// The query: the outcomes over every route from the seam's root to the level, memoized per (level, label, whether a
		// `@Sendable` function encloses the place below the level).
		struct MemoKey: Hashable {
			let node: Int
			let label: String
			let crossed: Bool
		}
		var memo = [MemoKey: Set<Outcome>]()
		var onStack = Set<MemoKey>()
		var graphCycles = 0
		func answer(node: Int, label: String, crossed: Bool) -> Set<Outcome> {
			if let declaration = declarationByLabelByNode[node][label] {
				return [outcome(of: declaration, crossed: crossed)]
			}
			guard !parents[node].isEmpty else { return [Outcome(property: nil, kind: .none)] }
			let key = MemoKey(node: node, label: label, crossed: crossed)
			if let known = memo[key] {
				return known
			}
			guard onStack.insert(key).inserted else {
				graphCycles += 1
				return []
			}
			let parentCrossed = crossed || levels[node].opensSendableFunction
			var outcomes = Set<Outcome>()
			for parent in parents[node] {
				outcomes.formUnion(answer(node: parent, label: label, crossed: parentCrossed))
			}
			onStack.remove(key)
			memo[key] = outcomes
			return outcomes
		}
		var queryAnswers = [Question: Set<Outcome>]()
		let queryStart = ContinuousClock.now
		for question in questions {
			queryAnswers[question] = answer(node: question.caseKey.node, label: question.label, crossed: question.caseKey.siteOpensSendableFunction)
		}
		report.queryNanoseconds = nanoseconds(ContinuousClock.now - queryStart)
		report.queries = questions.count
		report.memoEntries = memo.count
		report.graphCycles = graphCycles

		for question in questions {
			let today = todaysAnswers[question] ?? []
			let query = queryAnswers[question] ?? []
			if query.count > 1 {
				report.routeDependentAnswers += 1
			}
			guard today != query else { continue }
			report.mismatches += 1
			if report.mismatchSamples.count < 5 {
				let placeIndices = placeIndicesByCase[question.caseKey] ?? []
				let paths = placeIndices.prefix(3).map { placeLevels.places[$0].sitePath.map(\.label).joined(separator: ".") }
				report.mismatchSamples.append("label \(question.label) at \(paths.joined(separator: " | ")) (\(placeIndices.count) sites): today \(today.map(\.description).sorted()) query \(query.map(\.description).sorted())")
			}
		}
		return report
	}

	static func outcome(of declaration: SeamPlaceLevels.Level.Declaration, crossed: Bool) -> Outcome {
		if !declaration.isBoundBeforeNextProperty {
			Outcome(property: declaration.property, kind: .uncarried)
		} else if !crossed {
			Outcome(property: declaration.property, kind: .field)
		} else if declaration.isSeamParameter {
			Outcome(property: nil, kind: .none)
		} else {
			Outcome(property: declaration.property, kind: .uncarried)
		}
	}

	static func describe(_ level: SeamPlaceLevels.Level) -> String {
		let declarations = level.declarations.map { declaration in
			var text = declaration.property.asSource
			if !declaration.isBoundBeforeNextProperty {
				text += "(after)"
			}
			if declaration.isCycleParameter {
				text += "(cycle)"
			}
			if declaration.isReboundByBuilderFunction {
				text += "(rebound)"
			}
			return text
		}
		return "[\(declarations.joined(separator: ", "))]\(level.opensSendableFunction ? " @Sendable" : "")"
	}

	/// Appends the report of `placeLevels` to the report file, when enabled.
	public static func record(_ placeLevels: SeamPlaceLevels) {
		guard let reportPath else { return }
		let report = report(of: placeLevels)
		func quoted(_ text: String) -> String {
			var escaped = ""
			for scalar in text.unicodeScalars {
				switch scalar {
				case "\"": escaped += "\\\""
				case "\\": escaped += "\\\\"
				case "\n": escaped += "\\n"
				case "\t": escaped += "\\t"
				default:
					if scalar.value < 0x20 {
						escaped += " "
					} else {
						escaped.unicodeScalars.append(scalar)
					}
				}
			}
			return "\"" + escaped + "\""
		}
		var line = "{"
		line += "\"seam\":\(quoted(report.seamType)),\"places\":\(report.places),\"nodes\":\(report.nodes),\"edges\":\(report.edges)"
		line += ",\"levelConflicts\":\(report.levelConflicts),\"levelConflictsOnlyInFunctionFacts\":\(report.levelConflictsOnlyInFunctionFacts)"
		line += ",\"cases\":\(report.cases),\"queries\":\(report.queries),\"memoEntries\":\(report.memoEntries),\"graphCycles\":\(report.graphCycles)"
		line += ",\"mismatches\":\(report.mismatches),\"routeDependentAnswers\":\(report.routeDependentAnswers)"
		line += ",\"queryNs\":\(report.queryNanoseconds),\"graphNs\":\(report.graphNanoseconds),\"perSiteWalkNs\":\(report.perSiteWalkNanoseconds)"
		line += ",\"testName\":\(quoted(SeamRouteQueryShadow.context ?? ""))"
		line += ",\"mismatchSamples\":[\(report.mismatchSamples.map(quoted).joined(separator: ","))]"
		line += ",\"conflictSamples\":[\(report.conflictSamples.map(quoted).joined(separator: ","))]"
		line += "}\n"
		let descriptor = open(reportPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard descriptor >= 0 else { return }
		var bytes = Array(line.utf8)
		_ = bytes.withUnsafeMutableBytes { write(descriptor, $0.baseAddress, $0.count) }
		close(descriptor)
	}

	/// A name for the run the reports come from, such as a test's.
	@TaskLocal public static var context: String?
}
