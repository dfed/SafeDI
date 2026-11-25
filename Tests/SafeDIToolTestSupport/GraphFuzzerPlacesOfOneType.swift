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

/// The roll of one type built at two places (`SafeDIToolGraphFuzzerPlacesOfOneTypeTests`): a graph whose root reaches
/// `Shared` through two branches, each branch a chain of one to three types, the last of which builds `Shared` by value
/// or through an `Instantiator`. `Shared` receives `token`, which each branch's chain or the root instantiates, so the
/// two places are handed one `Token` only where the root holds it. Each place is drawn on its own:
///
/// - **Hole levels.** In a third of the graphs the branches sit inside a seam of module `Feature`, where `Shared` is
///   a hole (`any Sharing`) that `App`'s `SharedImpl` fills, so each place's fill is handed the `token` of its own
///   level, at the chain's depth the draw chose.
/// - **Cycle laps.** A third of the branches end in a lap: the last type also instantiates `Instantiator<Self>`, so
///   the place is built again on every lap, each lap with the token the lap or a type above it declares.
/// - **Overrides.** A branch that ends in no lap is handed, in the mock probe, its own override of `Shared`: the
///   `tag` default, a builder, both, or nothing, each place another value.
///
/// The probes build the root, through production and through `mock()` with the drawn overrides, and compare each
/// with a function written out by hand from the drawn graph (`knownRightProduction`, `knownRightMock`), which builds
/// each place with its own value. A generator that shares one builder per type across places must keep every place's
/// token, tag, instance and lap apart for the two to agree.
struct GraphFuzzerPlacesOfOneTypeGraph {
	init(seed: UInt64) {
		self.seed = seed
		var random = GraphFuzzerRandomNumberGenerator(seed: seed ^ 0x534841524544504C)
		isInSeam = random.percentChance(34)
		branches = (1...2).map { index in
			let depth = random.integer(in: 1...3)
			let endsInLap = random.percentChance(34)
			// The level, from 0 at the chain's first type, whose type instantiates `token`; `nil` for the root.
			let tokenLevel: Int? = random.percentChance(30) ? nil : random.integer(in: 0...(depth - 1))
			let isHeldInInstantiator = random.percentChance(25)
			let override: Override = endsInLap ? .none : random.element(of: Override.allCases)
			return Branch(index: index, depth: depth, endsInLap: endsInLap, tokenLevel: tokenLevel, isHeldInInstantiator: isHeldInInstantiator, override: override, tag: index * 10 + random.integer(in: 1...9))
		}
	}

	/// How the mock probe overrides a place.
	enum Override: CaseIterable, Equatable {
		case none
		/// `.init(tag: <tag>)`.
		case tag
		/// `.init({ token, leaf, tag in Shared(token: token, leaf: leaf, tag: tag + 100) })`.
		case builder
		/// Both.
		case tagAndBuilder
	}

	struct Branch: Equatable {
		/// 1 or 2.
		let index: Int
		/// How many types the chain holds, the last of which builds the place.
		let depth: Int
		/// Whether the last type also instantiates `Instantiator<Self>`, so each lap builds the place again.
		let endsInLap: Bool
		/// The chain level whose type instantiates `token`, or `nil` where the root does.
		let tokenLevel: Int?
		/// Whether the place is `sharedBuilder: Instantiator<Shared>` rather than `shared: Shared`.
		let isHeldInInstantiator: Bool
		let override: Override
		/// The tag the override passes.
		let tag: Int

		/// The label of the branch's first property, on the root or seam.
		var label: String {
			index == 1 ? "one" : "two"
		}

		var placeLabel: String {
			isHeldInInstantiator ? "sharedBuilder" : "shared"
		}
	}

	let seed: UInt64
	let isInSeam: Bool
	let branches: [Branch]

	var prefix: String {
		"P\(seed)_"
	}

	var rootHoldsToken: Bool {
		branches.contains { $0.tokenLevel == nil }
	}

	/// The type of a chain level.
	func typeName(of branch: Branch, level: Int) -> String {
		"\(prefix)\(branch.label.capitalized)\(level)"
	}

	/// The type the place's property names: the concrete type in one module, the protocol a hole fills in a seam.
	var placeType: String {
		isInSeam ? "any \(prefix)Sharing" : "\(prefix)Shared"
	}

	/// The wrapper of a place held in an instantiator: `Instantiator` needs an `Instantiable` type, so a hole's place is
	/// held in an erased instantiator of the protocol.
	var placeBuilderType: String {
		isInSeam ? "ErasedInstantiator<(), \(placeType)>" : "Instantiator<\(placeType)>"
	}

	/// The type that builds the place.
	var sharedTypeName: String {
		isInSeam ? "\(prefix)SharedImpl" : "\(prefix)Shared"
	}

	// MARK: Fixture

