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
		}
		if let path = environment["SAFEDI_TYPE_FACTS_LOG"], !path.isEmpty {
			append(result.line, toFileAt: path)
		}
	}

	struct Result {
		var findingsByCheck = [Int: [String]]()
		var variantCount = 0
		var worstNode = ""
		var worstNodeVariantCount = 0
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
			let expected = edges.prefix(instantiatedEdgeCount).map { Optional($0) }
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
			let declared = declaredReadsByNode[node] ?? Set(report.nodes[node].readsFromAbove)
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
		let unwalkedNodes = report.nodes.count - nodesSeen.count
		var line = "root=\(report.root) mock=\(report.forMockGeneration) nodes=\(report.nodes.count) unwalkedNodes=\(unwalkedNodes) places=\(places.count) variants=\(result.variantCount) worst=\(result.worstNodeVariantCount)"
		for check in 1...9 {
			line.append(" check\(check)=\(result.findingsByCheck[check]?.count ?? 0)")
		}
		for check in 1...9 {
			if let first = result.findingsByCheck[check]?.first {
				line.append(" first\(check)=«\(first.replacingOccurrences(of: "\n", with: " "))»")
			}
		}
		result.line = line + "\n"
		return result
	}

	private static func append(_ line: String, toFileAt path: String) {
		let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
		guard descriptor >= 0 else { return }
		defer { close(descriptor) }
		let bytes = Array(line.utf8)
		_ = bytes.withUnsafeBufferPointer { write(descriptor, $0.baseAddress, $0.count) }
	}
}
