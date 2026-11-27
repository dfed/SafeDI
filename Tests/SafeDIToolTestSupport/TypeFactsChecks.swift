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

import Foundation
import SafeDICore
import Testing

/// The checks of step 0 of the per-type facts design: every place a tree's build walks against the world's graph
/// (`TypeFactsReport`), which the memo oracle hands every test and fuzzer graph.
///
/// 1. Each place maps to a node: the root to the graph's root, each other place to its parent's node's edge.
/// 2. Each place that does not close a cycle builds its node's instantiated edges, in order, then some of its fills, in
///    order; one that closes a cycle builds nothing and repeats a node of its path.
/// 3. A place's subtree reads of the context above it only what its node declares it reads (`readsFromAbove`).
/// 4. Places of one node whose declared reads are answered alike build children answered alike, in the same order: the
///    node and those answers are a variant.
/// 5. The first place of each node is on the node's first route.
/// 6. As 4, for a pair one of whose places closes a cycle, and so builds what the place it closes on builds.
/// 7. As 5, against a walk that stops where a place closes a cycle, as the tree does.
/// 8. As 2's second half, for a closing place inside a fill, which can close on the path of the filled seam.
/// 9. As 3, for a place whose subtree closes a cycle, which reads the cycle parameters it passes.
/// 10. Places the world's variants map to one variant (the root place to the root's, each other to the variant its parent's
///     variant calls at the edge the place is built for) answer their declared reads alike, but for what a parameter
///     carries: a read only if available (rule 1), and whether a wrapper is still being built (rule 2).
///
/// Findings are recorded as issues only where `SAFEDI_TYPE_FACTS_STRICT` is set, until every graph passes; a run that
/// sets `SAFEDI_TYPE_FACTS_LOG` to a file appends a line per tree to it, with each check's count of findings and its
/// first finding, for a sweep.
enum TypeFactsChecks {
	static func check(_ report: TypeFactsReport) {
		let result = findings(of: report)
		let environment = ProcessInfo.processInfo.environment
		if environment["SAFEDI_TYPE_FACTS_STRICT"] != nil {
			for (check, findings) in result.findingsByCheck.sorted(by: { $0.key < $1.key }) {
				for finding in findings.prefix(3) {
					Issue.record(Comment(rawValue: "Type facts check \(check), root \(report.root): \(finding)"))
				}
			}
			for finding in result.check10OwedUncovered.prefix(3) {
				Issue.record(Comment(rawValue: "Type facts check 10, root \(report.root): \(finding)"))
			}
		}
		if let path = environment["SAFEDI_TYPE_FACTS_LOG"], !path.isEmpty {
			append(result.line, toFileAt: path)
		}
	}

	struct Result {
		var findingsByCheck = [Int: [String]]()
		/// How many comparisons each column check made, so a check that never fires shows.
		var comparedByCheck = [Int: Int]()
		var variantCount = 0
		var worstNode = ""
		var worstNodeVariantCount = 0
		var factsVariantCount = 0
		/// Pairs of places of one variant that check 10 compared after setting aside a read one of them asks, answered none.
		var check10ExemptedPairs = 0
		/// Check 10's findings by the fact a producer still owes that tells the two places apart (`owedFacts(answering:)`),
		/// a finding once per fact. Each fact's count goes to 0 when its producer lands; `unowed` stays 0.
		var check10OwedByFact = [String: Int]()
		/// Check 10's findings whose owed fact the node's `owedFacts` lacks, which `TypeFactsOwedFacts` must cover.
		var check10OwedUncovered = [String]()
		/// A proxy for rule 3's `@Sendable` gap: nodes two or more of whose reads by label are answered by a value at one
		/// place and by a `SendableLazilyInstantiated` at another. Wider than the gap: it does not ask whether the node is
		/// reached inside a `@Sendable` function, which the report does not say.
		var sendableGapProxyNodes = 0
		var line = ""
	}