	/// The files of the module that holds the seam and the chains, or of the one module; `Feature` in a seam graph.
	var featureFiles: [String: String] {
		var files = [String: String]()
		files["\(prefix)Token.swift"] = Self.type(named: "\(prefix)Token", declarations: [])
		files["\(prefix)Leaf.swift"] = Self.type(named: "\(prefix)Leaf", declarations: [])
		if isInSeam {
			files["\(prefix)Sharing.swift"] = "public protocol \(prefix)Sharing: AnyObject {}\n"
			files["\(prefix)Seam.swift"] = Self.type(
				named: "\(prefix)Seam",
				attribute: "@Instantiable(generateDependencyTree: true)",
				declarations: branches.map { "@Instantiated public let \($0.label): \(typeName(of: $0, level: 0))" },
			)
		} else {
			files["\(sharedTypeName).swift"] = sharedDeclaration(attribute: "@Instantiable", conformance: "")
		}
		for branch in branches {
			for level in 0..<branch.depth {
				var declarations = [String]()
				if branch.tokenLevel == level {
					declarations.append("@Instantiated public let token: \(prefix)Token")
				}
				if level == branch.depth - 1 {
					declarations.append(branch.isHeldInInstantiator
						? "\(isInSeam ? "@Instantiated(fulfilledByType: \"\(sharedTypeName)\")" : "@Instantiated") public let sharedBuilder: \(placeBuilderType)"
						: "@Instantiated public let shared: \(placeType)")
					if branch.endsInLap {
						declarations.append("@Instantiated public let nextLapBuilder: Instantiator<\(typeName(of: branch, level: level))>")
					}
				} else {
					declarations.append("@Instantiated public let next: \(typeName(of: branch, level: level + 1))")
				}
				files["\(typeName(of: branch, level: level)).swift"] = Self.type(named: typeName(of: branch, level: level), declarations: declarations)
			}
		}
		return files
	}

	/// The files of `App`, which declares the root and the known-right functions, in a seam graph; in one module,
	/// these join `featureFiles`.
	var appFiles: [String: String] {
		let importLine = isInSeam ? "import Feature\n\n" : ""
		var files = [String: String]()
		var rootDeclarations = [String]()
		if rootHoldsToken {
			rootDeclarations.append("@Instantiated public let token: \(prefix)Token")
		}
		if isInSeam {
			rootDeclarations.append("@Instantiated public let seam: \(prefix)Seam")
			files["\(sharedTypeName).swift"] = importLine + sharedDeclaration(attribute: "@Instantiable(fulfillingAdditionalTypes: [\(prefix)Sharing.self])", conformance: ", \(prefix)Sharing")
		} else {
			rootDeclarations += branches.map { "@Instantiated public let \($0.label): \(typeName(of: $0, level: 0))" }
		}
		files["\(prefix)Root.swift"] = importLine + Self.type(named: "\(prefix)Root", attribute: "@Instantiable(isRoot: true, generateMock: true)", declarations: rootDeclarations)
		files["\(prefix)KnownRight.swift"] = importLine + knownRightFunctions
		return files
	}

	/// Every file, for a graph in one module.
	var allFiles: [String: String] {
		featureFiles.merging(appFiles) { first, _ in first }
	}

	private func sharedDeclaration(attribute: String, conformance: String) -> String {
		"""
		\(attribute)
		public final class \(sharedTypeName): Instantiable\(conformance) {
		    public init(token: \(prefix)Token, leaf: \(prefix)Leaf, tag: Int = 0) {
		        self.token = token
		        self.leaf = leaf
		        self.tag = tag
		    }

		    @Received public let token: \(prefix)Token
		    @Instantiated public let leaf: \(prefix)Leaf
		    public let tag: Int
		}

		"""
	}

