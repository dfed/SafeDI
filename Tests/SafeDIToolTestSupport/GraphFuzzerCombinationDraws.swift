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

// MARK: - Cells

/// Where a combination cell's feature sits relative to a seam or a public mock: the seam's own tree, a hole's fill, a
/// place inside a fill, an inner seam, or a public mock. Each is a scaffold of its own (`GraphFuzzerCombinationDraw`).
enum GraphFuzzerCombinationColumn: String, CaseIterable {
	/// `ComboHome`, a seam of the seam's module, holds a place of `ComboService` that `ComboLive` fills from the roots'
	/// module.
	case seamTree = "SeamTree"
	/// The same scaffold, the feature on the fill, `ComboLive`, or beneath it.
	case holeFill = "HoleFill"
	/// `ComboHome` builds `ComboNest`, a seam of the module beneath its own, whose place of `ComboNestService`
	/// `ComboNestImpl` fills in `ComboHome`'s module; `ComboNestImpl` holds a place of `ComboService`, which `ComboLive`
	/// fills from the roots' module: a place inside a fill.
	case placeInsideFill = "PlaceInsideFill"
	/// `ComboHome` builds `ComboInner`, a seam of the module beneath its own, which holds a place of `ComboService` that
	/// `ComboHome` passes up and `ComboLive` fills from the roots' module.
	case innerSeam = "InnerSeam"
	/// `ComboHome`, a `.public` type of the declaring module with an `internal` initializer, holds a place of
	/// `ComboService`; `ComboApp`, a mocked type of a consumer module, builds it, so its mock calls `ComboHome`'s, and
	/// `ComboLive` fills the place from the consumer's module.
	case publicMock = "PublicMock"
}

/// Where in its column the cell's feature sits.
enum GraphFuzzerCombinationPosition: String, CaseIterable {
	/// On the column's boundary type: the seam, the fill, the fill that holds a place, the inner seam, the public mock.
	case boundary = "AtBoundary"
	/// On `ComboBelow`, a type the boundary type builds by value.
	case beneath = "Beneath"
	/// On `ComboLive`, the roots' module's fill of a place the boundary type's tree holds.
	case insideFill = "InsideFill"
}

/// The feature a combination cell draws at its position.
enum GraphFuzzerCombinationRow: String, CaseIterable {
	/// An erased `@Instantiated(fulfilledByType:erasedToConcreteExistential:)` constant or `ErasedInstantiator`.
	case erased = "Erased"
	/// The host builds itself again through an instantiator.
	case builtAgain = "BuiltAgain"
	/// The host binds `comboTag` and builds `ComboStep` through an instantiator, which declares `comboTag` again,
	/// builds a reader of it, and builds the host again: a value declared again along a cycle.
	case declaredAgainAlongCycle = "DeclaredAgainAlongCycle"
	/// The host declares instantiators of `ComboRingA` and `ComboRingB` (and now and then `ComboRingC`), each of which
	/// receives the next one's: a loop of received instantiators.
	case receivedInstantiatorLoop = "ReceivedInstantiatorLoop"
	/// The host, a fulfiller or a type a fulfiller builds, calls the seam whose place the fill fills, or is a seam.
	case fulfillerSeam = "FulfillerSeam"
	/// The host builds a generic type through an extension's `instantiate(…)`, or an extension-based type.
	case genericOrExtension = "GenericOrExtension"
	/// The host is `@MainActor` with a `nonisolated` initializer, or every type of the graph is `@MainActor`.
	case actorIsolation = "ActorIsolation"
	/// The host receives a `LazilyInstantiated` (or `SendableLazilyInstantiated`) declared above its boundary, as the
	/// wrapper, its instance, or the optional wrapper only if available.
	case lazilyInstantiated = "LazilyInstantiated"
	/// The host builds `ComboMocked`, which has a hand-written mock (`mock`, or `customMock` through `customMockName`),
	/// and the root generates a mock.
	case handWrittenMock = "HandWrittenMock"
	/// The host's module lists it in `additionalMocksToGenerate`.
	case additionalMock = "AdditionalMock"
	/// The host builds `ComboFlagged`, declared inside a platform-conditioned or a flag-conditioned `#if` block.
	case conditionalCompilation = "ConditionalCompilation"
	/// The host receives an alias (`fulfilledByDependencyNamed:ofType:`) of `comboShared`, declared above its boundary,
	/// required or only if available.
	case sharedInstance = "SharedInstance"
	/// The host carries `generatedAttributes`, `generatedInitializerAttributes` or `mockAttributes`, with a mock.
	case generatedAttributes = "GeneratedAttributes"
	/// The host builds a type nested in a namespace enum's extension or in its own extension.
	case nestedType = "NestedType"
	/// The host forwards `comboId: Int`, so the type above it builds it through an instantiator.
	case forwardedValue = "ForwardedValue"
	/// The type above the host builds it twice, under two labels: one type on two routes.
	case twoRoutes = "TwoRoutes"
}

