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

import SafeDICore

/// Which of the modules beneath a module (`--transitive-module-info-file-path`) the module's run reads.
///
/// Dependency trees alone ask for a module beneath. The modules a build lists are read whole, as they always are, and
/// every module beneath that declares a type a tree needs and nothing read declares is read too, as if it were listed: the
/// run then generates code, or reports the error, that listing it gives, and the code imports the module. So the walk starts
/// at the module's own trees and at the root of every module read. A module with no tree of its own asks for nothing,
/// whatever the trees of the modules it lists.
///
/// At another module's seam the walk goes through the seam's tree, and a type the seam's module does not read is a hole: a
/// need of this run unless a seam between this run's tree and the hole fills it, which that seam's module does when it reads
/// a type that fulfills the hole. The run needs the fill and, to reach it, every type between its tree and the hole, since
/// a run builds a type's tree only through the declarations it read.
///
/// A root's tree that needs a type nothing read declares does not build, so reading for it can only fix the build or report
/// what a complete list reports. A seam's tree takes such a type as a builder, which is a hole and builds; reading for it does
/// what listing the module does, so the seam builds the type and its initializer stops taking that builder, or the run
/// reports the duplicate declaration a complete list reports. A mock takes what it cannot build as a parameter and asks for
/// nothing: reading a module for one could turn a build that passes into one that fails, in as many ways as SafeDI can reject
/// a mock. A mock builds what the list and the modules read for the trees declare.
///
/// The walk reads declarations as their modules wrote them, before normalization, which qualifies a nested type among the
/// declarations a run reads and so needs to know which those are. It follows what the generated code follows, without the
/// checks that report an unusable tree, so it can read a module no tree needs only where the tree would be rejected.
struct ModulesBeneathSelection {
	// MARK: Initialization

	/// - Parameters:
	///   - ownModule: The module the run generates code for.
	///   - listedFiles: The module info files the build lists.
	init(ownModule: ModuleInfo, listedFiles: [ModuleInfoFile]) {
		for declaration in read(ownModule.instantiables, isOwn: true) where declaration.instantiable.isRoot || declaration.instantiable.generatesDependencyTree {
			startingVisits.append(Visit(declaration: declaration, walk: .tree))
		}
		guard !startingVisits.isEmpty else { return }
		for listedFile in listedFiles {
			read(listedFile)
			otherModules.add(listedFile)
		}
	}

	// MARK: Internal

	/// Whether the module's trees reach a type that nothing read so far declares: whether the files of the modules beneath
	/// are opened at all.
	func reachesTypeNothingReadDeclares() -> Bool {
		walk().reachesTypeNothingReadDeclares
	}

	/// The indices of those of `files` that declare what the module's trees need.
	///
	/// Works in rounds: a whole walk over what has been read names the files it wants, and only then are they read, so that
	/// what a round wants follows from the graph alone and never from the order of a walk.
	/// - Parameter files: The module info files of the modules beneath, without those the build lists.
	mutating func indicesOfFilesToRead(among files: [ModuleInfoFile]) -> Set<Int> {
		for (index, file) in files.enumerated() {
			otherModules.add(file)
			for instantiable in file.instantiables where !instantiable.mockOnly {
				for instantiableType in instantiable.instantiableTypes {
					fileIndicesDeclaringType[instantiableType, default: []].insert(index)
				}
			}
		}
		var indicesRead = Set<Int>()
		var indicesToRead = walk().fileIndicesToRead
		while !indicesToRead.isEmpty {
			for index in indicesToRead.sorted() {
				read(files[index])
			}
			indicesRead.formUnion(indicesToRead)
			indicesToRead = walk().fileIndicesToRead
		}
		return indicesRead
	}

	// MARK: Private

	/// A production declaration the walk can reach.
	private struct Declaration {
		let instantiable: Instantiable
		let isOwn: Bool
	}

	/// How a tree follows a declaration's dependencies.
	private enum Walk: Hashable {
		/// As far as the first seam another module generates.
		case tree
		/// The tree of a seam another module generates, over the declarations that module's run read.
		case treeOfSeam(generatedByModuleNamed: String)
	}

	/// A type the tree of a seam another module generates instantiates and that module's run does not read.
	private struct Hole {
		/// The visit of the declaration whose dependency it is.
		let ownerKey: Visit.Key
		/// The types that would fulfill it, most qualified first.
		let types: [TypeDescription]
	}

	private struct Visit {
		let declaration: Declaration
		let walk: Walk

		struct Key: Hashable {
			let concreteType: TypeDescription
			let walk: Walk
		}

		var key: Key {
			Key(concreteType: declaration.instantiable.concreteInstantiable, walk: walk)
		}

