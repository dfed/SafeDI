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
	struct CyclePlace: Hashable {
		let declaration: Int32
		let componentMembersAbove: [Int32]
	}

	/// A label no one parameter can pass at one place of a function (`unpassableCycleLabelSolution()`): the forms the function's
	/// body receives of it, in property order, and the declaration of it between the function and a call that closes a
	/// cycle on it that precedes the others in source order (`CycleParameter.Redeclaration.preceding(_:)`).
	struct UnpassablePlaceLabel {
		let place: CyclePlace
		let label: String
		let forms: [Property]
		let redeclaration: CycleParameter.Redeclaration
	}

	/// What the fold of `unpassableCycleLabelSolution()` settles: the labels no one parameter can pass, each at a place of its
	/// function in the order a walk from the root first meets the places, then in label order; and the labels each
	/// place's function takes as parameters.
	struct UnpassableCycleLabelSolution {
		let labels: [UnpassablePlaceLabel]
		let parameterLabels: [CyclePlace: Set<String>]
	}

	/// What a walk of one function's body has met of the labels its component declares.
	private struct BodyReceives {
		var formsByLabel = [String: Set<Property>]()
		var requiredForms = Set<Property>()
		var labelsDeclaredBeforeACloser = Set<String>()
		var redeclarations = [String: CycleParameter.Redeclaration]()
	}

	/// The labels the function a cycle closes on receives from above it, which a declaration between the function and
	/// the closing call declares again, in forms no one parameter can pass (`UnpassableCycleLabel`), each at the place of
	/// the function it is found at, with the forms the function's body receives and the declaration a diagnostic notes;
	/// and the labels each function takes as parameters (`TypeFactsGraph.unpassableCycleLabelValues()` reads them).
	///
	/// A function's body is its declaration's tree down to each call that closes a cycle on a declaration being built
	/// above the call. Such a call hands the closed-on function its parameters, so it receives, of a label, the one
	/// parameter that function takes for it: the functions' parameters are solved together, to a fixed point, as the
	/// tree's are.
	func unpassableCycleLabelSolution() -> UnpassableCycleLabelSolution {
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
				var aliasLabels = Set<String>()
				for dependency in dependencies {
					switch dependency.source {
					case let .received(onlyIfAvailable):
						receives.append((dependency.property, !onlyIfAvailable))
					case let .aliased(fulfillingProperty, _, onlyIfAvailable):
						// An alias of a property its own type declares reads that declaration: it receives nothing.
						if !labels.contains(fulfillingProperty.label) {
							receives.append((fulfillingProperty, !onlyIfAvailable))
						}
						// The alias declares its own label to the scopes beneath it.
						aliasLabels.insert(dependency.property.label)
					case .instantiated, .forwarded:
						break
					}
				}
				labels.formUnion(aliasLabels)
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
		// The declaration of each parameter's label the function's parameter was typed beneath, which the declarations
		// between a function and a call that closes a cycle on another function inside it count too.
		var parameterRedeclarations = [CyclePlace: [String: CycleParameter.Redeclaration]]()
		// The labels declared between each place's function and a call that closes a cycle on it, with those of every
		// function whose body holds such a call: where that function is called beneath a declaration, so is the call.
		var labelsDeclaredBeforeACloser = [CyclePlace: Set<String>]()
		var redeclarationsBeforeACloser = [CyclePlace: [String: CycleParameter.Redeclaration]]()
		var unpassableLabels = [UnpassablePlaceLabel]()
		// The labels each declaration declares, each noted where a diagnostic notes it, built when a walk first passes it.
		var declarationRedeclarations = [Int32: [String: CycleParameter.Redeclaration]]()
		// Each pass hands what the last found down the calls that close a cycle, until a pass changes nothing.
		for _ in 0...(places.count * 4) {
			var changed = false
			unpassableLabels = []
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
					for child in edges(from: declaration) where !reentersFill(child, in: pathBeneath, closesOn: { $0 == child }) {
						if child == place.declaration {
							body.labelsDeclaredBeforeACloser.formUnion(declaredBeneath)
							// The declarations between the function and this call, each noted at its declaration of the label.
							for (offset, between) in pathBeneath.enumerated().dropFirst(place.componentMembersAbove.count + 1) {
								let betweenRedeclarations = declarationRedeclarations[between] ?? Self.redeclarations(by: between, in: self)
								declarationRedeclarations[between] = betweenRedeclarations
								for (label, redeclaration) in betweenRedeclarations {
									body.redeclarations[label] = Self.preceding(body.redeclarations[label], redeclaration)
								}
								let betweenPlace = CyclePlace(declaration: between, componentMembersAbove: componentMembers(of: between, in: Array(pathBeneath[..<offset])))
								for (label, parameterRedeclaration) in parameterRedeclarations[betweenPlace, default: [:]] {
									body.redeclarations[label] = Self.preceding(body.redeclarations[label], parameterRedeclaration)
								}
							}
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
				var redeclarations = body.redeclarations
				for (label, redeclaration) in redeclarationsBeforeACloser[place, default: [:]] {
					redeclarations[label] = Self.preceding(redeclarations[label], redeclaration)
				}
				for closedOn in closedOnPlaces {
					if !declaredBeforeACloser.isSubset(of: labelsDeclaredBeforeACloser[closedOn, default: []]) {
						labelsDeclaredBeforeACloser[closedOn, default: []].formUnion(declaredBeforeACloser)
						changed = true
					}
					for (label, redeclaration) in redeclarations {
						let merged = Self.preceding(redeclarationsBeforeACloser[closedOn, default: [:]][label], redeclaration)
						if redeclarationsBeforeACloser[closedOn, default: [:]][label] != merged {
							redeclarationsBeforeACloser[closedOn, default: [:]][label] = merged
							changed = true
						}
					}
				}
				for label in declaredBeforeACloser.sorted() {
					guard let forms = body.formsByLabel[label], let redeclaration = redeclarations[label] else { continue }
					if let (property, _) = CycleParameter.property(passing: forms, requiredForms: body.requiredForms.intersection(forms)) {
						if parameters[place, default: [:]][label] != property {
							parameters[place, default: [:]][label] = property
							changed = true
						}
						parameterRedeclarations[place, default: [:]][label] = redeclaration
					} else {
						unpassableLabels.append(UnpassablePlaceLabel(place: place, label: label, forms: forms.sorted(), redeclaration: redeclaration))
					}
				}
			}
			guard changed else { break }
		}
		return UnpassableCycleLabelSolution(labels: unpassableLabels, parameterLabels: parameters.mapValues { Set($0.keys) })
	}

	/// The one of `current` and `candidate` that precedes the other in source order (`CycleParameter.Redeclaration.preceding(_:)`).
	private static func preceding(_ current: CycleParameter.Redeclaration?, _ candidate: CycleParameter.Redeclaration) -> CycleParameter.Redeclaration {
		current.map { $0.preceding(candidate) } ?? candidate
	}

	/// The labels `declaration` declares for the declarations it builds, each as a diagnostic notes it: at the first
	/// dependency of its type that declares the label, or, for a property no dependency declares (a child a mock root
	/// promotes), at no location.
	private static func redeclarations(by declaration: Int32, in graph: TypeFactsGraph) -> [String: CycleParameter.Redeclaration] {
		let instantiable = graph.graph.nodes[Int(declaration)].scope.instantiable
		let declaringType = instantiable.concreteInstantiable
		var redeclarations = [String: CycleParameter.Redeclaration]()
		for child in graph.edges(from: declaration) {
			if let property = graph.graph.nodes[Int(child)].property {
				redeclarations[property.label] = preceding(redeclarations[property.label], CycleParameter.Redeclaration(property: property, declaringType: declaringType, declarationLocation: nil))
			}
		}
		// The first dependency that declares a label is noted, whatever else declares it.
		for dependency in instantiable.dependencies.reversed() where !dependency.source.isReceived {
			redeclarations[dependency.property.label] = CycleParameter.Redeclaration(property: dependency.property, declaringType: declaringType, declarationLocation: dependency.declarationLocation)
		}
		return redeclarations
	}
}