/// One cell of the combination matrix at one position: a case of `GraphFuzzerSeamDrawFeature` or
/// `GraphFuzzerPublicMockDrawFeature` named `featureName`.
struct GraphFuzzerCombinationCell: Hashable {
	let row: GraphFuzzerCombinationRow
	let column: GraphFuzzerCombinationColumn
	let position: GraphFuzzerCombinationPosition

	/// The name of the draw feature the cell is: `combination<Row><Column><Position>`.
	var featureName: String {
		"combination" + row.rawValue + column.rawValue + position.rawValue
	}
}

// MARK: - Draw

/// The combination corpora's graphs (`GraphFuzzerGeneratorFeature.combinationDraws`): each seed draws one cell, the seed's
/// remainder by the number of cells, alone, so that nearly every graph is accepted and judged and a cell gets ten judged
/// graphs in few seeds. Each cell draws its rolls from a stream of its own, seeded from the seed and the cell's name, and
/// one roll in two puts the column's tree beneath `ComboParent`, a type of the roots' module that only builds it, so that
/// the boundary type is not always the root's child. The root's file names the cell on a line of its own
/// (`marker`), from which `cell(drawnIn:)` reads it.
struct GraphFuzzerCombinationDraw {
	typealias TypeDeclaration = GraphFuzzerGenerator.TypeDeclaration
	typealias PropertyDeclaration = GraphFuzzerGenerator.PropertyDeclaration

	init(seed: UInt64, prefix: String, isSendableGraph: Bool, isMixedGraph: Bool) {
		self.seed = seed
		self.prefix = prefix
		self.isSendableGraph = isSendableGraph
		self.isMixedGraph = isMixedGraph
	}

	/// What begins the line naming a graph's cell.
	static let marker = "// combination draw: "

	/// The seam corpus's cells: each column's undrawn rows, at each position its scaffold has.
	static let seamCells: [GraphFuzzerCombinationCell] = {
		func cells(_ column: GraphFuzzerCombinationColumn, _ rows: [GraphFuzzerCombinationRow], positions: [GraphFuzzerCombinationPosition]) -> [GraphFuzzerCombinationCell] {
			rows.flatMap { row in positions.map { GraphFuzzerCombinationCell(row: row, column: column, position: $0) } }
		}
		let twoPositions: [GraphFuzzerCombinationPosition] = [.boundary, .beneath]
		let threePositions: [GraphFuzzerCombinationPosition] = [.boundary, .beneath, .insideFill]
		return cells(.placeInsideFill, [.builtAgain, .declaredAgainAlongCycle, .receivedInstantiatorLoop, .fulfillerSeam, .genericOrExtension, .actorIsolation, .handWrittenMock, .additionalMock, .conditionalCompilation, .sharedInstance, .generatedAttributes, .nestedType], positions: threePositions)
			+ cells(.innerSeam, [.erased, .declaredAgainAlongCycle, .receivedInstantiatorLoop, .genericOrExtension, .actorIsolation, .lazilyInstantiated, .handWrittenMock, .additionalMock, .conditionalCompilation, .generatedAttributes, .nestedType], positions: threePositions)
			+ cells(.innerSeam, [.fulfillerSeam], positions: [.insideFill])
			+ cells(.seamTree, [.erased, .handWrittenMock, .additionalMock, .generatedAttributes], positions: twoPositions)
			+ cells(.holeFill, [.fulfillerSeam, .actorIsolation, .handWrittenMock, .additionalMock, .conditionalCompilation, .generatedAttributes], positions: twoPositions)
	}()