		/// The walk that follows the declaration's dependencies: a seam of another module is built by that module, unless no
		/// module is known to generate it, so every tree builds it inline.
		var walkOfDependencies: Walk {
			guard declaration.instantiable.generatesDependencyTree,
			      !declaration.isOwn,
			      let moduleName = declaration.instantiable.moduleName
			else { return walk }
			return .treeOfSeam(generatedByModuleNamed: moduleName)
		}
	}

	/// What a run knows of other modules from the module info files it opens and the views they carry, which it need not
	/// read: the declarations of the modules whose seams a walk can reach and of the modules those read.
	private struct OtherModules {
		mutating func add(_ file: ModuleInfoFile) {
			moduleNamesReadByModuleName[file.moduleName] = Set(file.dependencyModuleNames + [file.moduleName])
			add(moduleNamed: file.moduleName, instantiables: file.instantiables)
			for identity in file.view.moduleGraph {
				moduleNamesReadByModuleName[identity.moduleName] = Set(identity.dependencyModuleNames + [identity.moduleName])
			}
			for viewedModule in file.view.declarations {
				add(moduleNamed: viewedModule.moduleName, instantiables: viewedModule.instantiables)
			}
		}

		/// The production declaration of the first of `types` that one of the modules the run of the module named
		/// `moduleName` read declares. That run rejected two of them, so which is found decides nothing.
		func declaration(amongTypes types: [TypeDescription], readByRunOfModuleNamed moduleName: String) -> Declaration? {
			let moduleNamesRead = moduleNamesReadByModuleName[moduleName, default: []]
			return types.lazy.compactMap { type in
				productionDeclarationsByType[type]?.first { moduleNamesRead.contains($0.moduleName) }?.declaration
			}.first
		}

		private var moduleNamesReadByModuleName = [String: Set<String>]()
		private var productionDeclarationsByType = [TypeDescription: [(moduleName: String, declaration: Declaration)]]()
		private var moduleNamesAdded = Set<String>()

		private mutating func add(moduleNamed moduleName: String, instantiables: [Instantiable]) {
			guard moduleNamesAdded.insert(moduleName).inserted else { return }
			for instantiable in instantiables where !instantiable.mockOnly {
				let declaration = Declaration(instantiable: instantiable, isOwn: false)
				for instantiableType in instantiable.instantiableTypes {
					productionDeclarationsByType[instantiableType, default: []].append((moduleName: moduleName, declaration: declaration))
				}
			}
		}
	}

	private var startingVisits = [Visit]()
	/// The production declaration read so far of each type.
	private var declarationsByType = [TypeDescription: Declaration]()
	private var fileIndicesDeclaringType = [TypeDescription: Set<Int>]()
	private var otherModules = OtherModules()

	/// Records the declarations of another module's `file` as read. A root another module declares is validated by every
	/// run that reads it, as that module's run validates it, so its tree is walked too.
	private mutating func read(_ file: ModuleInfoFile) {
		for declaration in read(file.instantiables, isOwn: false) where declaration.instantiable.isRoot {
			startingVisits.append(Visit(declaration: declaration, walk: .tree))
		}
	}

	/// Records the production declarations among `instantiables` as read, the first read of a type winning: a second is a
	/// duplicate, which the run reports, so which is walked decides nothing.
	/// - Returns: Each of them as a declaration, in the order given.
	private mutating func read(_ instantiables: [Instantiable], isOwn: Bool) -> [Declaration] {
		instantiables.filter { !$0.mockOnly }.map { instantiable in
			let declaration = Declaration(instantiable: instantiable, isOwn: isOwn)
			for instantiableType in instantiable.instantiableTypes where declarationsByType[instantiableType] == nil {
				declarationsByType[instantiableType] = declaration
			}
			return declaration
		}
	}