	static func findings(of report: TypeFactsReport) -> Result {
		var result = Result()
		func add(_ check: Int, _ finding: String) {
			result.findingsByCheck[check, default: []].append(finding)
		}
		let places = report.places
		var childrenByPlace = [[Int]](repeating: [], count: places.count)
		for (index, place) in places.enumerated() {
			if let parent = place.parent {
				childrenByPlace[parent].append(index)
			}
		}
		func nodeDescription(_ node: Int?) -> String {
			node.map { "\($0) \(report.nodes[$0].description)" } ?? "none"
		}
		func path(of index: Int) -> [Int] {
			var path = [index]
			var current = index
			while let parent = places[current].parent {
				path.append(parent)
				current = parent
			}
			return path.reversed()
		}
		/// The nearest place above a closing place whose node's cycle key is its node's: the place whose builder function a
		/// closing place calls.
		func closedOnPlace(of index: Int) -> Int? {
			guard let node = places[index].node else { return nil }
			return path(of: index).dropLast().last { places[$0].node.map { report.nodes[$0].cycleKey } == report.nodes[node].cycleKey }
		}
		// Check 1.
		if let root = places.first, root.node != 0 {
			add(1, "the root place maps to \(nodeDescription(root.node))")
		}
		for place in places where place.node == nil {
			add(1, "place \(place.declaration) maps to no node")
		}
		// Check 2.
		for (index, place) in places.enumerated() {
			guard let node = place.node else { continue }
			let children = childrenByPlace[index]
			if place.closesCycle {
				if !children.isEmpty {
					add(2, "closing place \(place.declaration) builds \(children.count) children")
				}
				if closedOnPlace(of: index) == nil {
					// Inside a fill, a place can close on the path of the seam whose hole the fill fills, which is no place of
					// this tree (check 8).
					let isInsideFill = path(of: index).contains { places[$0].isFill }
					add(isInsideFill ? 8 : 2, "closing place \(place.declaration) repeats no node of its path")
				}
				continue
			}
			let edges = report.nodes[node].edges
			let instantiatedEdgeCount = report.nodes[node].instantiatedEdgeCount
			let instantiatedChildren = children.filter { !places[$0].isFill }.map { places[$0].node }
			// An alias or a hole is a leaf of the graph that no place builds.
			let expected = edges.prefix(instantiatedEdgeCount).filter { !report.nodes[$0].isLeaf }.map { Optional($0) }
			if instantiatedChildren != Array(expected) {
				add(2, "place \(place.declaration) builds \(instantiatedChildren.map(nodeDescription)) where its node has \(expected.map(nodeDescription))")
			}
			var fillEdges = edges.dropFirst(instantiatedEdgeCount)[...]
			for fillChild in children where places[fillChild].isFill {
				guard let fillNode = places[fillChild].node, let position = fillEdges.firstIndex(of: fillNode) else {
					add(2, "place \(place.declaration) builds fill \(places[fillChild].declaration) that is not among its node's fill edges, in order")
					break
				}
				fillEdges = fillEdges[(position + 1)...]
			}
		}
		// Check 3, and 9 for a place whose subtree closes a cycle: what the closing place passes the function it calls, a
		// cycle parameter, is read from above it, and no declared read stands for cycle parameters yet.
		var subtreeClosesCycle = places.map(\.closesCycle)
		for index in places.indices.reversed() {
			if subtreeClosesCycle[index], let parent = places[index].parent {
				subtreeClosesCycle[parent] = true
			}
		}
		var declaredReadsByNode = [Int: Set<String>]()
		for (index, place) in places.enumerated() {
			guard let node = place.node else { continue }
			let declared = declaredReadsByNode[node] ?? declaredReads(of: report.nodes[node])
			declaredReadsByNode[node] = declared
			let undeclared = Set(place.reads).subtracting(declared).sorted()
			if !undeclared.isEmpty {
				add(subtreeClosesCycle[index] ? 9 : 3, "place \(index) \(place.declaration) reads \(undeclared) from above, which its node does not declare")
			}
		}
		// Check 4.
		var variantByKey = [String: Int]()
		var variantCountByNode = [Int: Int]()
		let variantByPlace = places.map { place in
			let key = "\(place.node.map(String.init) ?? "none")|\(place.answeredReads.joined(separator: "|"))"
			if let variant = variantByKey[key] {
				return variant
			}
			variantByKey[key] = variantByKey.count
			if let node = place.node {
				variantCountByNode[node, default: 0] += 1
			}
			return variantByKey.count - 1
		}
		var firstPlaceByVariant = [Int: Int]()
		for (index, place) in places.enumerated() {
			let variant = variantByPlace[index]
			guard let first = firstPlaceByVariant[variant] else {
				firstPlaceByVariant[variant] = index
				continue
			}
			// A closing place calls the builder function of the place it closes on, so it builds what that place builds.
			func builtChildren(of place: Int) -> [Int] {
				guard places[place].closesCycle else { return childrenByPlace[place] }
				return closedOnPlace(of: place).map { childrenByPlace[$0] } ?? []
			}
			let builtByPlace = builtChildren(of: index)
			let builtByFirst = builtChildren(of: first)
			let children = builtByPlace.map { variantByPlace[$0] }
			let firstChildren = builtByFirst.map { variantByPlace[$0] }
			if children != firstChildren {
				let differing = zip(builtByPlace, builtByFirst).first { variantByPlace[$0] != variantByPlace[$1] }
				let detail = differing.map { child, firstChild in
					"; child \(places[child].declaration) answers \(Set(places[child].answeredReads).symmetricDifference(places[firstChild].answeredReads).sorted()) otherwise, cycle reads \(places[child].cycleReads.count) and \(places[firstChild].cycleReads.count)"
				} ?? "; \(children.count) children against \(firstChildren.count)"
				// A pair with a closing place is told apart (check 6): its children are those of the place it closes on, built
				// in that place's context, which only cycle parameters carry to the call.
				add(place.closesCycle || places[first].closesCycle ? 6 : 4, "places \(first) and \(index) of \(nodeDescription(place.node)) are answered alike but build otherwise\(detail)")
			}
		}
		result.variantCount = variantByKey.count
		if let worst = variantCountByNode.max(by: { $0.value < $1.value || $0.value == $1.value && $0.key > $1.key }) {
			result.worstNode = report.nodes[worst.key].description
			result.worstNodeVariantCount = worst.value
		}
		// Check 10.
		var factsVariantByPlace = [Int?](repeating: nil, count: places.count)
		if let root = places.first, root.node == 0, !report.variantNodes.isEmpty {
			factsVariantByPlace[0] = 0
		}
		for (index, children) in childrenByPlace.enumerated() {
			guard let variant = factsVariantByPlace[index], let node = places[index].node else { continue }
			let edges = report.nodes[node].edges
			var cursor = 0
			for child in children {
				guard let childNode = places[child].node, let edge = edges[cursor...].firstIndex(of: childNode) else { continue }
				factsVariantByPlace[child] = report.variantCalls[variant][edge]
				cursor = edge + 1
			}
		}
		var firstPlaceByFactsVariant = [Int: Int]()
		for (index, variant) in factsVariantByPlace.enumerated() {
			guard let variant else { continue }
			guard let first = firstPlaceByFactsVariant[variant] else {
				firstPlaceByFactsVariant[variant] = index
				continue
			}
			let declared = places[index].node.map { Set(report.nodes[$0].readsFromAbove) } ?? []
			// A read one place's construction asks and the other's does not (a seam leaf or fill asking its hole's own label)
			// is equal to the other's silence only where its answer is none; any other answer stays a finding.
			var answers = keyedAnswers(of: places[index], declared: declared)
			var firstAnswers = keyedAnswers(of: places[first], declared: declared)
			let askedByBoth = Set(answers.map(readOfAnswer)).intersection(firstAnswers.map(readOfAnswer))
			let isSilentNone = { (answer: String) in !askedByBoth.contains(readOfAnswer(answer)) && answer.hasSuffix(" = none") }
			let exempted = answers.filter(isSilentNone).count + firstAnswers.filter(isSilentNone).count
			answers = answers.filter { !isSilentNone($0) }
			firstAnswers = firstAnswers.filter { !isSilentNone($0) }
			if exempted > 0 {
				result.check10ExemptedPairs += 1
			}
			if answers != firstAnswers {
				let differing = answers.symmetricDifference(firstAnswers)
				let finding = "places \(first) and \(index) of \(nodeDescription(places[index].node)) share variant \(variant) but answer \(differing.sorted()) otherwise"
				add(10, finding)
				let owed = places[index].node.map { report.nodes[$0].owedFacts } ?? []
				for owedFact in owedFacts(answering: differing) {
					result.check10OwedByFact[owedFact, default: 0] += 1
					if !owed.contains(owedFact) {
						result.check10OwedUncovered.append("\(owedFact) owed but not in the node’s owed facts \(owed.sorted()): \(finding)")
					}
				}
			}
		}
		var answerFormsByNodeAndLabel = [Int: [String: Set<Character>]]()
		for place in places {
			guard let node = place.node else { continue }
			for answer in place.answeredReads {
				guard let form = bindingForm(of: answer) else { continue }
				let read = readOfAnswer(answer)
				let label = String(read.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" })
				answerFormsByNodeAndLabel[node, default: [:]][label, default: []].insert(form)
			}
		}
		for formsByLabel in answerFormsByNodeAndLabel.values where formsByLabel.values.count(where: { $0.isSuperset(of: ["v", "s"]) }) >= 2 {
			result.sendableGapProxyNodes += 1
		}
		result.factsVariantCount = report.variantNodes.count
		// Check 5.
		var nodesSeen = Set<Int>()
		for (index, place) in places.enumerated() {
			guard let node = place.node, nodesSeen.insert(node).inserted else { continue }
			let route = path(of: index).map { places[$0].node }
			let firstRoute = report.nodes[node].firstRoute.map { Optional($0) }
			if route != firstRoute {
				add(5, "the first place of \(nodeDescription(node)) has route \(route.map { $0.map(String.init) ?? "none" }) where the graph's first route is \(report.nodes[node].firstRoute)")
			}
		}
		// Check 7: the first route of a walk of the graph that, as the tree does, does not descend an edge to a node whose
		// cycle key a node on its path has, which a place there closes a cycle on.
		var closingAwareRoute = [Int: [Int]]()
		var stack: [(node: Int, edge: Int)] = [(0, 0)]
		var route = [0]
		var descended: Set = [0]
		closingAwareRoute[0] = [0]
		while let frame = stack.last {
			let edges = report.nodes[frame.node].edges
			guard frame.edge < edges.count else {
				stack.removeLast()
				route.removeLast()
				continue
			}
			stack[stack.count - 1].edge += 1
			let target = edges[frame.edge]
			let closes = route.contains { report.nodes[$0].cycleKey == report.nodes[target].cycleKey }
			if closingAwareRoute[target] == nil {
				closingAwareRoute[target] = route + [target]
			}
			// A node first reached where a place closes on it is descended where it is first reached otherwise.
			if !closes, descended.insert(target).inserted {
				stack.append((target, 0))
				route.append(target)
			}
		}
		var nodesSeenAgain = Set<Int>()
		for (index, place) in places.enumerated() {
			guard let node = place.node, nodesSeenAgain.insert(node).inserted else { continue }
			let placeRoute = path(of: index).compactMap { places[$0].node }
			if placeRoute != closingAwareRoute[node] {
				add(7, "the first place of \(nodeDescription(node)) has route \(placeRoute) where the walk that stops where a place closes a cycle first reaches it by \(closingAwareRoute[node] ?? [])")
			}
		}
		var compared = [Int: Int]()
		columnChecks(of: report, subtreeClosesCycle: subtreeClosesCycle, closedOnPlace: closedOnPlace, childrenByPlace: childrenByPlace, add: add, compared: &compared)
		result.comparedByCheck = compared
		let unwalkedNodes = report.nodes.count - nodesSeen.count - report.nodes.count(where: \.isLeaf)
		let twinNodes = report.nodes.count { $0.twin >= 0 }
		var line = "root=\(report.root) mock=\(report.forMockGeneration) nodes=\(report.nodes.count) unwalkedNodes=\(unwalkedNodes) places=\(places.count) variants=\(result.variantCount) factsVariants=\(result.factsVariantCount) worst=\(result.worstNodeVariantCount) twins=\(twinNodes)"
		for check in 1...lastCheck {
			line.append(" check\(check)=\(result.findingsByCheck[check]?.count ?? 0)")
		}
		line.append(" check10Exempted=\(result.check10ExemptedPairs) sendableGapProxy=\(result.sendableGapProxyNodes)")
		line.append(" check10Owed=\(result.check10OwedByFact.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")) check10OwedUncovered=\(result.check10OwedUncovered.count) test=\(Test.current?.name ?? "")")
		for check in 11...lastCheck {
			line.append(" compared\(check)=\(result.comparedByCheck[check] ?? 0)")
		}
		for check in 1...lastCheck {
			if let first = result.findingsByCheck[check]?.first {
				line.append(" first\(check)=«\(first.replacingOccurrences(of: "\n", with: " "))»")
			}
		}
		result.line = line + "\n"
		return result
	}