	/// The public mock corpus's cells: the public mock column's undrawn rows, at each position its scaffold has. A
	/// forwarded value is not drawn on the fill, which a place builds by value, and the additional mock not on the
	/// `.public` type, whose mock is generated already; the two routes are the boundary type's.
	static let publicMockCells: [GraphFuzzerCombinationCell] = {
		func cells(_ rows: [GraphFuzzerCombinationRow], positions: [GraphFuzzerCombinationPosition]) -> [GraphFuzzerCombinationCell] {
			rows.flatMap { row in positions.map { GraphFuzzerCombinationCell(row: row, column: .publicMock, position: $0) } }
		}
		return cells([.builtAgain, .lazilyInstantiated, .receivedInstantiatorLoop, .genericOrExtension, .generatedAttributes, .sharedInstance], positions: [.boundary, .beneath, .insideFill])
			+ cells([.forwardedValue], positions: [.boundary, .beneath])
			+ cells([.additionalMock], positions: [.beneath, .insideFill])
			+ cells([.twoRoutes], positions: [.boundary])
	}()

	/// The cell `seed` draws in the seam corpus.
	static func seamCell(forSeed seed: UInt64) -> GraphFuzzerCombinationCell {
		seamCells[Int(seed % UInt64(seamCells.count))]
	}

	/// The cell `seed` draws in the public mock corpus.
	static func publicMockCell(forSeed seed: UInt64) -> GraphFuzzerCombinationCell {
		publicMockCells[Int(seed % UInt64(publicMockCells.count))]
	}

	/// The cell `fixture` draws, read from the line its root's file names it on, or `nil` for a graph of another corpus.
	static func cell(drawnIn fixture: GraphFuzzerFixture) -> GraphFuzzerCombinationCell? {
		for content in fixture.swiftFileContent {
			guard let range = content.range(of: marker) else { continue }
			let name = content[range.upperBound...].prefix { $0 != "\n" }
			return (seamCells + publicMockCells).first { $0.featureName == name }
		}
		return nil
	}

	/// The mask of the stream a cell draws its rolls from: FNV-1a over its name, so that each cell's rolls are its own.
	static func randomSeedMask(of cell: GraphFuzzerCombinationCell) -> UInt64 {
		var hash: UInt64 = 0xCBF29CE484222325
		for byte in cell.featureName.utf8 {
			hash = (hash ^ UInt64(byte)) &* 0x100000001B3
		}
		return hash
	}

	// MARK: Seam cells

	/// The seed's seam cell: its column's scaffold, with the row's feature drawn on the host its position names.
	mutating func seamDeclarations() -> [TypeDeclaration] {
		declarations(of: Self.seamCell(forSeed: seed))
	}

	/// The seed's public mock cell, drawn as `seamDeclarations()` draws a seam cell, or its known-right path: every
	/// initializer `public` and every `.public` mock `true`, so that the consumer's mock builds the type inline.
	mutating func publicMockDeclarations(isKnownRight: Bool) -> [TypeDeclaration] {
		var declarations = self.declarations(of: Self.publicMockCell(forSeed: seed))
		guard isKnownRight else { return declarations }
		for index in declarations.indices {
			declarations[index].initializerAccess = nil
			declarations[index].instantiableArguments = declarations[index].instantiableArguments.map { $0 == "generateMock: .public" ? "generateMock: true" : $0 }
		}
		return declarations
	}

	/// `cell`'s column's scaffold, with the row's feature drawn on the host its position names.
	private mutating func declarations(of cell: GraphFuzzerCombinationCell) -> [TypeDeclaration] {
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ Self.randomSeedMask(of: cell))
		// Every roll is made before any is read, so that each draws as it does whatever the others draw.
		let hasParent = random.percentChance(50)
		let wrapperRoll = random.percentChance(50)
		let variantRoll = random.integer(in: 0...99)
		let secondVariantRoll = random.integer(in: 0...99)
		let isSendableWrapper = isSendableGraph || (isMixedGraph && wrapperRoll)
		instantiator = isSendableWrapper ? "SendableInstantiator" : "Instantiator"
		erasedInstantiator = isSendableWrapper ? "SendableErasedInstantiator" : "ErasedInstantiator"
		lazilyInstantiated = isSendableWrapper ? "SendableLazilyInstantiated" : "LazilyInstantiated"