	/// Visits everything the module's trees reach over what has been read, with an explicit stack, since a dependency tree
	/// can be as deep as the module has types. Reads nothing: it says which files of the modules beneath declare a type it
	/// reaches that nothing read declares, or that stands between its trees and a hole they fill.
	///
	/// Holes are settled when nothing is left to walk, since a fill's tree can reach another hole, or another route to one.
	private func walk() -> (reachesTypeNothingReadDeclares: Bool, fileIndicesToRead: Set<Int>) {
		var visitsToMake = startingVisits
		var reachesTypeNothingReadDeclares = false
		var fileIndicesToRead = Set<Int>()
		var visitedKeys = Set<Visit.Key>()
		var callersOfVisits = [Visit.Key: Set<Visit.Key>]()
		var holes = [Hole]()
		repeat {
			while let visit = visitsToMake.popLast() {
				guard visitedKeys.insert(visit.key).inserted else { continue }
				let instantiable = visit.declaration.instantiable
				let walk = visit.walkOfDependencies
				for dependency in instantiable.dependencies where dependency.isInstantiated {
					// Most qualified first, as the compiler searches for the type where the declaration spells it.
					let types = TypeDescription.nestedOptions(
						referencedType: dependency.asInstantiatedType,
						within: instantiable.concreteInstantiable,
					)
					if case let .treeOfSeam(moduleName) = walk {
						if let declaration = otherModules.declaration(amongTypes: types, readByRunOfModuleNamed: moduleName) {
							let callee = Visit(declaration: declaration, walk: walk)
							callersOfVisits[callee.key, default: []].insert(visit.key)
							visitsToMake.append(callee)
						} else {
							holes.append(Hole(ownerKey: visit.key, types: types))
						}
					} else if let declaration = declaration(amongTypes: types) {
						visitsToMake.append(Visit(declaration: declaration, walk: walk))
					} else {
						reachesTypeNothingReadDeclares = true
						fileIndicesToRead.formUnion(types.lazy.compactMap { fileIndicesDeclaringType[$0] }.first ?? [])
					}
				}
			}
			for hole in holes {
				let routes = routes(to: hole, callersOfVisits: callersOfVisits)
				for fill in routes.fillsOfSeamsBetween {
					callersOfVisits[fill.visit.key, default: []].insert(fill.callerKey)
					visitsToMake.append(fill.visit)
				}
				guard !routes.keysFromThisRunsTrees.isEmpty else { continue }
				if let fill = declaration(amongTypes: hole.types) {
					visitsToMake.append(Visit(declaration: fill, walk: .tree))
					for key in routes.keysFromThisRunsTrees where declarationsByType[key.concreteType] == nil {
						reachesTypeNothingReadDeclares = true
						fileIndicesToRead.formUnion(fileIndicesDeclaringType[key.concreteType] ?? [])
					}
				} else {
					reachesTypeNothingReadDeclares = true
					fileIndicesToRead.formUnion(hole.types.lazy.compactMap { fileIndicesDeclaringType[$0] }.first ?? [])
				}
			}
			visitsToMake.removeAll { visitedKeys.contains($0.key) }
		} while !visitsToMake.isEmpty
		return (reachesTypeNothingReadDeclares: reachesTypeNothingReadDeclares, fileIndicesToRead: fileIndicesToRead)
	}

	/// How `hole` is reached, walking back from its owner through the callers of each visit: the visits on every route from
	/// a tree this run generates on which no seam fills it, and the fill of each seam that fills it on a route.
	private func routes(
		to hole: Hole,
		callersOfVisits: [Visit.Key: Set<Visit.Key>],
	) -> (keysFromThisRunsTrees: Set<Visit.Key>, fillsOfSeamsBetween: [(visit: Visit, callerKey: Visit.Key)]) {
		var fillsOfSeamsBetween = [(visit: Visit, callerKey: Visit.Key)]()
		var keysWalked = Set<Visit.Key>()
		var keysFilledBySeam = Set<Visit.Key>()
		var calleesOfKeys = [Visit.Key: [Visit.Key]]()
		var keysInThisRunsTrees = [Visit.Key]()
		var keysToWalk = [hole.ownerKey]
		while let key = keysToWalk.popLast() {
			guard keysWalked.insert(key).inserted else { continue }
			guard case let .treeOfSeam(moduleName) = key.walk else {
				keysInThisRunsTrees.append(key)
				continue
			}
			if let fill = otherModules.declaration(amongTypes: hole.types, readByRunOfModuleNamed: moduleName) {
				fillsOfSeamsBetween.append((visit: Visit(declaration: fill, walk: key.walk), callerKey: key))
				keysFilledBySeam.insert(key)
			} else {
				for callerKey in callersOfVisits[key, default: []] {
					calleesOfKeys[callerKey, default: []].append(key)
					keysToWalk.append(callerKey)
				}
			}
		}
		// Forward again from this run's trees, since a route walked back can end at a seam that fills the hole.
		var keysFromThisRunsTrees = Set<Visit.Key>()
		keysToWalk = keysInThisRunsTrees
		while let key = keysToWalk.popLast() {
			guard keysFromThisRunsTrees.insert(key).inserted else { continue }
			keysToWalk += calleesOfKeys[key, default: []].filter { !keysFilledBySeam.contains($0) }
		}
		return (keysFromThisRunsTrees: keysFromThisRunsTrees, fillsOfSeamsBetween: fillsOfSeamsBetween)
	}

	private func declaration(amongTypes types: [TypeDescription]) -> Declaration? {
		types.lazy.compactMap { declarationsByType[$0] }.first
	}
}

extension Dependency {
	/// Whether a tree builds the dependency. A tree is handed what it receives and what is forwarded to it, from an ancestor
	/// that instantiates it or from outside the tree.
	fileprivate var isInstantiated: Bool {
		switch source {
		case .instantiated:
			true
		case .aliased, .forwarded, .received:
			false
		}
	}
}
