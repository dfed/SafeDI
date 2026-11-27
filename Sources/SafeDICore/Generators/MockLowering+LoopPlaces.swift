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
/// A loop of builders as production records it (`ScopeGenerator.LoopRebinding`): each member is a built place, whose
/// function begins with a closer on the builder function of each member its tree receives (`rebindsLoopMember`), which the
/// type key resolves among the statements of the level that declares the loop.
///
/// Every turn of a loop reads the overrides of the members its level declares, however deep the turn, so a closer hands
/// the member it rebinds the configuration its level hands that member: its field of the level's configuration. A member's
/// function cannot see its level's configuration, so it takes it, beside its own, as one parameter, which its level hands
/// and each of its closers hands on. One parameter for the level, never one per member, keeps a loop of n members at a
/// fixed number of parameters per function, where a parameter per member it reaches would give each of n functions n.
/// A level's configuration that cannot cross into a `@Sendable` function, `mock()`'s `safeDIOverrides` among them, around
/// members built in `@Sendable` functions, is the one exception: the closures of their `Sendable` wrappers would capture
/// it, so each member's function takes the configuration of each member its closers reach instead, each of which is `Sendable`, since a member built in a
/// `@Sendable` function is configured in a `Sendable` scope (`sendableConfigurationTypeNames(ofMockRootOf:)`). Such a
/// loop of n members, every one reaching every other, takes n parameters in each of its n functions, and each function
/// begins with a closer per member it receives, each of which hands n arguments, so the mock's text grows with the cube
/// of the loop: 4.7 MB at 32 members, where the walk writes 132 KB. A known gap, which ends where a level's
/// configuration can be read in a `@Sendable` function without capturing what is not `Sendable`.
/// These are passed arguments, as the nearest configurations a cycle's closers hand are
/// (`MockLowering.NearestConfigurations`), with two differences: they are never optional, since the level that declares a
/// loop declares a field for each member, and they never depend on the lap, since every turn hands on what the level
/// handed the first. A loop the mock root declares reads `mock()`'s `safeDIOverrides`, which every function sees, so its
/// members take no level parameter, unless they are built in `@Sendable` functions.
extension MockLowering.Walk {
	/// The closers that begin `generator`'s builder function, a member of a loop of builders the walk's level declares: one
	/// on the function of each member of the level's loops its tree receives, in the order the walk writes their
	/// rebindings, with the path of the member each closes on; a rename the level declares of a member is bound as the
	/// rename's own type, wrapping the function of the member it renames. `nil` where a rebinding hands a `_received`
	/// function, or the member's own builder function with its cycle parameters, or rebinds a member the level binds under
	/// a name apart from its label.
	func loopRebindings(of generator: ScopeGenerator) -> [MockLowering.LoopRebindingCloser]? {
		var rebindings = [MockLowering.LoopRebindingCloser]()
		for property in generator.reboundProperties {
			guard let member = loopMembers[property] else { continue }
			// A rename wraps the function of the member it renames, bound as the rename's own type.
			guard member.receivedFunctionName == nil,
			      member.bindingName == property.label,
			      let memberPath = loopMemberPaths[member.renamedProperty ?? property]
			else { return nil }
			rebindings.append(MockLowering.LoopRebindingCloser(
				record: ClosingPlaceRecord(
					property: member.rename ?? property,
					isErased: member.isErased,
					isExtension: member.isExtension,
					closedOnFunctionName: member.builderFunctionName,
					forwardedProperties: member.forwardedProperties,
					cycleArguments: [],
					rebindsLoopMember: true,
				),
				memberPath: memberPath,
			))
		}
		return rebindings
	}

