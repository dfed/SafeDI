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

/// What `SeamHoles` hands the scopes of one path of a seam's tree, spelled as bytes so that two paths of a class hand
/// their generators the same text: strings by their UTF-8 bytes and types by `asSource`, never by `==`, which reads
/// canonically equivalent strings, and `any P` and `P`, alike though generated code spells them apart. Each part is
/// listed explicitly, so a part `SeamHoles` adds is in no class until it is added here, which the memo oracle catches:
/// it compares every stored value of a shared generator with the unshared tree's on every path.
struct PositionClassContent: Hashable {
	private(set) var bytes = [UInt8]()

	mutating func append(_ string: String) {
		append(string.utf8.count)
		bytes.append(contentsOf: string.utf8)
	}

	mutating func append(_ int: Int) {
		bytes.append(contentsOf: String(int).utf8)
		bytes.append(0x3B)
	}

	mutating func append(_ flag: Bool) {
		bytes.append(flag ? 0x31 : 0x30)
	}

	mutating func append(_ string: String?) {
		append(string != nil)
		if let string {
			append(string)
		}
	}

	mutating func append(_ type: TypeDescription) {
		append(type.asSource)
	}

	mutating func append(_ property: Property) {
		append(property.label)
		append(property.typeDescription)
	}

	/// An access level, by its spelling.
	mutating func append(_ access: AccessLevel) {
		append(access.spelling)
	}

	/// What a site's or a member call's code reads of a field: its property, and how it is bound and handed.
	mutating func append(_ fields: [SeamSignature.Hole.Field]) {
		append(fields.count)
		for field in fields {
			append(field.property)
			append(field.access)
			switch field.deferral {
			case .none:
				append(0)
			case let .deferred(isSendable):
				append(isSendable ? 2 : 1)
			}
			append(field.bindsMemo)
			append(field.isSeamParameter)
			append(field.isBoundByPublicMockRoot)
			append(field.isReceivedOnlyIfAvailable)
		}
	}

	mutating func append(_ use: SeamCarrierValues.Use?) {
		append(use != nil)
		guard let use else { return }
		append(use.level)
		append(use.structEnd ?? -1)
		append(use.extras.lowerBound)
		append(use.extras.upperBound)
		append(use.ends.count)
		for end in use.ends {
			append(end)
		}
	}

	mutating func append(_ bindings: [SeamHoles.ValuesBinding]) {
		append(bindings.count)
		for binding in bindings {
			append(binding.bindingName)
			append(binding.type)
			append(binding.boundType)
			append(binding.fields)
			append(binding.memberCall.parentName)
			append(binding.memberCall.caseName)
			append(binding.isCalledInsideFunction)
			append(binding.isLetChild)
			append(binding.carrierUse)
			switch binding.formsRunAfter {
			case .none:
				append(0)
			case .some(.none):
				append(1)
			case let .some(.some(previousName)):
				append(2)
				append(previousName)
			}
		}
	}

	mutating func append(_ site: HoleSiteView?) {
		append(site != nil)
		guard let site else { return }
		append(site.internalName)
		append(site.wrapperFunctionName)
		append(site.builtType)
		append(site.builderLabel)
		append(site.place != nil)
		guard let place = site.place else { return }
		append(place.values)
		append(place.memberValuesTypeName)
		append(place.enumType)
		append(place.caseName)
		append(place.isBuiltBySendableBuilder)
		switch place.parent {
		case let .builder(levelType):
			append(0)
			append(levelType)
		case let .level(name, type):
			append(1)
			append(name)
			append(type)
		case let .fillLevelStruct(name):
			append(2)
			append(name)
		}
	}

	mutating func append(_ carrierSite: SeamHoles.CarrierSite?) {
		append(carrierSite != nil)
		guard let carrierSite else { return }
		append(carrierSite.use)
		append(carrierSite.formations)
	}
}

enum SeamPositionClasses {
	/// The class of every path that leads to a path `contentByPath` holds, by path: two paths share a class exactly when
	/// they hold the same content and their children, by property, the same classes, so the subtrees beneath two paths of a
	/// class read the same of `SeamHoles` at every depth. A path that leads to none reads nothing of `SeamHoles` beneath
	/// it, and is class 0, which no path here is. Classes are numbered in the order of the paths sorted by length, longest
	/// first, then by their spelling, so a run numbers alike whatever order the maps hold.
	static func classes(of contentByPath: [[Property]: PositionClassContent]) -> [[Property]: Int] {
		var childrenByPath = [[Property]: Set<Property>]()
		var paths = Set<[Property]>()
		for path in contentByPath.keys {
			// Each prefix once: a prefix already met has its own prefixes and their children already.
			for length in stride(from: path.count, to: 0, by: -1) {
				guard paths.insert(Array(path[..<length])).inserted else { break }
				if length > 1 {
					childrenByPath[Array(path[..<(length - 1)]), default: []].insert(path[length - 1])
				}
			}
		}
		let ordered = paths.map { (path: $0, spelling: Self.spelling(of: $0)) }.sorted {
			$0.path.count != $1.path.count ? $0.path.count > $1.path.count : $0.spelling.lexicographicallyPrecedes($1.spelling)
		}
		var classByContent = [PositionClassContent: Int]()
		var classByPath = [[Property]: Int]()
		for (path, _) in ordered {
			var content = contentByPath[path] ?? PositionClassContent()
			let children = (childrenByPath[path] ?? []).map { (property: $0, spelling: Self.spelling(of: [$0])) }.sorted { $0.spelling.lexicographicallyPrecedes($1.spelling) }
			content.append(children.count)
			for child in children {
				content.append(child.property)
				content.append(classByPath[path + [child.property]] ?? 0)
			}
			if let positionClass = classByContent[content] {
				classByPath[path] = positionClass
			} else {
				let positionClass = classByContent.count + 1
				classByContent[content] = positionClass
				classByPath[path] = positionClass
			}
		}
		GenerationWork.record(classByContent.count, by: ConstructionMemo.isEnabled ? .interningPositionClasses : nil)
		return classByPath
	}

	/// A path's properties as bytes, each label and type spelled, which orders paths alike on every run.
	private static func spelling(of path: [Property]) -> [UInt8] {
		var bytes = [UInt8]()
		for property in path {
			bytes.append(contentsOf: property.label.utf8)
			bytes.append(0)
			bytes.append(contentsOf: property.typeDescription.asSource.utf8)
			bytes.append(0)
		}
		return bytes
	}
}
