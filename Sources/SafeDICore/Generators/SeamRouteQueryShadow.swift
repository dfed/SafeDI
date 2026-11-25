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

	/// A level as built: its key, and what one build of it binds, which can differ between builds of one type.
	struct VariantKey: Hashable {
		let key: NodeKey
		let declarations: [SeamPlaceLevels.Level.Declaration]
		let opensSendableFunction: Bool
		let reentryDeclarations: [Property]
		let fillBaseStack: [Property]
		let fillBaseConcreteTypes: [TypeDescription]
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
		public var fillLevelVariants = 0
		public var sendableOnlyVariants = 0
		public var otherVariants = 0
		public var types = 0
		public var cases = 0
		public var queries = 0
		public var memoEntries = 0
		public var graphCycles = 0
		public var mismatches = 0
		public var reentryQuestions = 0
		public var reentryMismatches = 0
		public var hiddenQuestions = 0
		public var hiddenMismatches = 0
		public var stackSiteMismatches = 0
		public var stackCaseMismatches = 0
		public var stackRouteDependentCases = 0
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
		var indexByVariant = [VariantKey: Int]()
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
				let variantKey = VariantKey(key: key, declarations: level.declarations, opensSendableFunction: level.opensSendableFunction, reentryDeclarations: level.reentryDeclarations, fillBaseStack: level.fillBaseStack, fillBaseConcreteTypes: level.fillBaseConcreteTypes)
				if let existing = indexByVariant[variantKey] {
					nodes.append(existing)
				} else {
					if let first = indexByKey[key].map({ levels[$0] }) {
						// Another build of the type binds otherwise than its first: a variant of the level.
						report.levelConflicts += 1
						let functionFacts = { (declarations: [SeamPlaceLevels.Level.Declaration]) in
							declarations.filter { !$0.isCycleParameter && !$0.isReboundByBuilderFunction }
						}
						if level.builtType == nil {
							report.fillLevelVariants += 1
						} else if first.declarations == level.declarations {
							report.sendableOnlyVariants += 1
						} else if functionFacts(first.declarations) == functionFacts(level.declarations) {
							report.levelConflictsOnlyInFunctionFacts += 1
						} else {
							report.otherVariants += 1
							if report.conflictSamples.count < 3 {
								report.conflictSamples.append("level \(level.builtType?.asSource ?? "fill") before \(level.nextProperty?.asSource ?? "-") at \(place.sitePath.map(\.label).joined(separator: ".")): \(describe(first)) vs \(describe(level))")
							}
						}
					} else {
						indexByKey[key] = levels.count
					}
					indexByVariant[variantKey] = levels.count
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
		report.types = indexByKey.count
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
			let outcomeByLabelByPlace = placeIndices.map { placeIndex in
				let place = placeLevels.places[placeIndex]
				var outcomeByLabel = [String: Outcome]()
				for uncarried in place.carriedUncarriedProperties {
					outcomeByLabel[uncarried.label] = Outcome(property: uncarried, kind: .uncarried)
				}
				for field in place.carriedFields {
					outcomeByLabel[field.label] = Outcome(property: field, kind: .field)
				}
				return outcomeByLabel
			}
			for label in labels {
				var outcomes = Set<Outcome>()
				for outcomeByLabel in outcomeByLabelByPlace {
					outcomes.insert(outcomeByLabel[label] ?? Outcome(property: nil, kind: .none))
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
		// Iterative, since a seam's tree can be deeper than a concurrency thread's stack.
		func direct(_ key: MemoKey) -> Set<Outcome>? {
			if let declaration = declarationByLabelByNode[key.node][key.label] {
				return [outcome(of: declaration, crossed: key.crossed)]
			}
			if parents[key.node].isEmpty {
				return [Outcome(property: nil, kind: .none)]
			}
			return nil
		}
		func answer(node: Int, label: String, crossed: Bool) -> Set<Outcome> {
			let start = MemoKey(node: node, label: label, crossed: crossed)
			if let known = direct(start) ?? memo[start] {
				return known
			}
			var stack = [(key: start, isExpanded: false)]
			while let (key, isExpanded) = stack.popLast() {
				let parentCrossed = key.crossed || levels[key.node].opensSendableFunction
				let parentKeys = parents[key.node].map { MemoKey(node: $0, label: key.label, crossed: parentCrossed) }
				if isExpanded {
					var outcomes = Set<Outcome>()
					for parentKey in parentKeys {
						if let known = direct(parentKey) ?? memo[parentKey] {
							outcomes.formUnion(known)
						} else {
							graphCycles += 1
						}
					}
					onStack.remove(key)
					memo[key] = outcomes
					continue
				}
				guard memo[key] == nil, onStack.insert(key).inserted else { continue }
				stack.append((key, true))
				for parentKey in parentKeys where direct(parentKey) == nil && memo[parentKey] == nil && !onStack.contains(parentKey) {
					stack.append((parentKey, false))
				}
			}
			return memo[start] ?? []
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

		// Cycle re-entry: walking up from the place, the outermost level whose function a cycle re-enters, below the nearest
		// declaration of the label, hands the place that level's declaration between. Memoized per (level, label).
		let reentryByLabelByNode = levels.map { level in
			var reentryByLabel = [String: Property]()
			for property in level.reentryDeclarations where reentryByLabel[property.label] == nil {
				reentryByLabel[property.label] = property
			}
			return reentryByLabel
		}
		struct ReentryKey: Hashable {
			let node: Int
			let label: String
		}
		var reentryMemo = [ReentryKey: Set<Property?>]()
		var reentryOnStack = Set<ReentryKey>()
		func reentryAnswer(node: Int, label: String) -> Set<Property?> {
			let start = ReentryKey(node: node, label: label)
			var stack = [(key: start, isExpanded: false)]
			while let (key, isExpanded) = stack.popLast() {
				guard reentryMemo[key] == nil else { continue }
				if declarationByLabelByNode[key.node][key.label] != nil {
					reentryMemo[key] = [nil]
					continue
				}
				let parentKeys = parents[key.node].map { ReentryKey(node: $0, label: key.label) }
				if isExpanded {
					var fromAbove = Set<Property?>()
					if parentKeys.isEmpty {
						fromAbove.insert(nil)
					}
					for parentKey in parentKeys {
						if let known = reentryMemo[parentKey] {
							fromAbove.formUnion(known)
						} else {
							report.graphCycles += 1
						}
					}
					let own = reentryByLabelByNode[key.node][key.label]
					reentryMemo[key] = Set(fromAbove.map { $0 ?? own })
					reentryOnStack.remove(key)
					continue
				}
				guard reentryOnStack.insert(key).inserted else { continue }
				stack.append((key, true))
				for parentKey in parentKeys where reentryMemo[parentKey] == nil && !reentryOnStack.contains(parentKey) {
					stack.append((parentKey, false))
				}
			}
			return reentryMemo[start] ?? []
		}
		for caseKey in caseOrder {
			let placeIndices = placeIndicesByCase[caseKey] ?? []
			let siteLabel = levels[caseKey.node].nextProperty?.label
			var labels = [String]()
			var seenLabels = Set<String>()
			for placeIndex in placeIndices {
				for property in placeLevels.places[placeIndex].carriedCycleReentryProperties where seenLabels.insert(property.label).inserted {
					labels.append(property.label)
				}
				for node in placeNodes[placeIndex] {
					for property in levels[node].reentryDeclarations where seenLabels.insert(property.label).inserted {
						labels.append(property.label)
					}
				}
			}
			for label in labels {
				var today = Set<Property?>()
				for placeIndex in placeIndices {
					today.insert(placeLevels.places[placeIndex].carriedCycleReentryProperties.first { $0.label == label })
				}
				let query: Set<Property?> = label == siteLabel ? [nil] : reentryAnswer(node: caseKey.node, label: label)
				report.reentryQuestions += 1
				guard today != query else { continue }
				report.reentryMismatches += 1
				report.mismatches += 1
				if report.mismatchSamples.count < 5 {
					let paths = placeIndices.prefix(3).map { placeLevels.places[$0].sitePath.map(\.label).joined(separator: ".") }
					func spelled(_ answers: Set<Property?>) -> [String] {
						answers.map { $0?.asSource ?? "none" }.sorted()
					}
					report.mismatchSamples.append("re-entry label \(label) at \(paths.joined(separator: " | ")) (\(placeIndices.count) sites): today \(spelled(today)) query \(spelled(query))")
				}
			}
		}
		// Declarations a fill's field of a seam parameter hides: where the place's nearest declaration of the label is such a
		// field, carried, the nearest declaration above that fill of another property.
		struct HiddenKey: Hashable {
			let node: Int
			let label: String
			let crossed: Bool
		}
		var hiddenMemo = [HiddenKey: Set<Property?>]()
		var hiddenOnStack = Set<HiddenKey>()
		// Iterative, as `answer` is: a seam's tree can be deeper than a concurrency thread's stack.
		func hiddenAnswer(node: Int, label: String, crossed: Bool) -> Set<Property?> {
			let start = HiddenKey(node: node, label: label, crossed: crossed)
			var stack = [(key: start, isExpanded: false)]
			while let (key, isExpanded) = stack.popLast() {
				guard hiddenMemo[key] == nil else { continue }
				if let declaration = declarationByLabelByNode[key.node][key.label] {
					var result = Set<Property?>()
					if levels[key.node].builtType == nil, declaration.isFieldOfSeamParameter, outcome(of: declaration, crossed: key.crossed).kind == .field {
						// A declaration the fill binds before the field, such as one a passing-up seam binds that the filled seam's struct
						// does not carry, is the nearest above the field.
						let earlier = levels[key.node].declarations.prefix { $0 != declaration }.last { $0.property.label == key.label }
						if let earlier {
							result.insert(earlier.property == declaration.property ? nil : earlier.property)
						}
						for parent in parents[key.node] where earlier == nil {
							for above in answer(node: parent, label: key.label, crossed: false) {
								result.insert(above.property == declaration.property ? nil : above.property)
							}
						}
					}
					if result.isEmpty {
						result.insert(nil)
					}
					hiddenMemo[key] = result
					continue
				}
				let parentCrossed = key.crossed || levels[key.node].opensSendableFunction
				let parentKeys = parents[key.node].map { HiddenKey(node: $0, label: key.label, crossed: parentCrossed) }
				if parentKeys.isEmpty {
					hiddenMemo[key] = [nil]
					continue
				}
				if isExpanded {
					var result = Set<Property?>()
					for parentKey in parentKeys {
						if let known = hiddenMemo[parentKey] {
							result.formUnion(known)
						} else {
							report.graphCycles += 1
						}
					}
					hiddenMemo[key] = result
					hiddenOnStack.remove(key)
					continue
				}
				guard hiddenOnStack.insert(key).inserted else { continue }
				stack.append((key, true))
				for parentKey in parentKeys where hiddenMemo[parentKey] == nil && !hiddenOnStack.contains(parentKey) {
					stack.append((parentKey, false))
				}
			}
			return hiddenMemo[start] ?? []
		}
		for caseKey in caseOrder {
			let placeIndices = placeIndicesByCase[caseKey] ?? []
			var labels = [String]()
			var seenLabels = Set<String>()
			for placeIndex in placeIndices {
				for property in placeLevels.places[placeIndex].carriedHiddenByFieldProperties where seenLabels.insert(property.label).inserted {
					labels.append(property.label)
				}
				for node in placeNodes[placeIndex] {
					for declaration in levels[node].declarations where declaration.isFieldOfSeamParameter && seenLabels.insert(declaration.property.label).inserted {
						labels.append(declaration.property.label)
					}
				}
			}
			for label in labels {
				var today = Set<Property?>()
				for placeIndex in placeIndices {
					today.insert(placeLevels.places[placeIndex].carriedHiddenByFieldProperties.first { $0.label == label })
				}
				let query = hiddenAnswer(node: caseKey.node, label: label, crossed: caseKey.siteOpensSendableFunction)
				report.hiddenQuestions += 1
				guard today != query else { continue }
				report.hiddenMismatches += 1
				report.mismatches += 1
				if report.mismatchSamples.count < 5 {
					let paths = placeIndices.prefix(3).map { placeLevels.places[$0].sitePath.map(\.label).joined(separator: ".") }
					report.mismatchSamples.append("hidden label \(label) at \(paths.joined(separator: " | ")): today \(today.map { $0?.asSource ?? "none" }.sorted()) query \(query.map { $0?.asSource ?? "none" }.sorted())")
				}
			}
		}

		// The stack each place's owner is built with: per place, derived from its own levels; per case, the entries of every
		// route, from the graph.
		struct StackEntry: Hashable {
			let property: Property
			let concreteType: TypeDescription
		}
		func entries(of property: Property, builtAs concreteType: TypeDescription) -> [StackEntry] {
			var result = [StackEntry]()
			if let instance = property.asLazilyInstantiatedInstanceProperty {
				result.append(StackEntry(property: instance, concreteType: concreteType))
			}
			result.append(StackEntry(property: property, concreteType: concreteType))
			return result
		}
		func fillBase(of level: SeamPlaceLevels.Level) -> [StackEntry] {
			zip(level.fillBaseStack, level.fillBaseConcreteTypes).map { StackEntry(property: $0, concreteType: $1) }
		}
		var stackMemo = [Int: Set<StackEntry>]()
		var stackOnStack = Set<Int>()
		func stackEntries(node: Int) -> Set<StackEntry> {
			var stack = [(node: node, isExpanded: false)]
			while let (visited, isExpanded) = stack.popLast() {
				guard stackMemo[visited] == nil else { continue }
				guard let builtType = levels[visited].builtType else {
					stackMemo[visited] = Set(fillBase(of: levels[visited]))
					continue
				}
				if isExpanded {
					var result = Set<StackEntry>()
					for parent in parents[visited] {
						if let property = levels[parent].nextProperty {
							result.formUnion(entries(of: property, builtAs: builtType))
						}
						if let known = stackMemo[parent] {
							result.formUnion(known)
						} else {
							report.graphCycles += 1
						}
					}
					stackMemo[visited] = result
					stackOnStack.remove(visited)
					continue
				}
				guard stackOnStack.insert(visited).inserted else { continue }
				stack.append((visited, true))
				for parent in parents[visited] where stackMemo[parent] == nil && !stackOnStack.contains(parent) {
					stack.append((parent, false))
				}
			}
			return stackMemo[node] ?? []
		}
		for caseKey in caseOrder {
			let placeIndices = placeIndicesByCase[caseKey] ?? []
			var today = Set<StackEntry>()
			var distinctStacks = Set<[StackEntry]>()
			for placeIndex in placeIndices {
				let place = placeLevels.places[placeIndex]
				let carried = zip(place.carriedStack, place.carriedStackConcreteTypes).map { StackEntry(property: $0, concreteType: $1) }
				today.formUnion(carried)
				distinctStacks.insert(carried)
				var derived = [StackEntry]()
				for (index, level) in place.levels.enumerated() {
					guard let builtType = level.builtType else {
						derived += fillBase(of: level)
						break
					}
					guard index + 1 < place.levels.count else { break }
					if let property = place.levels[index + 1].nextProperty {
						derived += entries(of: property, builtAs: builtType)
					}
				}
				if derived != carried {
					report.stackSiteMismatches += 1
					report.mismatches += 1
					if report.mismatchSamples.count < 5 {
						report.mismatchSamples.append("stack at \(place.sitePath.map(\.label).joined(separator: ".")): today \(carried.map { "\($0.property.asSource)@\($0.concreteType.asSource)" }) derived \(derived.map { "\($0.property.asSource)@\($0.concreteType.asSource)" })")
					}
				}
			}
			if distinctStacks.count > 1 {
				report.stackRouteDependentCases += 1
			}
			if today != stackEntries(node: caseKey.node) {
				report.stackCaseMismatches += 1
				report.mismatches += 1
				if report.mismatchSamples.count < 5 {
					report.mismatchSamples.append("stack entries of case at \(placeLevels.places[placeIndices[0]].sitePath.map(\.label).joined(separator: ".")): today \(today.count) query \(stackEntries(node: caseKey.node).count)")
				}
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
		line += ",\"fillLevelVariants\":\(report.fillLevelVariants),\"sendableOnlyVariants\":\(report.sendableOnlyVariants),\"otherVariants\":\(report.otherVariants),\"types\":\(report.types)"
		line += ",\"cases\":\(report.cases),\"queries\":\(report.queries),\"memoEntries\":\(report.memoEntries),\"graphCycles\":\(report.graphCycles)"
		line += ",\"reentryQuestions\":\(report.reentryQuestions),\"reentryMismatches\":\(report.reentryMismatches)"
		line += ",\"hiddenQuestions\":\(report.hiddenQuestions),\"hiddenMismatches\":\(report.hiddenMismatches)"
		line += ",\"stackSiteMismatches\":\(report.stackSiteMismatches),\"stackCaseMismatches\":\(report.stackCaseMismatches),\"stackRouteDependentCases\":\(report.stackRouteDependentCases)"
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