	/// The configuration of each member of a loop of builders whose function the walk recorded, by its path, as
	/// `rebindingCodes(of:…)` and `handLevelConfiguration(of:toBuiltPlaceAt:)` hand it. A member is left out where the walk
	/// recorded no function for it, such as a call of another module's public mock, or where its level's configuration has
	/// no field for it, and so is every member a closer of whose closes on one left out: its place keeps the walk's body.
	mutating func loopMemberConfigurations() -> [[Int]: MockLowering.LoopMemberConfiguration] {
		guard !loopRebindings.isEmpty else { return [:] }
		var memberPaths = Set<[Int]>()
		for (path, rebindings) in loopRebindings {
			memberPaths.insert(path)
			memberPaths.formUnion(rebindings.map(\.memberPath))
		}
		var configurations = [[Int]: MockLowering.LoopMemberConfiguration]()
		// In the order of the paths, so that the names the root's table claims follow the tree, never a set's order.
		for path in memberPaths.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
			guard let call = builtPlaceCalls[path],
			      call.inputs.hasFunction,
			      let context = builtPlaceConfigurationContexts[path],
			      let levelRead = context.parentConfiguration,
			      let own = MockLowering.passedArguments(
			      	ofBuiltPlaceTaking: configurationParameter(of: call.nodeConfiguration),
			      	label: context.fieldName,
			      	parentConfiguration: levelRead,
			      	nearestIsProvided: context.nearestIsProvided,
			      	staysOutsideSendableFunctions: staysOutsideSendableFunctions(ofConfigurationOf: call.nodeConfiguration),
			      ).first
			else { continue }
			let level: PassedArgument?
			if levelRead == MockLowering.mockOverridesRead {
				level = nil
			} else {
				guard let levelCall = builtPlaceCalls[Array(path.dropLast())] else { continue }
				let levelNode = levelCall.nodeConfiguration
				level = PassedArgument(
					parameterName: configurationParameterNames.name(ofLoopLevelConfigurationOf: levelNode.instantiable.concreteInstantiable, builtWithHandWrittenMock: levelNode.usesMockInitializer),
					type: configurationParameter(of: levelNode).type,
					value: levelRead,
					staysOutsideSendableFunctions: staysOutsideSendableFunctions(ofConfigurationOf: levelNode),
				)
			}
			configurations[path] = MockLowering.LoopMemberConfiguration(
				own: own,
				fieldName: context.fieldName,
				levelRead: levelRead,
				level: level,
				memberParameterName: configurationParameterNames.name(ofMemberConfigurationLabeled: context.fieldName),
				reachedPaths: [],
				handsMembers: false,
			)
		}
		// The loops whose level's configuration cannot cross into the `@Sendable` functions of its members, by the level's
		// path: their members take the configurations of the members they reach in its place.
		var levelsHandingMembers = Set<[Int]>()
		for (path, configuration) in configurations {
			// `mock()`'s `safeDIOverrides` is read into locals before every `@Sendable` function, as the walk reads it.
			if configuration.level?.staysOutsideSendableFunctions ?? true, builtPlaceCalls[path]?.generator.buildsInSendableFunction == true {
				levelsHandingMembers.insert(Array(path.dropLast()))
			}
		}
		if !levelsHandingMembers.isEmpty {
			// The members each member's calls reach, its own left out: the fixed point of what each closer's member reaches.
			var reached = [[Int]: Set<[Int]>]()
			for (path, rebindings) in loopRebindings where levelsHandingMembers.contains(Array(path.dropLast())) {
				reached[path] = Set(rebindings.map(\.memberPath))
			}
			var changed = true
			while changed {
				changed = false
				for (path, paths) in reached {
					var grown = paths
					for memberPath in paths {
						grown.formUnion(reached[memberPath, default: []])
					}
					grown.remove(path)
					if grown != paths {
						reached[path] = grown
						changed = true
					}
				}
			}
			for path in Array(configurations.keys) where levelsHandingMembers.contains(Array(path.dropLast())) {
				configurations[path]?.level = nil
				configurations[path]?.handsMembers = true
				configurations[path]?.reachedPaths = reached[path, default: []].sorted { $0.lexicographicallyPrecedes($1) }
			}
		}
		// A member a closer of whose closes on a member left out is left out too.
		var removed = true
		while removed {
			removed = false
			for (path, rebindings) in loopRebindings where configurations[path] != nil && !rebindings.allSatisfy({ configurations[$0.memberPath] != nil }) {
				configurations[path] = nil
				removed = true
			}
		}
		return configurations
	}

	/// Whether the configuration a place of `node` reads cannot cross into a `@Sendable` function, as
	/// `relateConfiguration(ofBuiltPlaceAt:of:)` hands it.
	func staysOutsideSendableFunctions(ofConfigurationOf node: MockLowering.NodeConfiguration) -> Bool {
		node.hasConfiguration ? !sendableConfigurationTypeNames.contains(node.instantiable.concreteInstantiable.asSource) : !node.requiresSendable
	}

	/// The closers that begin the function of the loop member at `path`, `rebindings`, each handing the member it rebinds
	/// its field of the level's configuration, read from what the function at `path` takes (`configuration`), and the
	/// level's configuration itself, and `nearestArguments`, the nearest configurations of a cycle the rebound member's
	/// function takes, by that member's path.
	static func rebindingCodes(
		of rebindings: [MockLowering.LoopRebindingCloser],
		at path: [Int],
		configuration: MockLowering.LoopMemberConfiguration,
		among configurations: [[Int]: MockLowering.LoopMemberConfiguration],
		nearestArguments: [[Int]: [PassedArgument]],
	) -> [GeneratedCode] {
		let levelRead: ValuePath = configuration.level.map { .passedArgument($0.parameterName) } ?? configuration.levelRead
		return rebindings.map { rebinding in
			var record = rebinding.record
			if let callee = configurations[rebinding.memberPath] {
				let arguments = if callee.handsMembers {
					// Each configuration the callee takes is one the caller takes: its own, or one it was handed.
					callee.arguments(at: rebinding.memberPath, among: configurations) { handedPath, handed in
						handedPath == path ? .passedArgument(configuration.own.parameterName) : .passedArgument(handed.memberParameterName)
					}
				} else {
					callee.arguments(readingLevelAt: levelRead)
				}
				record.passedArguments = arguments + (nearestArguments[rebinding.memberPath] ?? [])
			}
			return .place(PlacePlan(code: .empty, record: .closer(record)))
		}
	}

	/// Hands the built place of the loop member at `path` its level's configuration, or the configuration of each member
	/// its calls reach, as its level hands them, after its own (`relateConfiguration(ofBuiltPlaceAt:of:)`).
	mutating func handLevelConfiguration(of configuration: MockLowering.LoopMemberConfiguration, toBuiltPlaceAt path: [Int], among configurations: [[Int]: MockLowering.LoopMemberConfiguration]) {
		guard case var .built(record) = builtRecords[path] else { return }
		let arguments = configuration.handsMembers
			? Array(configuration.arguments(at: path, among: configurations) { _, handed in handed.own.value }.dropFirst())
			: (configuration.level.map { [$0] } ?? [])
		for var argument in arguments {
			// As `relateConfiguration(ofBuiltPlaceAt:of:)` binds the place's own: no `@Sendable` closure around the call
			// captures a configuration that is not `Sendable`.
			argument.bindsBeforeCall = pathsStartingExtraction.contains(path) && !argument.staysOutsideSendableFunctions
			record.passedArguments.append(argument)
		}
		builtRecords[path] = .built(record)
	}
}

