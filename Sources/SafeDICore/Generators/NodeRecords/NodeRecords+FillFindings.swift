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

/// What node records refuse of a root's filled seam call so that they never lay out a root whose fills
/// `DependencyTreeGenerator.validateFills` reports: each fact a finding of it reads (`FillFinding.Kind`), judged from the
/// world and the holes alone, wider than the check, which judges the tree. A root refused here keeps its tree until the
/// check reads the facts.
enum FillFindingFacts {
	/// Whether a fill of `facts`, the fills of one call of `world`, reads anything `validateFills` judges: a label the
	/// place's path declares where the fill cannot read it (`uncarriedDeclarations`, `cycleReentryDeclarations`,
	/// `declarationsHiddenByFields`), a place whose fills build the seam again (`reenteringCallDeclarations`,
	/// `reenteringPlaceFields`), a field the root's module may not read, a field that does not give every form the fill's
	/// tree receives of its label, a lazy wrapper read beside a memo the fill binds of its label, or a label whose
	/// fields differ in form between the places of one case.
	static func mayBeReported(_ facts: [FillFacts], in world: TypeFactsGraph) -> Bool {
		let rootModuleName = world.scope(of: 0).instantiable.moduleName
		var fieldFormsByCaseAndLabel = [String: Set<TypeDescription>]()
		for fill in facts {
			let hole = fill.hole
			guard hole.reenteringCallDeclarations.isEmpty, hole.reenteringPlaceFields.isEmpty else { return true }
			let readLabels = Set(fill.readLabels)
			let unreadableLabels = Set(hole.uncarriedDeclarations.map(\.property.label))
				.union(hole.cycleReentryDeclarations.map(\.property.label))
				.union(hole.declarationsHiddenByFields.map(\.property.label))
			guard readLabels.isDisjoint(with: unreadableLabels) else { return true }
			let formsByLabel = receivedForms(beneath: fill.declaration, ofLabels: readLabels, in: world)
			let caseKey = ScopeGenerator.fillCaseKey(of: hole)
			for field in hole.fields where readLabels.contains(field.property.label) {
				let label = field.property.label
				fieldFormsByCaseAndLabel["\(caseKey)\u{0}\(label)", default: []].insert(field.property.typeDescription.unwrapped)
				let isReadable = switch field.access {
				case .open, .public:
					true
				case .package, .internal:
					rootModuleName != nil && rootModuleName == hole.scopeSeamModule.moduleName
				case .fileprivate, .private:
					false
				}
				guard isReadable else { return true }
				for form in formsByLabel[label, default: []] {
					// As `validateFills` asks whether a field gives a receive its value.
					let candidates = [form.property] + (form.property.typeDescription.isOptional ? [form.property.asUnwrappedProperty] : [])
					let provided = candidates.contains { $0 == field.property || $0 == field.property.asLazilyInstantiatedInstancePropertyOfDeclaredBinding }
					guard provided else { return true }
					// A wrapper read beside a memo the fill binds of its label.
					guard form.property.typeDescription.unwrapped.lazilyInstantiatedInstanceType == nil || !fill.memoBoundLabels.contains(label) else { return true }
				}
			}
		}
		return fieldFormsByCaseAndLabel.values.contains { $0.count > 1 }
	}

	/// The forms of each of `labels` the tree beneath `fill` receives, each with whether it is received only if available,
	/// in one walk of that tree.
	private static func receivedForms(beneath fill: DeclarationID, ofLabels labels: Set<String>, in world: TypeFactsGraph) -> [String: [(property: Property, isOnlyIfAvailable: Bool)]] {
		var forms = [String: [(property: Property, isOnlyIfAvailable: Bool)]]()
		var pending = [fill]
		var visited: Set = [fill]
		while let declaration = pending.popLast() {
			for dependency in world.scope(of: declaration).instantiable.dependencies {
				switch dependency.source {
				case let .received(onlyIfAvailable):
					if labels.contains(dependency.property.label) {
						forms[dependency.property.label, default: []].append((dependency.property, onlyIfAvailable))
					}
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					if labels.contains(fulfillingProperty.label) {
						forms[fulfillingProperty.label, default: []].append((fulfillingProperty, onlyIfAvailable))
					}
				case .instantiated, .forwarded:
					break
				}
			}
			for child in world.edges(from: declaration) where visited.insert(child).inserted {
				pending.append(child)
			}
		}
		return forms
	}
}
