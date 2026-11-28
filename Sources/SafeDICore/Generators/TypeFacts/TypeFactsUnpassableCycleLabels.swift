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

/// The parameters of the functions lazy cycles close on, read from the per-type facts alone: for each place the tree
/// builds such a function, the labels it takes in the order its body first receives them (`CycleParameter`), and the
/// labels no one parameter can pass (`UnpassableCycleLabel`).
struct TypeFactsCycleFunctionParameters {
	/// A declaration where the tree builds its function: the declaration, beneath the declarations of its component
	/// that are being built above it, outermost first. A call of one of those closes a cycle on it, so the declaration's
	/// body ends there, and two places of one declaration beneath other such declarations have other bodies.
	struct Place: Hashable {
		let declaration: DeclarationID
		let componentMembersAbove: [DeclarationID]
	}

	/// One parameter of a place's function.
	struct Parameter: Hashable {
		/// The property the parameter binds (`CycleParameter.property`).
		let property: Property
		/// The declaration of the label between the function and a call that closes a cycle on it that precedes the
		/// others in source order (`CycleParameter.redeclaration`).
		let redeclaration: CycleParameter.Redeclaration
		/// Whether that declaration is a property its type forwards.
		let isForwarded: Bool
	}

	/// Every place of a declaration on a cycle, in the order a walk from the root first meets each, with its function's
	/// parameters.
	let places: [(place: Place, parameters: [Parameter])]
	/// The labels no one parameter can pass, each with the declaration whose function it is, in declaration order then
	/// label order.
	let unpassableLabels: [(declaration: DeclarationID, label: String)]
	/// For each declaration, the group of declarations whose functions can close on one another: its strongly connected
	/// component joined with those of the other declarations of its cycle identity (`TypeFactsWorld.cycle(of:)`), or -1
	/// for a declaration on no cycle that has no such twin. A place's `componentMembersAbove` are of its group.
	let cycleGroups: [Int32]
}

extension TypeFactsGraph {
	private typealias CyclePlace = TypeFactsCycleFunctionParameters.Place

	/// What a walk of one function's body has met of the labels its component declares.
	private struct BodyReceives {
		var formsByLabel = [String: Set<Property>]()
		var requiredForms = Set<Property>()
		var labelsDeclaredBeforeACloser = [String: CycleParameter.Redeclaration]()
	}