	/// How an answered read's nearest bindings hold the label, for the `@Sendable` gap proxy: `s` for a
	/// `SendableLazilyInstantiated`, `l` for a `LazilyInstantiated`, `v` for a value, `nil` where nothing binds it.
	private static func bindingForm(of answer: String) -> Character? {
		guard let start = answer.range(of: " = bindings [") else { return nil }
		let bindings = answer[start.upperBound...].prefix { $0 != "]" }
		guard !bindings.isEmpty else { return nil }
		if bindings.contains("SendableLazilyInstantiated<") {
			return "s"
		} else if bindings.contains("LazilyInstantiated<") {
			return "l"
		} else {
			return "v"
		}
	}

	/// The facts a producer still owes that tell apart the answers two places of one variant give, the symmetric
	/// difference of their keyed answers: per read, `mockRootPin` for a mock read; for two answers of one read, the first
	/// field that differs names it (`fillBeingBuilt` for being built at one only, `mockRootRecord` for what is pinned or
	/// read above, `mockRootBinding` for what the mock root binds, `madeAgain` for a builder's bindings); `unowed`
	/// otherwise, a read one place asks among them.
	static func owedFacts(answering differing: Set<String>) -> Set<String> {
		var answersByRead = [String: [String]]()
		for answer in differing {
			answersByRead[readOfAnswer(answer), default: []].append(answer)
		}
		var owed = Set<String>()
		for (read, answers) in answersByRead {
			if read.hasPrefix("mock(") {
				owed.insert("mockRootPin")
			} else if answers.count == 2 {
				let (first, second) = (answers[0], answers[1])
				let differs = { (field: String) in self.field(field, of: first) != self.field(field, of: second) }
				if (field("being built", of: first) == "[]") != (field("being built", of: second) == "[]") {
					owed.insert("fillBeingBuilt")
				} else if differs("pinned above") || differs("read above") {
					owed.insert("mockRootRecord")
				} else if differs("bound by mock root") {
					owed.insert("mockRootBinding")
				} else if differs("bindings"), first.contains("Instantiator<") {
					owed.insert("madeAgain")
				} else {
					owed.insert("unowed")
				}
			} else {
				owed.insert("unowed")
			}
		}
		return owed
	}

