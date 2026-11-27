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

/// What a test observes of node records (`NodeRecords`): for each production root, of a module with seams or without,
/// whether its world was refused and why, whether its code was laid out from the records, and every way the records
/// differ from the records the tree's places made: at every place, the record of the place's node must equal the
/// place's own.
public enum NodeRecordsObservation {
	/// Whether a root whose world node records accept is laid out from them, rather than from its tree's places, where
	/// `observer` is set. Off unless a test turns it on; the tree's places are laid out where the engine cannot lay the
	/// records out. The tree is still planned and laid out beside the records, for the comparison, so the engine lays each
	/// such root out twice: a test that counts the engine's views sees each count twice, and the mode must drop the tree's
	/// plan before it is turned on for every run, or generate time doubles.
	@TaskLocal public static var laysOutRoots = false

	/// Whether `generate` lays out a root whose world node records accept from them and builds no tree for it
	/// (`DependencyTreeGenerator.nodeRecordsLayout`). Off until the switch to node records lands: only a test turns it on.
	@TaskLocal public static var buildsNoTreeForAcceptedRoots = false

	/// The nodes a test claims as a kind would (`NodeRecords.claim(of:in:)`), by their concrete type's name, each
	/// with the raw values of the refusals the claim discharges. Only a test sets it.
	@TaskLocal public static var claimsForTesting = [String: [String]]()

	/// Whether a mock root whose world node records accept has the statements that build its nodes laid out from them,
	/// rather than written by the mock's walk, where `observer` is set. Off unless a test turns it on: the two write other
	/// text for a node beneath a function, which is handed its override where the walk's captures the root's.
	@TaskLocal public static var laysOutMockRoots = false

	/// Handed each mocked type and the root of its mock root's world as the mock root is built, where a test observes node records
	/// (`DependencyTreeGenerator.createMockRootScopeGenerator`). A task local rather than a parameter: an optional closure
	/// threaded through the mock roots' construction raised the peak memory of a run that sets none by a fifth on Linux.
	@TaskLocal static var recordsMockWorldRoot: (@Sendable (TypeDescription, ConstructionScope) -> Void)?

	/// Handed each root's report, where set. Only a test sets it.
	@TaskLocal public static var observer: (@Sendable (NodeRecordsReport) -> Void)?

	/// Handed the body of the root a tree's places build, beside the node records made for the same root, where a root's
	/// plan is observed: set by the generator around one root's plan.
	@TaskLocal static var rootBodyObserver: (@Sendable (_ rootBody: [GeneratedCode]) -> Void)?

	/// The ways `nodeRecordsBody`, the root's body node records make, differs from `treeBody`, the body the tree's places
	/// make: a line per difference, each naming the place by the labels on its path, and how many places the tree's body
	/// holds, each place a shared plan reaches counted once per path.
	static func differences(between treeBody: [GeneratedCode], and nodeRecordsBody: [GeneratedCode]) -> (differences: [String], treePlaceCount: Int) {
		var differences = [String]()
		var treePlaceCount = 0
		var pending = [(tree: treeBody, nodeRecords: nodeRecordsBody, path: "root")]
		while let (treeCodes, nodeRecordsCodes, path) = pending.popLast() {
			// A hole's place, and a place on the route to one, is a sequence of places: the payloads bound before it, each
			// a place written as text, then the place itself. Each is compared as a statement of its own.
			let tree = treeCodes.flatMap(statements(of:))
			let nodeRecords = nodeRecordsCodes.flatMap(statements(of:))
			guard tree.count == nodeRecords.count else {
				differences.append("\(path): the tree builds \(tree.count) statements, node records \(nodeRecords.count)")
				continue
			}
			for (treeCode, nodeRecordsCode) in zip(tree, nodeRecords) {
				let (treeIndentation, treeInner) = unindented(treeCode)
				let (nodeRecordsIndentation, nodeRecordsInner) = unindented(nodeRecordsCode)
				guard case let .place(nodeRecordsPlan) = nodeRecordsInner.node, let nodeRecordsRecord = nodeRecordsPlan.record else {
					differences.append("\(path): node records made a statement that is no place")
					continue
				}
				let label = switch nodeRecordsRecord {
				case let .built(record): record.property.label
				case let .closer(record): record.property.label
				case let .alias(record): record.property.label
				}
				let placePath = "\(path).\(label)"
				guard case let .place(treePlan) = treeInner.node, let treeRecord = treePlan.record else {
					differences.append("\(placePath): the tree writes no place’s record")
					continue
				}
				treePlaceCount += 1
				if treeIndentation != nodeRecordsIndentation {
					differences.append("\(placePath): indented \(treeIndentation.count) in the tree, \(nodeRecordsIndentation.count) by node records")
				}
				switch (treeRecord, nodeRecordsRecord) {
				case let (.built(treeBuilt), .built(nodeRecordsBuilt)):
					differences += fieldDifferences(between: treeBuilt, and: nodeRecordsBuilt).map { "\(placePath): \($0)" }
					pending.append((tree: treeBuilt.children, nodeRecords: nodeRecordsBuilt.children, path: placePath))
				case let (.alias(treeAlias), .alias(nodeRecordsAlias)):
					differences += fieldDifferences(between: treeAlias, and: nodeRecordsAlias).map { "\(placePath): \($0)" }
				case let (.closer(treeCloser), .closer(nodeRecordsCloser)):
					differences += fieldDifferences(between: treeCloser, and: nodeRecordsCloser).map { "\(placePath): \($0)" }
				case (.built, _), (.alias, _), (.closer, _):
					differences.append("\(placePath): the tree writes another kind of place than node records")
				}
			}
		}
		return (differences, treePlaceCount)
	}