	/// The parameters of each function a cycle closes on, and the labels no one parameter can pass.
	///
	/// A function's body is its declaration's tree down to each call that closes a cycle on a declaration being built
	/// above the call. Such a call hands the closed-on function its parameters, so it receives, of a label, the one
	/// parameter that function takes for it: the functions' parameters are solved together, to a fixed point, as the
	/// tree's are.
	func cycleFunctionParameters() -> TypeFactsCycleFunctionParameters {
		var ownReceives = [[(property: Property, isRequired: Bool)]]()
		var declaredLabels = [[String: CycleParameter.Redeclaration]]()
		// The forms each declaration provides to the scopes beneath it, as `ScopeGenerator.providedProperties` lists them.
		var declaredForms = [Set<Property>]()
		/// Whether a scope that provides `forms` hides a receive of `property` from the scopes above it, as the tree decides
		/// it (`ScopeGenerator.receives(children:…)`): it provides the property, the unwrapped form of an optional one, or,
		/// for a receive only if available, a form such a receive reads.
		func hides(_ forms: Set<Property>, _ property: Property, isRequired: Bool) -> Bool {
			forms.contains(property)
				|| (property.typeDescription.isOptional && forms.contains(property.asUnwrappedProperty))
				|| (!isRequired && property.formsReadByOnlyIfAvailableReceive.contains { forms.contains($0) })
		}
		var forwardedRedeclarations = Set<CycleParameter.Redeclaration>()
		for index in 0..<declarationCount {
			var declared = [String: CycleParameter.Redeclaration]()
			var forms = Set<Property>()
			let instantiable = graph.nodes[index].scope.instantiable
			let dependencies = graph.nodes[index].key.leaf == .none ? instantiable.dependencies : []
			// A declaration is noted at the dependency that declares its label, as the tree notes it.
			func declare(_ property: Property) {
				let dependency = dependencies.first { !$0.source.isReceived && $0.property.label == property.label }
				let redeclaration = CycleParameter.Redeclaration(
					property: dependency?.property ?? property,
					declaringType: instantiable.concreteInstantiable,
					declarationLocation: dependency?.declarationLocation,
				)
				declared[property.label] = declared[property.label].map { $0.preceding(redeclaration) } ?? redeclaration
				for declaredProperty in [property, redeclaration.property] {
					forms.insert(declaredProperty)
					if let instanceProperty = declaredProperty.asLazilyInstantiatedInstancePropertyOfDeclaredBinding {
						forms.insert(instanceProperty)
					}
				}
				if dependency?.source == .forwarded {
					forwardedRedeclarations.insert(redeclaration)
				}
			}
			for child in edges(from: Int32(index)) {
				if let property = graph.nodes[Int(child)].property {
					declare(property)
				}
			}
			for dependency in dependencies {
				switch dependency.source {
				case .instantiated, .forwarded:
					declare(dependency.property)
				case .received, .aliased:
					break
				}
			}
			var receives = [(property: Property, isRequired: Bool)]()
			var aliasProperties = [Property]()
			for dependency in dependencies {
				switch dependency.source {
				case let .received(onlyIfAvailable):
					receives.append((dependency.property, !onlyIfAvailable))
				case let .aliased(fulfillingProperty, _, onlyIfAvailable):
					// An alias of a property its own type declares reads that declaration: it receives nothing.
					if !(onlyIfAvailable ? fulfillingProperty.formsReadByOnlyIfAvailableReceive : [fulfillingProperty]).contains(where: forms.contains) {
						receives.append((fulfillingProperty, !onlyIfAvailable))
					}
					// The alias declares its own label to the scopes beneath it.
					aliasProperties.append(dependency.property)
				case .instantiated, .forwarded:
					break
				}
			}
			for aliasProperty in aliasProperties {
				declare(aliasProperty)
			}
			ownReceives.append(receives)
			declaredLabels.append(declared)
			declaredForms.append(forms)
		}
		// A call of a declaration closes a cycle on a declaration of its cycle identity being built above it: itself, or
		// its twin, a value and a lazily instantiated wrapper of one label and type.
		func closes(_ declaration: Int32, on other: Int32) -> Bool {
			declaration == other || cycle(of: declaration) == cycle(of: other)
		}
		// A seam's call inside one of the seam's own fills passes the fills it was handed: the fill is not built again, so
		// its edge closes no cycle and reaches nothing.
		func reenters(_ child: Int32, in path: [Int32]) -> Bool {
			graph.nodes[Int(child)].key.isFill && path.contains { closes(child, on: $0) }
		}
		// The groups of declarations whose functions can close on one another: components joined through twins.
		var groupOfComponent = [ComponentID: ComponentID]()
		func group(ofComponent component: ComponentID) -> ComponentID {
			var group = component
			while let next = groupOfComponent[group] {
				group = next
			}
			return group
		}
		for declaration in 0..<Int32(declarationCount) where twins[Int(declaration)] >= 0 {
			let ownGroup = group(ofComponent: component(of: declaration))
			let twinGroup = group(ofComponent: component(of: twins[Int(declaration)]))
			if ownGroup != twinGroup {
				groupOfComponent[max(ownGroup, twinGroup)] = min(ownGroup, twinGroup)
			}
		}
		let cycleGroups = (0..<Int32(declarationCount)).map { declaration in
			isOnCycle(declaration) || twins[Int(declaration)] >= 0 ? group(ofComponent: component(of: declaration)) : -1
		}
		func componentMembers(of declaration: Int32, in path: [Int32]) -> [Int32] {
			guard cycleGroups[Int(declaration)] >= 0 else { return [] }
			return path.filter { cycleGroups[Int($0)] == cycleGroups[Int(declaration)] }
		}
		/// `redeclarations` with those of `others`, each label keeping the declaration that comes first in source order.
		func merging(_ redeclarations: [String: CycleParameter.Redeclaration], _ others: [String: CycleParameter.Redeclaration]) -> [String: CycleParameter.Redeclaration] {
			redeclarations.merging(others) { $0.preceding($1) }
		}
		// Every place of a declaration on a cycle, in the order a walk from the root first meets each.
		var places = [CyclePlace]()
		var visitedPlaces = Set<CyclePlace>()
		func visit(_ declaration: Int32, path: [Int32]) {
			let place = CyclePlace(declaration: declaration, componentMembersAbove: componentMembers(of: declaration, in: path))
			guard visitedPlaces.insert(place).inserted else { return }
			if cycleGroups[Int(declaration)] >= 0 {
				places.append(place)
			}
			for child in edges(from: declaration) where !closes(child, on: declaration) && !path.contains(where: { closes(child, on: $0) }) {
				visit(child, path: path + [declaration])
			}
		}
		visit(0, path: [])

		var parameters = [CyclePlace: [String: (property: Property, passedForms: Set<Property>, requiredForms: Set<Property>)]]()
		// The labels declared between each place's function and a call that closes a cycle on it, with those of every
		// function whose body holds such a call: where that function is called beneath a declaration, so is the call.
		var labelsDeclaredBeforeACloser = [CyclePlace: [String: CycleParameter.Redeclaration]]()
		var redeclarationsOfParameters = [CyclePlace: [String: CycleParameter.Redeclaration]]()
		var unpassableByDeclaration = [Int32: Set<String>]()
		// Each pass hands what the last found down the calls that close a cycle, until a pass changes nothing.
		for _ in 0...(places.count * 4) {
			var changed = false
			unpassableByDeclaration = [:]
			for place in places {
				var body = BodyReceives()
				var closedOnPlaces = Set<CyclePlace>()
				var visited = Set<[AnyHashable]>()
				func receive(_ property: Property, isRequired: Bool, beneath hidden: Set<Property>) {
					guard !hides(hidden, property, isRequired: isRequired) else { return }
					body.formsByLabel[property.label, default: []].insert(property)
					if isRequired {
						body.requiredForms.insert(property)
					}
				}
				func walk(_ declaration: Int32, path: [Int32], hidden: Set<Property>, declaredBelow: [String: CycleParameter.Redeclaration]) {
					let membersAbove = componentMembers(of: declaration, in: path)
					guard visited.insert([declaration, membersAbove, hidden, declaredBelow]).inserted else { return }
					for ownReceive in ownReceives[Int(declaration)] {
						receive(ownReceive.property, isRequired: ownReceive.isRequired, beneath: hidden)
					}
					let hiddenBeneath = hidden.union(declaredForms[Int(declaration)])
					let declaredBeneath = declaration == place.declaration ? declaredBelow : merging(declaredBelow, declaredLabels[Int(declaration)])
					let pathBeneath = path + [declaration]
					for child in edges(from: declaration) where !reenters(child, in: pathBeneath) {
						if closes(child, on: place.declaration) {
							body.labelsDeclaredBeforeACloser = merging(body.labelsDeclaredBeforeACloser, declaredBeneath)
						} else if let position = pathBeneath.firstIndex(where: { closes(child, on: $0) }) {
							// A call that closes a cycle on another function hands it its parameters.
							let closedOn = CyclePlace(declaration: pathBeneath[position], componentMembersAbove: componentMembers(of: pathBeneath[position], in: Array(pathBeneath[..<position])))
							// Only a function above this one is called again wherever this one is: one built inside this
							// function's body is called beneath this function's own declarations alone.
							if position < place.componentMembersAbove.count {
								closedOnPlaces.insert(closedOn)
							}
							// The closing scope receives what the function's body receives under each parameter's label.
							for parameter in parameters[closedOn, default: [:]].values {
								for form in parameter.passedForms.union(parameter.requiredForms) {
									receive(form, isRequired: parameter.requiredForms.contains(form), beneath: hiddenBeneath)
								}
							}
						} else {
							walk(child, path: pathBeneath, hidden: hiddenBeneath, declaredBelow: declaredBeneath)
						}
					}
				}
				walk(place.declaration, path: place.componentMembersAbove, hidden: [], declaredBelow: [:])
				let declaredBeforeACloser = merging(body.labelsDeclaredBeforeACloser, labelsDeclaredBeforeACloser[place, default: [:]])
				for closedOn in closedOnPlaces {
					let handedOn = merging(labelsDeclaredBeforeACloser[closedOn, default: [:]], declaredBeforeACloser)
					if handedOn != labelsDeclaredBeforeACloser[closedOn, default: [:]] {
						labelsDeclaredBeforeACloser[closedOn] = handedOn
						changed = true
					}
				}
				redeclarationsOfParameters[place] = declaredBeforeACloser
				// The function's own label is no parameter, nor is a label its type declares or forwards itself, as in the tree.
				let ownLabels = Set(declaredLabels[Int(place.declaration)].keys).union([graph.nodes[Int(place.declaration)].property?.label].compactMap(\.self))
				for label in declaredBeforeACloser.keys.sorted() where !ownLabels.contains(label) {
					guard let forms = body.formsByLabel[label] else { continue }
					let requiredForms = body.requiredForms.intersection(forms)
					if let (property, passedForms) = CycleParameter.property(passing: forms, requiredForms: requiredForms) {
						let previous = parameters[place, default: [:]][label]
						if previous?.property != property || previous?.passedForms != passedForms || previous?.requiredForms != requiredForms {
							parameters[place, default: [:]][label] = (property, passedForms, requiredForms)
							changed = true
						}
					} else {
						unpassableByDeclaration[place.declaration, default: []].insert(label)
					}
				}
			}
			guard changed else { break }
		}
		return TypeFactsCycleFunctionParameters(
			places: places.map { place in
				let taken = parameters[place, default: [:]].filter { !unpassableByDeclaration[place.declaration, default: []].contains($0.key) }
				let order = parameterOrder(of: place.declaration)
				var orderedLabels = order.map { labelTexts[Int($0)] }.filter { taken[$0] != nil }
				orderedLabels.append(contentsOf: Set(taken.keys).subtracting(orderedLabels).sorted())
				return (place, orderedLabels.compactMap { label in
					guard let property = taken[label]?.property, let redeclaration = redeclarationsOfParameters[place]?[label] else { return nil }
					return TypeFactsCycleFunctionParameters.Parameter(property: property, redeclaration: redeclaration, isForwarded: forwardedRedeclarations.contains(redeclaration))
				})
			},
			unpassableLabels: unpassableByDeclaration.keys.sorted().flatMap { declaration in
				unpassableByDeclaration[declaration, default: []].sorted().map { (declaration, $0) }
			},
			cycleGroups: cycleGroups,
		)
	}
}