		var declarations = scaffold(of: cell.column, hasParent: hasParent)
		let hostName = name(ofHostAt: cell.position, in: cell.column)
		declarations = adding(cell.row, toHostNamed: hostName, column: cell.column, position: cell.position, variantRoll: variantRoll, secondVariantRoll: secondVariantRoll, to: declarations)
		if let rootIndex = declarations.firstIndex(where: { $0.name == nameOfRoot(in: cell.column) }) {
			declarations[rootIndex].precedingDeclarations.insert(Self.marker + cell.featureName, at: 0)
		}
		// A file imports every module beneath its own that the graph holds, as its module lists them all
		// (`GraphFuzzerOracle.toolOutcome(of:…)`): a fill in the roots' module names a protocol the inner seam's module declares.
		let presentModules = Set(declarations.compactMap(\.module))
		for index in declarations.indices {
			guard let module = declarations[index].module else { continue }
			declarations[index].imports += module.transitiveDependencies.filter { presentModules.contains($0) && !module.dependencies.contains($0) }.map(\.name)
		}
		return declarations
	}

	/// The column's types: `ComboRoot`, a root of the roots' module (`ComboApp`, a mocked type of the consumer's module, in
	/// the public mock column), builds `ComboHome` (through `ComboParent` when `hasParent`), and `ComboLive` fills the
	/// column's place of `ComboService` from that module.
	private func scaffold(of column: GraphFuzzerCombinationColumn, hasParent: Bool) -> [TypeDeclaration] {
		var home = type("ComboHome", .seamModule, arguments: ["generateDependencyTree: true"])
		var declarations = [TypeDeclaration]()
		switch column {
		case .publicMock:
			home = type("ComboHome", .seamModule, arguments: ["generateMock: .public"])
			// The consumer's module cannot build `ComboHome` inline, so its mock calls `ComboHome`'s.
			home.initializerAccess = .internal
			home.properties.append(place)
			home.additionalDeclarations.append(protocolDeclaration("ComboService"))
			declarations += [home, type("ComboBelow", .seamModule)]
		case .seamTree, .holeFill:
			home.properties.append(place)
			home.additionalDeclarations.append(protocolDeclaration("ComboService"))
			declarations.append(home)
			declarations.append(type("ComboBelow", column == .holeFill ? .samePackageCaller : .seamModule, fillsHole: column == .holeFill))
		case .placeInsideFill:
			var nest = type("ComboNest", .seamDependency, arguments: ["generateDependencyTree: true"], properties: [PropertyDeclaration(attribute: "@Instantiated", label: "comboNestService", type: "any \(name("ComboNestService"))")])
			nest.additionalDeclarations.append(protocolDeclaration("ComboNestService"))
			var nestImpl = type("ComboNestImpl", .seamModule, arguments: ["fulfillingAdditionalTypes: [\(name("ComboNestService")).self]"], properties: [place])
			nestImpl.additionalConformances.append(name("ComboNestService"))
			nestImpl.additionalDeclarations.append(protocolDeclaration("ComboService"))
			home.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "comboNest", type: nest.name))
			declarations += [home, nest, nestImpl, type("ComboBelow", .seamModule)]
		case .innerSeam:
			var inner = type("ComboInner", .seamDependency, arguments: ["generateDependencyTree: true"], properties: [place])
			inner.additionalDeclarations.append(protocolDeclaration("ComboService"))
			home.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "comboInner", type: inner.name))
			declarations += [home, inner, type("ComboBelow", .seamDependency)]
		}
		var live = type("ComboLive", .samePackageCaller, arguments: ["fulfillingAdditionalTypes: [\(name("ComboService")).self]"], fillsHole: column != .publicMock)
		live.additionalConformances.append(name("ComboService"))
		declarations.append(live)
		var root = column == .publicMock
			? type("ComboApp", .samePackageCaller, arguments: ["generateMock: true"])
			: type("ComboRoot", .samePackageCaller, arguments: ["isRoot: true"])
		if hasParent {
			root.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "comboParent", type: name("ComboParent")))
			declarations.append(type("ComboParent", .samePackageCaller, properties: [PropertyDeclaration(attribute: "@Instantiated", label: "comboHome", type: name("ComboHome"))]))
		} else {
			root.properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "comboHome", type: name("ComboHome")))
		}
		return [root] + declarations
	}

	/// The type the cell's feature is drawn on: the column's boundary type, `ComboBelow` beneath it, or `ComboLive`.
	private func name(ofHostAt position: GraphFuzzerCombinationPosition, in column: GraphFuzzerCombinationColumn) -> String {
		switch (position, column) {
		case (.boundary, .seamTree), (.boundary, .publicMock):
			name("ComboHome")
		case (.boundary, .holeFill), (.insideFill, _):
			name("ComboLive")
		case (.boundary, .placeInsideFill):
			name("ComboNestImpl")
		case (.boundary, .innerSeam):
			name("ComboInner")
		case (.beneath, _):
			name("ComboBelow")
		}
	}

	/// The type that builds the column's tree: `ComboApp`, whose mock is the public mock column's probe, or `ComboRoot`.
	private func nameOfRoot(in column: GraphFuzzerCombinationColumn) -> String {
		column == .publicMock ? name("ComboApp") : name("ComboRoot")
	}

	/// The type above the host's boundary that declares what the host receives: `ComboHome` where the boundary is beneath
	/// it, and the root otherwise. A fill of the inner seam's place reads the root's: a level of the seam that passes the
	/// place up holds none of what it binds before its call, so a fill reading `ComboHome`'s is rejected by design
	/// (`boundByPassingUpSeam`), and the cell would judge nothing.
	private func nameOfDeclarer(in column: GraphFuzzerCombinationColumn, position: GraphFuzzerCombinationPosition) -> String {
		switch (column, position) {
		case (.placeInsideFill, _), (.innerSeam, .boundary), (.innerSeam, .beneath):
			name("ComboHome")
		case (.innerSeam, .insideFill), (.seamTree, _), (.holeFill, _), (.publicMock, _):
			nameOfRoot(in: column)
		}
	}

	/// The seam whose place the host's fill fills, which a fulfiller that calls its own seam builds again.
	private func nameOfFilledSeam(hostName: String, in column: GraphFuzzerCombinationColumn) -> String {
		column == .placeInsideFill && hostName != name("ComboLive") ? name("ComboNest") : name("ComboHome")
	}

	/// `declarations` with `row` drawn on the type named `hostName`.
	private func adding(_ row: GraphFuzzerCombinationRow, toHostNamed hostName: String, column: GraphFuzzerCombinationColumn, position: GraphFuzzerCombinationPosition, variantRoll: Int, secondVariantRoll: Int, to declarations: [TypeDeclaration]) -> [TypeDeclaration] {
		var declarations = declarations
		guard let hostIndex = declarations.firstIndex(where: { $0.name == hostName }) else { return declarations }
		let host = declarations[hostIndex]
		let hostModule = host.module ?? .samePackageCaller
		let lowestModule = declarations.compactMap(\.module).min() ?? .seamModule
		// The host's boundary type builds `ComboBelow` only where the cell draws on it, so that every other cell's tree is as
		// small as its column.
		if hostName == name("ComboBelow"), let boundaryIndex = declarations.firstIndex(where: { $0.name == name(ofHostAt: .boundary, in: column) }) {
			declarations[boundaryIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "comboBelow", type: hostName))
		}
		/// A type of the host's module, filling a hole where the host does.
		func hostType(_ suffix: String, properties: [PropertyDeclaration] = [], arguments: [String] = []) -> TypeDeclaration {
			type(suffix, hostModule, arguments: arguments, properties: properties, fillsHole: host.fillsHole)
		}
		func addToHost(_ property: PropertyDeclaration) {
			declarations[hostIndex].properties.append(property)
		}
		let declarerIndex = declarations.firstIndex { $0.name == nameOfDeclarer(in: column, position: position) }
		switch row {
		case .erased:
			var concrete = hostType("ComboErased")
			let erasedName = name("AnyComboErased")
			concrete.additionalDeclarations.append("public final class \(erasedName)\(helperTypesAreSendable ? ": Sendable" : "") {\n\tpublic init(_ value: \(concrete.name)) {\n\t\tself.value = value\n\t}\n\n\tpublic let value: \(concrete.name)\n}")
			let attribute = "@Instantiated(fulfilledByType: \"\(concrete.name)\", erasedToConcreteExistential: true)"
			addToHost(variantRoll < 50
				? PropertyDeclaration(attribute: attribute, label: "comboErased", type: erasedName)
				: PropertyDeclaration(attribute: attribute, label: "comboErasedBuilder", type: "\(erasedInstantiator)<(), \(erasedName)>"))
			declarations.append(concrete)
		case .builtAgain:
			addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboAgainBuilder", type: "\(instantiator)<\(hostName)>"))
		case .declaredAgainAlongCycle:
			let tag = hostType("ComboTag")
			let reader = hostType("ComboReader", properties: [secondVariantRoll < 30
					? PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "comboTag", type: tag.name + "?")
					: PropertyDeclaration(attribute: "@Received", label: "comboTag", type: tag.name)])
			let step = hostType("ComboStep", properties: [
				PropertyDeclaration(attribute: "@Instantiated", label: "comboTag", type: tag.name),
				PropertyDeclaration(attribute: "@Instantiated", label: "comboReader", type: reader.name),
				PropertyDeclaration(attribute: "@Instantiated", label: "comboHostBuilder", type: "\(instantiator)<\(hostName)>"),
			])
			addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboTag", type: tag.name))
			addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboStepBuilder", type: "\(instantiator)<\(step.name)>"))
			declarations += [tag, reader, step]
		case .receivedInstantiatorLoop:
			let memberSuffixes = variantRoll < 30 ? ["ComboRingA", "ComboRingB", "ComboRingC"] : ["ComboRingA", "ComboRingB"]
			func builderLabel(_ suffix: String) -> String {
				"comboRing\(suffix.dropFirst("ComboRing".count))Builder"
			}
			for (index, suffix) in memberSuffixes.enumerated() {
				let next = memberSuffixes[(index + 1) % memberSuffixes.count]
				declarations.append(hostType(suffix, properties: [PropertyDeclaration(attribute: "@Received", label: builderLabel(next), type: "\(instantiator)<\(name(next))>")]))
			}
			for suffix in memberSuffixes {
				addToHost(PropertyDeclaration(attribute: "@Instantiated", label: builderLabel(suffix), type: "\(instantiator)<\(name(suffix))>"))
			}
			if secondVariantRoll < 30 {
				addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboRingA", type: name("ComboRingA")))
			}
		case .fulfillerSeam:
			// Three draws in twenty make the host a seam, which, where the host holds a place, is D3's shape (a fulfiller
			// that is a seam with a place it cannot fill generates code that does not compile), so that the rest judge.
			if variantRoll < 15 {
				declarations[hostIndex].instantiableArguments = Self.inserting("generateDependencyTree: true", into: host.instantiableArguments)
			} else {
				addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboOwnSeamBuilder", type: "\(instantiator)<\(nameOfFilledSeam(hostName: hostName, in: column))>"))
			}
		case .genericOrExtension:
			var token = hostType("ComboToken")
			let tokenName = token.name
			let uncheckedSendable = helperTypesAreSendable ? ": @unchecked Sendable" : ""
			if variantRoll < 50 {
				let boxName = name("ComboBox")
				token.additionalDeclarations.append("public final class \(boxName)<Value>\(uncheckedSendable) {\n\tpublic init(value: Value) {\n\t\tself.value = value\n\t}\n\n\tpublic let value: Value\n}")
				token.additionalDeclarations.append("@Instantiable\nextension \(boxName): Instantiable {\n\tpublic static func instantiate(comboToken: \(tokenName)) -> \(boxName)<\(tokenName)> {\n\t\t\(boxName)<\(tokenName)>(value: comboToken)\n\t}\n}")
				addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboToken", type: tokenName))
				addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboBox", type: "\(boxName)<\(tokenName)>"))
			} else {
				let madeName = name("ComboMade")
				token.additionalDeclarations.append("public final class \(madeName)\(uncheckedSendable) {\n\tpublic init(comboToken: \(tokenName)) {\n\t\tself.comboToken = comboToken\n\t}\n\n\tpublic let comboToken: \(tokenName)\n}")
				token.additionalDeclarations.append("@Instantiable\nextension \(madeName): Instantiable {\n\tpublic static func instantiate(comboToken: \(tokenName)) -> \(madeName) {\n\t\t\(madeName)(comboToken: comboToken)\n\t}\n}")
				addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboToken", type: tokenName))
				addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboMade", type: madeName))
			}
			declarations.append(token)
		case .actorIsolation:
			// A `nonisolated` initializer stores its properties from outside the main actor, which Swift 6 allows only for
			// `Sendable` values, so only a graph whose types are `Sendable` draws it.
			if variantRoll < 50, helperTypesAreSendable {
				declarations[hostIndex].isMainActor = true
				declarations[hostIndex].initializerIsNonisolated = true
				declarations[hostIndex].additionalConformances.removeAll { $0 == "@unchecked Sendable" }
			} else {
				for index in declarations.indices {
					declarations[index].isMainActor = true
					declarations[index].additionalConformances.removeAll { $0 == "@unchecked Sendable" }
				}
			}
		case .lazilyInstantiated:
			let lazy = type("ComboLazy", lowestModule)
			if let declarerIndex {
				declarations[declarerIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "comboLazy", type: "\(lazilyInstantiated)<\(lazy.name)>"))
			}
			// A public mock's fill reads only what the mocked type's levels hold, so the mocked type receives the wrapper too.
			if column == .publicMock, position == .insideFill, let homeIndex = declarations.firstIndex(where: { $0.name == name("ComboHome") }) {
				declarations[homeIndex].properties.append(PropertyDeclaration(attribute: "@Received", label: "comboLazy", type: "\(lazilyInstantiated)<\(lazy.name)>"))
			}
			let receive: PropertyDeclaration = switch variantRoll {
			case 0..<40: PropertyDeclaration(attribute: "@Received", label: "comboLazy", type: "\(lazilyInstantiated)<\(lazy.name)>")
			case 40..<70: PropertyDeclaration(attribute: "@Received", label: "comboLazy", type: lazy.name)
			default: PropertyDeclaration(attribute: "@Received(onlyIfAvailable: true)", label: "comboLazy", type: "\(lazilyInstantiated)<\(lazy.name)>?")
			}
			addToHost(receive)
			declarations.append(lazy)
		case .handWrittenMock:
			var mocked = hostType("ComboMocked")
			if variantRoll < 50 {
				mocked.handWrittenMockName = "mock"
			} else {
				mocked.instantiableArguments = ["generateMock: true", "customMockName: \"customMock\""]
				mocked.handWrittenMockName = "customMock"
			}
			addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboMocked", type: mocked.name))
			declarations.append(mocked)
			if let rootIndex = declarations.firstIndex(where: { $0.name == name("ComboRoot") }) {
				declarations[rootIndex].instantiableArguments = Self.inserting("generateMock: true", into: declarations[rootIndex].instantiableArguments)
			}
		case .additionalMock:
			declarations[hostIndex].additionalDeclarations.append("#SafeDIConfiguration(additionalMocksToGenerate: [\"\(hostName)\"])")
		case .conditionalCompilation:
			let flaggedName = name("ComboFlagged")
			let condition = variantRoll < 50 ? "canImport(Foundation)" : "!COMBO_FLAG"
			let conformance = isSendableGraph ? ", Sendable" : isMixedGraph ? ", @unchecked Sendable" : ""
			declarations[hostIndex].additionalDeclarations.append("#if \(condition)\n@Instantiable\npublic final class \(flaggedName): Instantiable\(conformance) {\n\tpublic init() {}\n}\n#endif")
			addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboFlagged", type: flaggedName))
		case .sharedInstance:
			let shared = type("ComboShared", lowestModule)
			if let declarerIndex {
				declarations[declarerIndex].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: "comboShared", type: shared.name))
			}
			// A public mock's fill reads only what the mocked type's levels hold, so the mocked type receives it too.
			if column == .publicMock, position == .insideFill, let homeIndex = declarations.firstIndex(where: { $0.name == name("ComboHome") }) {
				declarations[homeIndex].properties.append(PropertyDeclaration(attribute: "@Received", label: "comboShared", type: shared.name))
			}
			addToHost(variantRoll < 30
				? PropertyDeclaration(attribute: "@Received(fulfilledByDependencyNamed: \"comboShared\", ofType: \(shared.name).self, onlyIfAvailable: true)", label: "comboSharedAlias", type: shared.name + "?")
				: PropertyDeclaration(attribute: "@Received(fulfilledByDependencyNamed: \"comboShared\", ofType: \(shared.name).self)", label: "comboSharedAlias", type: shared.name))
			declarations.append(shared)
		case .generatedAttributes:
			let attribute = "\"@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)\""
			let isSeam = host.instantiableArguments.contains("generateDependencyTree: true")
			var arguments = host.instantiableArguments
			if isSeam, variantRoll < 34 {
				arguments = Self.inserting("generatedInitializerAttributes: \(attribute)", into: arguments)
			} else if variantRoll < 67 {
				arguments = Self.inserting("generatedAttributes: \(attribute)", into: Self.inserting("generateMock: true", into: arguments))
			} else {
				arguments = Self.inserting("mockAttributes: \(attribute)", into: Self.inserting("generateMock: true", into: arguments))
			}
			declarations[hostIndex].instantiableArguments = arguments
		case .nestedType:
			var nested = hostType("ComboNested")
			let enclosingName: String
			if variantRoll < 50 {
				enclosingName = name("ComboSpace")
				declarations[hostIndex].additionalDeclarations.append("public enum \(enclosingName) {}")
			} else {
				enclosingName = hostName
			}
			nested.enclosingExtension = "extension \(enclosingName)"
			addToHost(PropertyDeclaration(attribute: "@Instantiated", label: "comboNested", type: "\(enclosingName).\(nested.name)"))
			declarations.append(nested)
		case .forwardedValue:
			declarations[hostIndex].properties.insert(PropertyDeclaration(attribute: "@Forwarded", label: "comboId", type: "Int"), at: 0)
			// A type that forwards a value is built through an instantiator.
			for index in declarations.indices {
				declarations[index].properties = declarations[index].properties.map { property in
					guard property.attribute == "@Instantiated", property.type == hostName else { return property }
					return PropertyDeclaration(attribute: "@Instantiated", label: property.label + "Builder", type: "\(instantiator)<\(hostName)>")
				}
			}
		case .twoRoutes:
			for index in declarations.indices {
				guard let property = declarations[index].properties.first(where: { $0.attribute == "@Instantiated" && $0.type == hostName }) else { continue }
				declarations[index].properties.append(PropertyDeclaration(attribute: "@Instantiated", label: property.label + "Second", type: hostName))
			}
		}
		return declarations
	}

	// MARK: Helpers

	private let seed: UInt64
	private let prefix: String
	private let isSendableGraph: Bool
	private let isMixedGraph: Bool
	private var instantiator = "Instantiator"
	private var erasedInstantiator = "ErasedInstantiator"
	private var lazilyInstantiated = "LazilyInstantiated"

	/// Whether the graph's plain helper types are `Sendable`, as its `Sendable` wrappers require.
	private var helperTypesAreSendable: Bool {
		isSendableGraph || isMixedGraph
	}

	/// The place every column holds: `comboService: any ComboService`.
	private var place: PropertyDeclaration {
		PropertyDeclaration(attribute: "@Instantiated", label: "comboService", type: "any \(name("ComboService"))")
	}

	private func name(_ suffix: String) -> String {
		prefix + suffix
	}

	private func protocolDeclaration(_ suffix: String) -> String {
		"public protocol \(name(suffix))\(helperTypesAreSendable ? ": Sendable" : "") {}"
	}

	private func type(_ suffix: String, _ module: GraphFuzzerModule, arguments: [String] = [], properties: [PropertyDeclaration] = [], fillsHole: Bool = false) -> TypeDeclaration {
		var declaration = TypeDeclaration(name: name(suffix), instantiableArguments: arguments, properties: properties, declaresHelperTypes: false, additionalConformances: isMixedGraph ? ["@unchecked Sendable"] : [])
		declaration.module = module
		declaration.fillsHole = fillsHole
		return declaration
	}

	/// The order `@Instantiable` takes its arguments in.
	private static let argumentOrder = ["isRoot", "generateDependencyTree", "fulfillingAdditionalTypes", "conformsElsewhere", "mockOnly", "generatedInitializerAttributes", "mockAttributes", "generatedAttributes", "generateMock", "customMockName"]

	/// `arguments` with `argument` in the order `@Instantiable` takes them, unless an argument of its label is there.
	static func inserting(_ argument: String, into arguments: [String]) -> [String] {
		func label(_ argument: String) -> String {
			String(argument.prefix { $0 != ":" })
		}
		guard !arguments.contains(where: { label($0) == label(argument) }) else { return arguments }
		let rank = argumentOrder.firstIndex(of: label(argument)) ?? argumentOrder.count
		let index = arguments.firstIndex { (argumentOrder.firstIndex(of: label($0)) ?? argumentOrder.count) > rank } ?? arguments.count
		var arguments = arguments
		arguments.insert(argument, at: index)
		return arguments
	}
}