extension MockLowering {
	/// What the function of a member of a loop of builders takes: its own configuration, its field of its level's, and,
	/// where the level is not the mock root, the level's configuration, under a name the root's table claims for the
	/// level's type (`ConfigurationParameterNames.name(ofLoopLevelConfigurationOf:builtWithHandWrittenMock:)`).
	struct LoopMemberConfiguration {
		/// What the member's level hands the member's own configuration parameter.
		let own: PassedArgument
		/// The name of the member's field in its level's configuration.
		let fieldName: String
		/// The level's configuration, read where the level calls the member's function.
		let levelRead: ValuePath
		/// What the member's level hands the parameter that takes the level's configuration; `nil` where the level is the
		/// mock root, whose `safeDIOverrides` every function reads, or where the members take each other's in its place.
		var level: PassedArgument?
		/// The name of the parameter of another member's function that takes this member's configuration, where the members
		/// of its loop take each other's in place of their level's.
		let memberParameterName: String
		/// The members whose configurations the function takes in place of its level's, in the order of their paths: those
		/// its calls reach. Empty where it takes its level's.
		var reachedPaths: [[Int]]

		/// Whether the member's function takes the configurations of the members it reaches in place of its level's.
		var handsMembers: Bool

		/// The passed arguments a call hands the function of the member at `memberPath` where it takes the members'
		/// configurations: its own, then each member's it reaches, read where `handedValue` reads each, of a member's path
		/// and configuration.
		func arguments(at memberPath: [Int], among configurations: [[Int]: LoopMemberConfiguration], handedValue: ([Int], LoopMemberConfiguration) -> ValuePath) -> [PassedArgument] {
			var arguments = [PassedArgument(parameterName: own.parameterName, type: own.type, value: handedValue(memberPath, self), staysOutsideSendableFunctions: own.staysOutsideSendableFunctions)]
			for path in reachedPaths {
				guard let reached = configurations[path] else { continue }
				arguments.append(PassedArgument(parameterName: reached.memberParameterName, type: reached.own.type, value: handedValue(path, reached), staysOutsideSendableFunctions: reached.own.staysOutsideSendableFunctions))
			}
			return arguments
		}

		/// The passed arguments a closer hands the member's function where the level's configuration reads `levelRead`.
		func arguments(readingLevelAt levelRead: ValuePath) -> [PassedArgument] {
			[PassedArgument(parameterName: own.parameterName, type: own.type, value: .member(fieldName, of: levelRead), staysOutsideSendableFunctions: own.staysOutsideSendableFunctions)]
				+ (level.map { [PassedArgument(parameterName: $0.parameterName, type: $0.type, value: levelRead, staysOutsideSendableFunctions: $0.staysOutsideSendableFunctions)] } ?? [])
		}
	}

	/// A closer that rebinds a member of a loop of builders at the start of another member's function, and the path of the
	/// member it rebinds, whose configurations it hands once they are known.
	struct LoopRebindingCloser {
		let record: ClosingPlaceRecord
		let memberPath: [Int]
	}
}