	private static func type(named name: String, attribute: String = "@Instantiable", declarations: [String]) -> String {
		let properties = declarations.map { declaration -> (label: String, type: String) in
			let property = declaration[declaration.range(of: " let ")!.upperBound...]
			return (String(property.prefix { $0 != ":" }), property.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces))
		}
		let initializer = properties.isEmpty
			? "public init() {}"
			: "public init(\(properties.map { "\($0.label): \($0.type)" }.joined(separator: ", "))) {\n" + properties.map { "        self.\($0.label) = \($0.label)" }.joined(separator: "\n") + "\n    }"
		return """
		\(attribute)
		public final class \(name): Instantiable {
		    \(initializer)
		\(declarations.map { "\n    \($0)" }.joined())
		}

		"""
	}

	// MARK: Probes

	/// What `mock()` is passed: each branch's override of its place, nested along its chain.
	var mockExpression: String {
		var fields = [String]()
		for branch in branches {
			let configuration: String? = switch branch.override {
			case .none:
				nil
			case .tag:
				".init(tag: \(branch.tag))"
			case .builder:
				".init({ token, leaf, tag in \(sharedTypeName)(token: token, leaf: leaf, tag: tag + 100) })"
			case .tagAndBuilder:
				".init(tag: \(branch.tag), { token, leaf, tag in \(sharedTypeName)(token: token, leaf: leaf, tag: tag + 100) })"
			}
			guard var nested = configuration else { continue }
			nested = "\(branch.placeLabel): \(nested)"
			for _ in 1..<branch.depth {
				nested = "next: .init(\(nested))"
			}
			fields.append("\(branch.label): .init(\(nested))")
		}
		let overrides = isInSeam
			? (fields.isEmpty ? [] : ["seam: .init(\(fields.joined(separator: ", ")))"])
			: fields
		return overrides.isEmpty ? "\(prefix)Root.mock()" : "\(prefix)Root.mock(safeDIOverrides: .init(\(overrides.joined(separator: ", "))))"
	}

	var probePairs: [DifferentialValueProbePair] {
		[
			DifferentialValueProbePair(name: "\(prefix)Root() against hand-built", featureExpression: "\(prefix)Root()", knownRightExpression: "\(prefix)knownRightProduction()"),
			DifferentialValueProbePair(name: "\(mockExpression) against hand-built", featureExpression: mockExpression, knownRightExpression: "\(prefix)knownRightMock()"),
		]
	}

	// MARK: Known right

	/// The branch whose override a mock that merges places applies everywhere: the first that has one.
	private var mergingBranch: Branch? {
		branches.first { $0.override != .none }
	}

	private var mergedOverride: Override {
		mergingBranch?.override ?? .none
	}

	private func mergedTagSource(for branch: Branch, suffix: String) -> Branch {
		suffix == "MockMergingPlaces" ? mergingBranch ?? branch : branch
	}

	/// Whether a mock that merged the places would build other values than the drawn overrides ask for: the two
	/// branches' overrides differ, and the merged override reaches a place that takes no other.
	var mergingPlacesChangesMockValues: Bool {
		branches.contains { !$0.endsInLap && ($0.override != mergedOverride || ($0.override != .none && $0.override != .builder && $0.tag != mergingBranch?.tag)) }
	}

	/// The functions that build the root by hand: each chain level a function taking the token above it, so each lap
	/// calls its own type's function again.
	private var knownRightFunctions: String {
		var lines = [String]()
		for (suffix, overrideOf) in [
			("Production", { (_: Branch) in Override.none }),
			("Mock", { (branch: Branch) in branch.override }),
			// The values a mock builds that keys its overrides by type rather than by place: every place of `Shared`
			// takes the override of the first branch that has one, as one builder shared by every place would.
			("MockMergingPlaces", { (_: Branch) in mergedOverride }),
		] as [(String, (Branch) -> Override)] {
			let isMock = suffix != "Production"
			var rootArguments = [String]()
			var body = [String]()
			if rootHoldsToken {
				body.append("    let token = \(prefix)Token()")
				rootArguments.append("token: token")
			}
			let branchArguments = branches.map { "\($0.label): \(prefix)knownRight\(suffix)_\(typeName(of: $0, level: 0).dropFirst(prefix.count))(token: \(rootHoldsToken ? "token" : "nil"))" }
			if isInSeam {
				rootArguments.append("seam: \(prefix)Seam(\(branchArguments.joined(separator: ", ")))")
			} else {
				rootArguments += branchArguments
			}
			lines.append("public func \(prefix)knownRight\(suffix)() -> \(prefix)Root {\n\(body.map { $0 + "\n" }.joined())    return \(prefix)Root(\(rootArguments.joined(separator: ", ")))\n}\n")
			for branch in branches {
				for level in 0..<branch.depth {
					let name = typeName(of: branch, level: level)
					var functionBody = [String]()
					var arguments = [String]()
					if branch.tokenLevel == level {
						functionBody.append("    let token: \(prefix)Token? = \(prefix)Token()")
						arguments.append("token: token!")
					}
					let token = "token!"
					if level == branch.depth - 1 {
						let override = isMock && !branch.endsInLap ? overrideOf(branch) : .none
						let tag = switch override {
						case .none: 0
						case .tag: mergedTagSource(for: branch, suffix: suffix).tag
						case .builder: 100
						case .tagAndBuilder: mergedTagSource(for: branch, suffix: suffix).tag + 100
						}
						let construction = "\(sharedTypeName)(token: \(token), leaf: \(prefix)Leaf(), tag: \(tag))"
						arguments.append(branch.isHeldInInstantiator
							? "sharedBuilder: \(placeBuilderType) { \(construction) }"
							: "shared: \(construction)")
						if branch.endsInLap {
							let passed = branch.tokenLevel == level ? "nil" : "token"
							arguments.append("nextLapBuilder: Instantiator<\(name)> { \(prefix)knownRight\(suffix)_\(name.dropFirst(prefix.count))(token: \(passed)) }")
						}
					} else {
						arguments.append("next: \(prefix)knownRight\(suffix)_\(typeName(of: branch, level: level + 1).dropFirst(prefix.count))(token: token)")
					}
					lines.append("public func \(prefix)knownRight\(suffix)_\(name.dropFirst(prefix.count))(token: \(prefix)Token?) -> \(name) {\n\(functionBody.map { $0 + "\n" }.joined())    return \(name)(\(arguments.joined(separator: ", ")))\n}\n")
				}
			}
		}
		return lines.joined(separator: "\n")
	}
}