	/// The text an answer gives after one of its fields' names, up to the next field: `[]` of `being built []`.
	private static func field(_ name: String, of answer: String) -> Substring {
		let names = [" = bindings ", " being built ", " passed ", " pinned above ", " read above ", " bound by mock root "]
		guard let start = answer.range(of: name == "bindings" ? " = bindings " : " \(name) ") else { return "" }
		let rest = answer[start.upperBound...]
		let end = names.compactMap { rest.range(of: $0)?.lowerBound }.min() ?? rest.endIndex
		return rest[..<end]
	}

	/// The read an answered read names, `value(x)` of `value(x) = none`.
	private static func readOfAnswer(_ answer: String) -> String {
		String(answer.prefix { $0 != " " })
	}

	/// A place's answered reads as a variant's key compares them: a read only if available left out (rule 1), given the
	/// node's declared reads as the report spells them, and what is
	/// still being built left out of a read whose declaration is a wrapper (rule 2), which the text shows by its type.
	private static func keyedAnswers(of place: TypeFactsReport.Place, declared: Set<String>) -> Set<String> {
		var answers = Set<String>()
		for answer in place.answeredReads where !answer.hasPrefix("optional(") {
			// A nearest declaration that only receives only if available read (`optionalValue`) keys by rule 1 too.
			let read = String(answer.prefix { $0 != " " })
			if read.hasPrefix("value("), !declared.contains(read), declared.contains("optionalValue(" + read.dropFirst("value(".count)) {
				continue
			}
			let isWrapper = answer.contains("Instantiator<") || answer.contains("LazilyInstantiated<")
			answers.insert(isWrapper ? answer.replacingOccurrences(of: #" being built \[[^\]]*\]"#, with: "", options: .regularExpression) : answer)
		}
		return answers
	}

	/// A node's declared reads as a logged read is spelled: an `optionalValue` read is logged as `value`'s is.
	private static func declaredReads(of node: TypeFactsReport.Node) -> Set<String> {
		var reads = Set(node.readsFromAbove)
		for read in node.readsFromAbove where read.hasPrefix("optionalValue(") {
			reads.insert("value(" + read.dropFirst("optionalValue(".count))
		}
		return reads
	}

	static let lastCheck = 32

	/// Checks 11 to 31: each column of the graph against what the generator decided at each place.
	///
	/// 11. The children: as many as the node's listed edges, each of its edge's label.
	/// 12. The order the place builds its children in is the edges' positions; 13 where the place's subtree closes a cycle,
	///     the place is inside a fill or passes one beneath it, whose receives the node's union does not see alike, or the
	///     place is a mock's root, whose pins order it too.
	/// 14. Each child's loop of builders is the edge's loop; 15 as 13.
	/// 16. What the place receives, required, only if available, through an alias, is the node's union; 17 as 13, or in a
	///     mock, where a receive a required one pins is passed `nil`, a fill beneath only where each receive it adds is of a
	///     label a fill reads.
	/// 18. The names declared `@escaping` beneath are the node's; 19 as 13.
	/// 20. A place built in a `Sendable` wrapper builds in a `@Sendable` function; 21 a function made `@Sendable` only by a
	///     cycle closed from inside one, which the edge does not open.
	/// 22. Two nodes share a cycle identity exactly when they share a cycle key.
	/// 23. A closing place shares its node's cycle identity with the place it closes on, and closes on its own node by a
	///     call edge; 24 on another node, its twin.
	/// 25. The children's bindings follow the order the place builds them, each at its edge's count of bindings before.
	/// 26. Each binding is declared in the node's module.
	/// 27. A place's parent's node is among its node's parents.
	/// 28. A place passes at most its node's fills, each along a fill edge.
	/// 29. Every type the place's subtree builds is among its node's types beneath.
	/// 30. A node holds a hole beneath exactly when a hole is reachable from it along edges that are not fills.
	/// 31. How the place is constructed: a seam call, a call of another module's public mock, a type built with its
	///     hand-written mock.
	/// 32. Oracle B: each member a variant makes again is called as the variant that each body calling the maker calls for
	///     that member at its own edge, and the maker has such a body. It reads the variants alone, so it runs on every tree
	///     with a loop of builders, refused or not.
	private static func columnChecks(
		of report: TypeFactsReport,
		subtreeClosesCycle: [Bool],
		closedOnPlace: (Int) -> Int?,
		childrenByPlace: [[Int]],
		add: (Int, String) -> Void,
		compared: inout [Int: Int],
	) {
		let places = report.places
		let nodes = report.nodes
		var isInsideFill = places.map(\.isFill)
		for index in places.indices {
			if let parent = places[index].parent, isInsideFill[parent] {
				isInsideFill[index] = true
			}
		}
		// The fills a place's subtree passes, whose reads from the caller's scope its generator receives, and so orders its
		// children by: the node's union leaves a fill's reads out until the receives of a fill's fields are a column.
		var fillNodesBeneath = places.map { _ in Set<Int>() }
		for index in places.indices.reversed() {
			for child in childrenByPlace[index] {
				fillNodesBeneath[index].formUnion(fillNodesBeneath[child])
				if places[child].isFill, let fillNode = places[child].node {
					fillNodesBeneath[index].insert(fillNode)
				}
			}
		}
		func count(_ check: Int) {
			compared[check, default: 0] += 1
		}
		for (index, place) in places.enumerated() {
			guard let node = place.node, let generator = place.generator else { continue }
			let facts = nodes[node]
			let fillNodes = fillNodesBeneath[index].sorted()
			let explained = subtreeClosesCycle[index] || isInsideFill[index] || !fillNodes.isEmpty
			// Check 31. A fill's construction is the fill, whatever builds its fulfiller.
			if facts.construction != "fill" {
				count(31)
			}
			if facts.construction != "fill", generator.callsSeam != (facts.construction == "seamCall") || generator.callsPublicMock != (facts.construction == "publicMockCall") || generator.constructsWithHandWrittenMock && facts.construction != "handWrittenMock" {
				add(31, "place \(index) \(place.declaration) is \(facts.construction) where its generator calls a seam \(generator.callsSeam), a public mock \(generator.callsPublicMock), a hand-written mock \(generator.constructsWithHandWrittenMock)")
			}
			// Check 27.
			if let parent = place.parent, let parentNode = places[parent].node {
				count(27)
				if !facts.parents.contains(parentNode) {
					add(27, "place \(index) \(place.declaration)'s parent's node \(parentNode) is not among its node's parents \(facts.parents)")
				}
			}
			// Check 26.
			count(26)
			if facts.bindingModules.contains(where: { $0 != facts.module }) {
				add(26, "node \(node) \(facts.description) declares bindings in modules \(facts.bindingModules) beside its own \(facts.module)")
			}
			// Check 29.
			if !place.closesCycle {
				count(29)
				var stack = [index]
				var built = Set<String>()
				while let current = stack.popLast() {
					built.insert(places[current].builtType)
					// A fill's types are the call's fill edges', which a node's types beneath leave out.
					stack.append(contentsOf: childrenByPlace[current].filter { !places[$0].isFill })
				}
				let missing = built.subtracting(facts.typesBeneath).sorted()
				if !missing.isEmpty {
					add(29, "place \(index) \(place.declaration)'s subtree builds \(missing) that its node's types beneath lack")
				}
			}
			// Check 28.
			let fillChildren = childrenByPlace[index].filter { places[$0].isFill }
			if !fillChildren.isEmpty {
				count(28)
				let fillTargets = zip(facts.edges, facts.edgeFacts).filter(\.1.isFill).map(\.0)
				if fillChildren.count > facts.fillCount || fillChildren.contains(where: { places[$0].node.map { !fillTargets.contains($0) } ?? true }) {
					add(28, "place \(index) \(place.declaration) passes \(fillChildren.count) fills where its node passes \(facts.fillCount)")
				}
			}
			// Check 23 and 24.
			if place.closesCycle, let closedOn = closedOnPlace(index), let closedOnNode = places[closedOn].node {
				count(23)
				if facts.cycleKeyID != nodes[closedOnNode].cycleKeyID {
					add(23, "closing place \(index) \(place.declaration) has cycle identity \(facts.cycleKeyID) where the place it closes on has \(nodes[closedOnNode].cycleKeyID)")
				} else if closedOnNode == node {
					if let parent = place.parent, let parentNode = places[parent].node, let edge = nodes[parentNode].edges.firstIndex(of: node), !nodes[parentNode].edgeFacts[edge].isCallEdge {
						add(23, "closing place \(index) \(place.declaration) closes on its own node by an edge that is no call edge")
					}
				} else {
					count(24)
					if facts.twin < 0 {
						add(24, "closing place \(index) \(place.declaration) closes on node \(closedOnNode), another node of its identity, where its node has no twin")
					}
				}
			}
			guard !place.closesCycle else { continue }
			// Check 11.
			let childEdges = Array(zip(facts.edges, facts.edgeFacts).filter { !$0.1.isFill }.enumerated())
			count(11)
			if generator.childCount != childEdges.count || generator.childLabels != childEdges.map({ nodes[$0.element.0].label }) {
				add(11, "place \(index) \(place.declaration) builds children \(generator.childLabels) where its node lists \(childEdges.map { nodes[$0.element.0].label })")
				continue
			}
			// Check 12 and 13.
			let expectedOrder = childEdges.sorted { $0.element.1.buildPosition < $1.element.1.buildPosition }.map(\.offset)
			// A mock root orders its children by what its pins pass `nil` too (`MockReceivesPassedNil`), which the node's
			// receives leave to the variants.
			let isExplainedOrder = explained || report.forMockGeneration && place.parent == nil
			count(isExplainedOrder ? 13 : 12)
			// A child that lists a property a sibling before it lists is never built, and follows those built.
			if Array(expectedOrder.prefix(generator.orderedIndices.count)) != generator.orderedIndices {
				add(isExplainedOrder ? 13 : 12, "place \(index) \(place.declaration) builds its children \(generator.childLabels) in order \(generator.orderedIndices) where its node's positions give \(expectedOrder)")
			}
			// Check 14 and 15.
			let expectedLoops = childEdges.map(\.element.1.loop)
			let generatorLoops = generator.loopByChildIndex.map { $0 < 0 ? -1 : childEdges[$0].element.1.buildPosition }
			count(explained ? 15 : 14)
			if expectedLoops != generatorLoops {
				add(explained ? 15 : 14, "place \(index) \(place.declaration) has loops \(generatorLoops) where its node's edges have \(expectedLoops)")
			}
			// Check 25.
			count(25)
			let childBindings = generator.orderedIndices.map { child -> String in
				let bindingIndex = childEdges[child].element.1.bindingsBefore
				return bindingIndex < facts.bindings.count ? String(facts.bindings[bindingIndex].prefix { $0 != ":" }) : ""
			}
			let orderedLabels = generator.orderedIndices.map { generator.childLabels[$0] }
			if childBindings != orderedLabels {
				add(25, "place \(index) \(place.declaration) binds its children \(orderedLabels) where its node's bindings give \(childBindings)")
			}
			// Check 16 and 17.
			// A node on a cycle receives what its whole cycle receives, a fixed point no one place of it need reach.
			let isExplainedReceive = explained || report.forMockGeneration || facts.isOnCycle
			count(isExplainedReceive ? 17 : 16)
			let receiveDifferences = [
				("received", generator.received, facts.received),
				("required", generator.required, facts.required),
				("only if available", generator.onlyIfAvailableUnwrapped, facts.onlyIfAvailableUnwrapped),
				("through an alias", generator.requiredAliasFulfilling, facts.requiredAliasFulfilling),
			].filter { spellingsOfOneType($0.1) != spellingsOfOneType($0.2) }
			if !receiveDifferences.isEmpty {
				// Explained only where the node's union, a fixed point over every build of the type, holds what the place's
				// generator receives: a place on a cycle, beneath one that closes a cycle, or built for a mock sees less,
				// never more.
				// A label one receiver requires is required (`collectReceivedProperties`), so a place that receives it only if
				// available where the union requires it sees less too.
				// A fill beneath adds what its tree reads, in any form its tree reads it: the caller hands it a wrapper of a
				// value it declares, or a value whose wrapper the fill reads.
				let fillReads = Set(fillNodes.flatMap { nodes[$0].received + nodes[$0].required + nodes[$0].onlyIfAvailableUnwrapped + nodes[$0].requiredAliasFulfilling })
				let fillLabels = Set(fillReads.map { String($0.prefix { $0 != ":" }) })
				let requiredUnwrapped = spellingsOfOneType(facts.required).map { $0.hasSuffix("?") ? String($0.dropLast()) : $0 }
				let isSubset = receiveDifferences.allSatisfy { name, generatorSet, nodeSet in
					let nodeHolds = name == "only if available" ? Set(spellingsOfOneType(nodeSet)).union(requiredUnwrapped) : Set(spellingsOfOneType(nodeSet))
					return Set(spellingsOfOneType(generatorSet)).subtracting(nodeHolds).allSatisfy { fillLabels.contains(String($0.prefix { $0 != ":" })) }
				}
				let differences = receiveDifferences.map { "\($0.0) \($0.1) where its node's union is \($0.2)" }.joined(separator: ", ")
				add(isExplainedReceive && isSubset ? 17 : 16, "place \(index) \(place.declaration) receives \(differences)")
			}
			// Check 18 and 19.
			count(explained ? 19 : 18)
			if generator.typesDeclaredEscaping != facts.typesDeclaredEscaping {
				add(explained ? 19 : 18, "place \(index) \(place.declaration) declares \(generator.typesDeclaredEscaping) escaping where its node's union is \(facts.typesDeclaredEscaping)")
			}
			// Check 20 and 21.
			if let parent = place.parent, let parentNode = places[parent].node, let edge = nodes[parentNode].edges.firstIndex(of: node) {
				let opensSendable = ["sendableInstantiatorBuilder", "sendableLazyWrapper"].contains(nodes[parentNode].edgeFacts[edge].opens)
				count(20)
				if opensSendable, !generator.buildsInSendableFunction {
					add(20, "place \(index) \(place.declaration)'s edge opens a `@Sendable` function its generator does not build in")
				} else if !opensSendable, generator.buildsInSendableFunction {
					add(subtreeClosesCycle[index] ? 21 : 20, "place \(index) \(place.declaration) builds in a `@Sendable` function its edge does not open")
				}
			}
		}
		// Check 22. Keys compare by their bytes: Swift reads two encodings of one label as two names, which `String` equates.
		var identityByKey = [[UInt8]: Int]()
		var keyByIdentity = [Int: [UInt8]]()
		for (index, node) in nodes.enumerated() where !node.isLeaf {
			count(22)
			let key = Array(node.cycleKey.utf8)
			if let identity = identityByKey[key], identity != node.cycleKeyID {
				add(22, "node \(index) \(node.description) has identity \(node.cycleKeyID) where another of key \(node.cycleKey) has \(identity)")
			} else if let otherKey = keyByIdentity[node.cycleKeyID], otherKey != key {
				add(22, "node \(index) \(node.description) shares identity \(node.cycleKeyID) with key \(String(decoding: otherKey, as: UTF8.self))")
			}
			identityByKey[key] = node.cycleKeyID
			keyByIdentity[node.cycleKeyID] = key
		}
		// Check 30.
		var holdsHole = nodes.map { $0.kind == "hole" }
		var changed = true
		while changed {
			changed = false
			for index in nodes.indices.reversed() where !holdsHole[index] {
				for (target, edge) in zip(nodes[index].edges, nodes[index].edgeFacts) where !edge.isFill && holdsHole[target] {
					holdsHole[index] = true
					changed = true
				}
			}
		}
		for (index, node) in nodes.enumerated() {
			count(30)
			if node.holdsHoleBeneath != holdsHole[index] {
				add(30, "node \(index) \(node.description) holds a hole beneath \(node.holdsHoleBeneath) where its edges reach one \(holdsHole[index])")
			}
		}
		// Check 32.
		guard report.variantMadeAgainCalls.contains(where: { !$0.isEmpty }) else { return }
		var edgeCallersByVariant = [[Int]](repeating: [], count: report.variantCalls.count)
		for (caller, calls) in report.variantCalls.enumerated() {
			for callee in calls {
				edgeCallersByVariant[callee].append(caller)
			}
		}
		for (maker, calls) in report.variantMadeAgainCalls.enumerated() {
			let makerNode = nodes[report.variantNodes[maker]]
			for (member, callee) in zip(makerNode.madeAgain, calls) {
				count(32)
				let parents = edgeCallersByVariant[maker]
				if parents.isEmpty {
					add(32, "v\(maker) of \(makerNode.description) makes again v\(callee) and no body calls it at an edge")
				}
				for parent in parents {
					let parentNode = nodes[report.variantNodes[parent]]
					for (edge, target) in parentNode.edges.enumerated() where target == member && report.variantCalls[parent][edge] != callee {
						add(32, "v\(maker) of \(makerNode.description) makes again v\(callee) of node \(member), where its parent v\(parent) calls v\(report.variantCalls[parent][edge])")
					}
				}
			}
		}
	}

	/// The properties as one type: the columns intern a property's first spelling, while the generator's sets keep the most
	/// explicit (`insertKeepingMostExplicitSpelling`), and `TypeDescription`'s `==` reads `any P` as `P` and
	/// `throws(any Error)` as `throws`.
	private static func spellingsOfOneType(_ properties: [String]) -> [String] {
		properties.map { property in
			property
				.replacingOccurrences(of: #"(?<![A-Za-z0-9_])any "#, with: "", options: .regularExpression)
				.replacingOccurrences(of: "throws(Error)", with: "throws")
		}.sorted()
	}

	private static func append(_ line: String, toFileAt path: String) {
		let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard descriptor >= 0 else { return }
		defer { close(descriptor) }
		let bytes = Array(line.utf8)
		_ = bytes.withUnsafeBufferPointer { write(descriptor, $0.baseAddress, $0.count) }
	}
}