	private static func unindented(_ code: GeneratedCode) -> (indentation: String, code: GeneratedCode) {
		var indentation = ""
		var inner = code
		while case let .indented(wrapped, by) = inner.node {
			indentation += by
			inner = wrapped
		}
		return (indentation, inner)
	}

	/// The fields of `nodeRecords`, a place that closes a cycle, that differ from `tree`'s.
	private static func fieldDifferences(between tree: ClosingPlaceRecord, and nodeRecords: ClosingPlaceRecord) -> [String] {
		var differences = [String]()
		func compare<Value: Equatable>(_ name: String, _ treeValue: Value, _ nodeRecordsValue: Value) {
			guard treeValue != nodeRecordsValue else { return }
			differences.append("\(name) is \(treeValue) in the tree, \(nodeRecordsValue) by node records")
		}
		compare("property", tree.property, nodeRecords.property)
		compare("isErased", tree.isErased, nodeRecords.isErased)
		compare("isExtension", tree.isExtension, nodeRecords.isExtension)
		compare("closedOnFunctionName", tree.closedOnFunctionName, nodeRecords.closedOnFunctionName)
		compare("forwardedProperties", tree.forwardedProperties, nodeRecords.forwardedProperties)
		compare("cycleArguments", tree.cycleArguments, nodeRecords.cycleArguments)
		compare("passedArguments", tree.passedArguments, nodeRecords.passedArguments)
		compare("rebindsLoopMember", tree.rebindsLoopMember, nodeRecords.rebindsLoopMember)
		return differences
	}

	/// `code`'s statements: each piece of a sequence, indented as the sequence is, or `code` where it is no sequence.
	private static func statements(of code: GeneratedCode) -> [GeneratedCode] {
		let (indentation, inner) = unindented(code)
		guard case let .sequence(pieces) = inner.node else { return [code] }
		return pieces.flatMap { statements(of: .indented($0, by: indentation)) }
	}

