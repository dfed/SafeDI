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

extension SeamPlacesDrafts {
	/// How the fields of the drafted levels outside fills differ from those of the stored levels of `places` with the same
	/// type and next property: the next property's position and loop, the `@Sendable` function the scope is built in, the
	/// path segment from the enclosing level, the entry a closing call closes on, and the keys of the enclosing levels.
	/// Each level is spelled as a set of `field=value` entries, and a stored level is alike where some drafted level of its
	/// key spells the same. The first line is a count report. Test only, until the assembler builds the levels.
	func levelFieldDifferences(from places: SeamSignature.Places) -> [String] {
		func builtType(of variant: VariantID) -> String {
			world.graph.nodes[Int(world.declaration(of: variant))].scope.instantiable.concreteInstantiable.asSource
		}
		func target(of level: SeamPlacesLevelID) -> Int {
			let targets = world.edges(from: world.declaration(of: level.variant))
			return Int(targets[targets.startIndex + Int(level.edge)])
		}
		func key(of level: SeamPlacesLevelID) -> String {
			let next = world.graph.nodes[target(of: level)]
			return "\(builtType(of: level.variant)) before \(next.key.isFill ? "fill" : next.property?.label ?? "fill")"
		}
		func spelled(opens function: TypeFactsFunctionOpened, into level: SeamPlacesLevelID) -> String {
			let callee = target(of: level)
			let builtType = world.typeTable[Int(world.builtTypes[callee])].asSource
			let label = world.graph.nodes[callee].property?.label ?? "fill"
			switch function {
			case .none, .instantiatorBuilder:
				return "none"
			case .sendableInstantiatorBuilder:
				return "\(label) instantiator \(builtType)"
			case .sendableLazyWrapper:
				return "\(label) lazy wrapper \(builtType)"
			case .otherSendableFunction:
				return "\(label) other"
			}
		}
		let closesOn = Dictionary(closedOnEntries().map { ($0.level, $0.entry) }, uniquingKeysWith: { first, _ in first })
		// A level's routes come down only the edges that build its variant in line: a call that closes a cycle refers to a
		// builder function and enters no body. An edge that builds in line on some routes and closes on others is two levels,
		// one built in line and one that closes. Levels alike in everything but their parents are one level with every
		// parent, as the stored graph merges them.
		var parentsByLevel = [String: Set<String>]()
		for level in levels + closingLevels where !world.graph.nodes[Int(world.declaration(of: level.id.variant))].key.isFill && level.fill == nil {
			let opened = level.parents.first.map { parent in
				spelled(opens: levels.first { $0.id == parent }?.opens ?? closingLevels.first { $0.id == parent }?.opens ?? .none, into: parent)
			} ?? "none"
			let segment = world.graph.nodes[Int(world.declaration(of: level.id.variant))].property?.label ?? ""
			let parents = Set(level.parents.filter(buildsInLine).map(key(of:)))
			var entries = [String]()
			if buildsInLine(level.id) || !closesCycle(level.id) {
				entries.append("none")
			}
			if closesCycle(level.id), let entry = closesOn[level.id] {
				entries.append("\(entry.property.label): \(entry.concreteType.asSource)")
			}
			for entry in entries {
				let fields = [
					"position=\(level.nextPosition < 0 ? "none" : String(level.nextPosition))",
					"loop=\(level.nextLoop < 0 ? "none" : String(level.nextLoop))",
					"opens=\(opened)",
					"segment=\(segment)",
					"closesOn=\(entry)",
				]
				parentsByLevel["\(key(of: level.id))\t\(fields.joined(separator: " "))", default: []].formUnion(parents)
			}
		}
		var draftedByKey = [String: Set<String>]()
		for (level, parents) in parentsByLevel {
			let parts = level.components(separatedBy: "\t")
			draftedByKey[parts[0], default: []].insert("\(parts[1]) parents=\(parents.sorted().joined(separator: "; "))")
		}
		func storedKey(of level: SeamSignature.Places.Level) -> String {
			"\(level.key.builtType?.asSource ?? "fill") before \(level.key.nextProperty?.label ?? "fill")"
		}
		var differences = Set<String>()
		var compared = 0
		var alike = 0
		for level in places.levels where !level.key.isInFill {
			let key = storedKey(of: level)
			guard let drafted = draftedByKey[key] else { continue }
			let opened = level.opensSendableFunction.map { opened -> String in
				switch opened.function {
				case let .instantiator(builtType):
					"\(opened.property.label) instantiator \(builtType.asSource)"
				case let .sendableLazyWrapper(builtType):
					"\(opened.property.label) lazy wrapper \(builtType.asSource)"
				case .other:
					"\(opened.property.label) other"
				}
			} ?? "none"
			let fields = [
				"position=\(level.nextPosition.map(String.init) ?? "none")",
				"loop=\(level.nextLoop.map(String.init) ?? "none")",
				"opens=\(opened)",
				"segment=\(level.pathSegment.map(\.label).joined(separator: "."))",
				"closesOn=\(level.closesOn.map { "\($0.property.label): \($0.concreteType.asSource)" } ?? "none")",
				"parents=\(Set(level.parents.map { storedKey(of: places.levels[$0]) }).sorted().joined(separator: "; "))",
			]
			compared += 1
			let spelledFields = fields.joined(separator: " ")
			guard !drafted.contains(spelledFields) else {
				alike += 1
				continue
			}
			// Name the fields that no drafted level of the key shares.
			for field in fields where !drafted.contains(where: { $0.contains(field) }) {
				let name = field.prefix { $0 != "=" }
				let draftedValues = Set(drafted.compactMap { spelling in spelling.components(separatedBy: " \(name)=").dropFirst().first.map { "\(name)=\($0)" } ?? (spelling.hasPrefix("\(name)=") ? String(spelling.prefix { $0 != " " }) : nil) })
				differences.insert("level fields: \(key): stored \(field), drafted \(draftedValues.sorted().joined(separator: " | "))")
			}
		}
		return ["report: level fields: \(compared) stored levels compared, \(alike) alike"] + differences.sorted()
	}
}
