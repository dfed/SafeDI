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

extension TypeFactsGraph {
	/// A declaration where the tree builds its function: the declaration, beneath the declarations of its component
	/// that are being built above it, outermost first. A call of one of those closes a cycle on it, so the declaration's
	/// body ends there, and two places of one declaration beneath other such declarations have other bodies.
	private struct CyclePlace: Hashable {
		let declaration: Int32
		let componentMembersAbove: [Int32]
	}

	/// What a walk of one function's body has met of the labels its component declares.
	private struct BodyReceives {
		var formsByLabel = [String: Set<Property>]()
		var requiredForms = Set<Property>()
		var labelsDeclaredBeforeACloser = Set<String>()
	}

	/// The labels the function a cycle closes on receives from above it, which a declaration between the function and
	/// the closing call declares again, in forms no one parameter can pass (`UnpassableCycleLabel`), each with the
	/// declaration whose function it is, in declaration order then label order.
	///
	/// A function's body is its declaration's tree down to each call that closes a cycle on a declaration being built
	/// above the call. Such a call hands the closed-on function its parameters, so it receives, of a label, the one
	/// parameter that function takes for it: the functions' parameters are solved together, to a fixed point, as the
	/// tree's are.
	func unpassableCycleLabels() -> [(declaration: DeclarationID, label: String)] {
		var ownReceives = [[(property: Property, isRequired: Bool)]]()
		var declaredLabels = [Set<String>]()
		for index in 0..<declarationCount {
			var labels = Set<String>()
			for child in edges(from: Int32(index)) {
				if let label = graph.nodes[Int(child)].property?.label {
					labels.insert(label)
				}
			}
			var receives = [(property: Property, isRequired: Bool)]()
			if graph.nodes[index].key.leaf == .none {
				let dependencies = graph.nodes[index].scope.instantiable.dependencies
				for dependency in dependencies {
					switch dependency.source {
					case .instantiated, .forwarded:
						labels.insert(dependency.property.label)
					case .received, .aliased:
						break
					}
				}
				for dependency in dependencies {
					switch dependency.source {
					case let .received(onlyIfAvailable):
						receives.append((dependency.property, !onlyIfAvailable))
					case let .aliased(fulfillingProperty, _, onlyIfAvailable):
						// An alias of a property its own type declares reads that declaration: it receives nothing.
						if !labels.contains(fulfillingProperty.label) {
							receives.append((onlyIfAvailable ? fulfillingProperty.asOptionalProperty : fulfillingProperty, !onlyIfAvailable))
						}
					case .instantiated, .forwarded:
						break
					}
				}
			}
			ownReceives.append(receives)
			declaredLabels.append(labels)
		}
		func componentMembers(of declaration: Int32, in path: [Int32]) -> [Int32] {
			guard isOnCycle(declaration) else { return [] }
			return path.filter { isOnCycle($0) && component(of: $0) == component(of: declaration) }
		}
		// Every place of a declaration on a cycle, in the order a walk from the root first meets each.
		var places = [CyclePlace]()
		var visitedPlaces = Set<CyclePlace>()
		func visit(_ declaration: Int32, path: [Int32]) {
			let place = CyclePlace(declaration: declaration, componentMembersAbove: componentMembers(of: declaration, in: path))
			guard visitedPlaces.insert(place).inserted else { return }
			if isOnCycle(declaration) {
				places.append(place)
			}
			for child in edges(from: declaration) where !path.contains(child) && child != declaration {
				visit(child, path: path + [declaration])
			}
		}
		visit(0, path: [])

		var parameters = [CyclePlace: [String: Property]]()
		// The labels declared between each place's function and a call that closes a cycle on it, with those of every
		// function whose body holds such a call: where that function is called beneath a declaration, so is the call.
		var labelsDeclaredBeforeACloser = [CyclePlace: Set<String>]()
		var unpassableByDeclaration = [Int32: Set<String>]()
		// Each pass hands what the last found down the calls that close a cycle, until a pass changes nothing.
		for _ in 0...(places.count * 4) {
			var changed = false
			unpassableByDeclaration = [:]
			for place in places {
				var body = BodyReceives()
				var closedOnPlaces = Set<CyclePlace>()
				var visited = Set<[AnyHashable]>()
				func walk(_ declaration: Int32, path: [Int32], hidden: Set<String>, declaredBelow: Set<String>) {
					let membersAbove = componentMembers(of: declaration, in: path)
					guard visited.insert([declaration, membersAbove, hidden, declaredBelow]).inserted else { return }
					for receive in ownReceives[Int(declaration)] where !hidden.contains(receive.property.label) {
						body.formsByLabel[receive.property.label, default: []].insert(receive.property)
						if receive.isRequired {
							body.requiredForms.insert(receive.property)
						}
					}
					let hiddenBeneath = hidden.union(declaredLabels[Int(declaration)])
					let declaredBeneath = declaration == place.declaration ? declaredBelow : declaredBelow.union(declaredLabels[Int(declaration)])
					let pathBeneath = path + [declaration]
					for child in edges(from: declaration) {
						if child == place.declaration {
							body.labelsDeclaredBeforeACloser.formUnion(declaredBeneath)
						} else if let position = pathBeneath.firstIndex(of: child) {
							// A call that closes a cycle on another function hands it its parameters.
							let closedOn = CyclePlace(declaration: child, componentMembersAbove: componentMembers(of: child, in: Array(pathBeneath[..<position])))
							closedOnPlaces.insert(closedOn)
							for (label, property) in parameters[closedOn, default: [:]] where !hiddenBeneath.contains(label) {
								body.formsByLabel[label, default: []].insert(property)
								if !property.typeDescription.isOptional {
									body.requiredForms.insert(property)
								}
							}
						} else {
							walk(child, path: pathBeneath, hidden: hiddenBeneath, declaredBelow: declaredBeneath)
						}
					}
				}
				walk(place.declaration, path: place.componentMembersAbove, hidden: [], declaredBelow: [])
				let declaredBeforeACloser = body.labelsDeclaredBeforeACloser.union(labelsDeclaredBeforeACloser[place, default: []])
				for closedOn in closedOnPlaces where !declaredBeforeACloser.isSubset(of: labelsDeclaredBeforeACloser[closedOn, default: []]) {
					labelsDeclaredBeforeACloser[closedOn, default: []].formUnion(declaredBeforeACloser)
					changed = true
				}
				for label in declaredBeforeACloser.sorted() {
					guard let forms = body.formsByLabel[label] else { continue }
					if let (property, _) = CycleParameter.property(passing: forms, requiredForms: body.requiredForms.intersection(forms)) {
						if parameters[place, default: [:]][label] != property {
							parameters[place, default: [:]][label] = property
							changed = true
						}
					} else {
						unpassableByDeclaration[place.declaration, default: []].insert(label)
					}
				}
			}
			guard changed else { break }
		}
		return unpassableByDeclaration.keys.sorted().flatMap { declaration in
			unpassableByDeclaration[declaration, default: []].sorted().map { (declaration, $0) }
		}
	}
}