	/// The fields of `nodeRecords`, a rename or a hole's place, that differ from `tree`'s.
	private static func fieldDifferences(between tree: AliasPlaceRecord, and nodeRecords: AliasPlaceRecord) -> [String] {
		var differences = [String]()
		func compare<Value: Equatable>(_ name: String, _ treeValue: Value, _ nodeRecordsValue: Value) {
			guard treeValue != nodeRecordsValue else { return }
			differences.append("\(name) is \(treeValue) in the tree, \(nodeRecordsValue) by node records")
		}
		compare("property", tree.property, nodeRecords.property)
		compare("fulfillingProperty", tree.fulfillingProperty, nodeRecords.fulfillingProperty)
		// Node records leave a call's text to the engine, which spells it from the call (`InPlaceCall`).
		if nodeRecords.call == nil {
			compare("text", tree.text, nodeRecords.text)
		}
		compare("reads", tree.reads, nodeRecords.reads)
		compare("otherBindings", tree.otherBindings, nodeRecords.otherBindings)
		compare("calledFunctionNames", tree.calledFunctionNames, nodeRecords.calledFunctionNames)
		compare("declaredFunctionNames", tree.declaredFunctionNames, nodeRecords.declaredFunctionNames)
		compare("calledRootFunctionNames", tree.calledRootFunctionNames, nodeRecords.calledRootFunctionNames)
		compare("holdsCall", tree.call != nil, nodeRecords.call != nil)
		if let treeCall = tree.call, let nodeRecordsCall = nodeRecords.call {
			differences += fieldDifferences(between: treeCall.record, and: nodeRecordsCall.record).map { "call: \($0)" }
			compare("call: argumentValues", treeCall.record.argumentValues, nodeRecordsCall.record.argumentValues)
			compare("call: statements before the leading statement", treeCall.statementsBeforeLeadingStatement.count, nodeRecordsCall.statementsBeforeLeadingStatement.count)
			compare("call: statements after the leading statement", treeCall.statementsAfterLeadingStatement.count, nodeRecordsCall.statementsAfterLeadingStatement.count)
		}
		return differences
	}

	/// The fields of `nodeRecords` that differ from `tree`'s, children aside.
	private static func fieldDifferences(between tree: BuiltPlaceRecord, and nodeRecords: BuiltPlaceRecord) -> [String] {
		var differences = [String]()
		func compare<Value: Equatable>(_ name: String, _ treeValue: Value, _ nodeRecordsValue: Value) {
			guard treeValue != nodeRecordsValue else { return }
			differences.append("\(name) is \(treeValue) in the tree, \(nodeRecordsValue) by node records")
		}
		compare("property", tree.property, nodeRecords.property)
		compare("isErased", tree.isErased, nodeRecords.isErased)
		compare("concreteType", tree.concreteType, nodeRecords.concreteType)
		compare("isExtension", tree.isExtension, nodeRecords.isExtension)
		compare("target", tree.target, nodeRecords.target)
		compare("arguments", tree.arguments, nodeRecords.arguments)
		compare("forwardedProperties", tree.forwardedProperties, nodeRecords.forwardedProperties)
		compare("cycleParameters", tree.cycleParameters, nodeRecords.cycleParameters)
		compare("callCycleArguments", tree.callCycleArguments, nodeRecords.callCycleArguments)
		compare("functionName", tree.functionName, nodeRecords.functionName)
		compare("isSendable", tree.isSendable, nodeRecords.isSendable)
		compare("typesDeclaredEscaping", tree.typesDeclaredEscaping, nodeRecords.typesDeclaredEscaping)
		compare("lineEnd", tree.lineEnd, nodeRecords.lineEnd)
		compare("hasFunction", tree.hasFunction, nodeRecords.hasFunction)
		compare("holdsSharingFields", tree.sharingFields != nil, nodeRecords.sharingFields != nil)
		compare("leadingStatement", tree.leadingStatement, nodeRecords.leadingStatement)
		compare("closureArguments", tree.closureArguments, nodeRecords.closureArguments)
		return differences
	}
}

/// One production root's node records, beside its tree's places (`NodeRecordsObservation`).
public struct NodeRecordsReport: Sendable {
	/// The root's concrete type.
	public let root: String
	/// Why node records refused the root's world (`NodeRecordRefusal`), or `nil` where they made its records.
	public let refusal: String?
	/// Every refusal the root's world holds, at any node, each once (`NodeRecords.refusals(in:seamTree:declaredTypeNames:)`): empty where node records
	/// made its records.
	public let everyRefusal: [String]
	/// Whether the root's code was laid out from node records.
	public let isLaidOutFromNodeRecords: Bool
	/// Each way the records differ from the records the tree's places made, where both were made.
	public let differences: [String]
	/// How many records node records made: one per variant but the root's.
	public let recordCount: Int
	/// How many places the tree's body holds, counted per path, where node records made the root's records.
	public let treePlaceCount: Int
	/// What made the run build the root's tree (`TreeForcer`); empty where its code was laid out from node records alone,
	/// and the tree was built only for the test to compare.
	public let treeForcers: [TreeForcer]
	/// Whether the root is a mock's: its records are compared with no tree's, so `differences` is empty, and a test
	/// compares the code laid out from them, or the values that code builds, with the mock's walk's.
	public var isMockRoot = false
}
