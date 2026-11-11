// SPIKE, never to be merged: measures what treating access as a first-class input to generate would save.
//
// SAFEDI_SPIKE_ACCESS (all off when unset, and then this file does nothing):
//   record       generate counts, per module, the declarations it holds and writes the oracle's keep list.
//   unnameable   scan and generate drop every other-module @Instantiable the module cannot name (Dan's idea, literally).
//   oracle       scan and generate drop every other-module @Instantiable that `record` found unreached: more than any
//                access rule could drop, so its saving is the ceiling.
// SAFEDI_SPIKE_ACCESS_DIR: where `record` writes and `oracle` reads, one set of files per module.
// SAFEDI_SPIKE_ACCESS_SAFEDI (independent of the above):
//   nameable     the .safedi keeps only declarations another module can name (`package` or wider).
//   reached      as `nameable`, plus whatever a seam's or public mock's tree in the module reaches (option C, without stubs).

import Foundation
import SafeDICore

enum SpikeAccess {
	enum Mode: String {
		case record
		case unnameable
		case oracle
	}

	enum WriterMode: String {
		case nameable
		case reached
	}

	static let mode = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_ACCESS"].flatMap(Mode.init(rawValue:))
	static let writerMode = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_ACCESS_SAFEDI"].flatMap(WriterMode.init(rawValue:))
	static let directory = ProcessInfo.processInfo.environment["SAFEDI_SPIKE_ACCESS_DIR"]

	/// Whether scan's cache may hold fewer declarations than scan's walk mentioned.
	static var prunesScanCache: Bool {
		mode == .unnameable || mode == .oracle
	}

	private static func keepListPath(moduleName: String) -> String? {
		directory.map { ($0 as NSString).appendingPathComponent("\(moduleName).keep") }
	}

	private static func key(of instantiable: Instantiable) -> String {
		"\(instantiable.sourceFilePath ?? "")\t\(instantiable.concreteInstantiable.asSource)"
	}

	private static func keepList(moduleName: String?) -> Set<String>? {
		guard mode == .oracle,
		      let moduleName,
		      let path = keepListPath(moduleName: moduleName),
		      let contents = try? String(contentsOfFile: path, encoding: .utf8)
		else {
			return nil
		}
		return Set(contents.split(separator: "\n").map(String.init))
	}

	static func canName(_ instantiable: Instantiable, declaredIn declarer: ModuleIdentity, from emitter: ModuleIdentity) -> Bool {
		AccessLevel.effective(ofTypeDeclaredBy: instantiable)
			.satisfies(AccessLevel.required(toConstructFrom: emitter, declaredIn: declarer, isOwnFile: false))
	}

	/// What to keep of `instantiables`, which `declaringModule` attributes to modules.
	private static func kept(
		_ instantiables: [Instantiable],
		emitter: ModuleIdentity,
		keepList: Set<String>?,
		declaringModule: (Instantiable) -> ModuleIdentity?,
	) -> [Instantiable] {
		guard let mode, mode != .record else { return instantiables }
		return instantiables.filter { instantiable in
			guard let declarer = declaringModule(instantiable), let moduleName = declarer.moduleName, moduleName != emitter.moduleName else {
				return true
			}
			switch mode {
			case .record:
				return true
			case .unnameable:
				return canName(instantiable, declaredIn: declarer, from: emitter)
			case .oracle:
				return keepList?.contains(key(of: instantiable)) ?? true
			}
		}
	}

	/// `module` and `dependentModules` without what this run's mode drops, in `generate`, after each declaration has its module.
	static func pruned(module: ModuleInfo, dependentModules: [ModuleInfo]) -> (module: ModuleInfo, dependentModules: [ModuleInfo]) {
		guard mode != nil, mode != .record else { return (module, dependentModules) }
		let emitter = ModuleIdentity(moduleName: module.moduleName, packageName: module.packageName)
		let keepList = keepList(moduleName: module.moduleName)
		func prune(_ moduleInfo: ModuleInfo) -> ModuleInfo {
			moduleInfo.spikeReplacing(instantiables: kept(moduleInfo.instantiables, emitter: emitter, keepList: keepList) { instantiable in
				instantiable.moduleName.map { ModuleIdentity(moduleName: $0, packageName: instantiable.packageName) }
			})
		}
		return (prune(module), dependentModules.map(prune))
	}

	/// What scan caches of `fileScan`, named as the manifest names files, under this run's mode. Needs the plugin's
	/// target graph, the only way scan can know the modules.
	static func scanCacheFilter(inputSourcesFile: String) -> (FileScan) -> FileScan {
		guard prunesScanCache,
		      let targetGraph = try? PluginTargetGraph(besideInputSourcesFileAt: inputSourcesFile)
		else {
			return { $0 }
		}
		let membership = ModuleMembership(targetGraph: targetGraph)
		let emitter = ModuleIdentity(moduleName: membership.moduleName, packageName: membership.packageName)
		let keepList = keepList(moduleName: membership.moduleName)
		return { fileScan in
			let declaringModule = membership.declaringModule(ofFileAt: fileScan.path).map { ModuleIdentity(moduleName: $0.moduleName, packageName: $0.packageName) }
			return fileScan.spikeReplacing(instantiables: kept(fileScan.instantiables, emitter: emitter, keepList: keepList) { _ in declaringModule })
		}
	}

	/// The closure over every dependency edge of `starts`, through `map`, as concrete types.
	private static func reached(from starts: [Instantiable], map: [TypeDescription: Instantiable]) -> Set<TypeDescription> {
		var reachedTypes = Set<TypeDescription>()
		var toVisit = starts
		while let instantiable = toVisit.popLast() {
			guard reachedTypes.insert(instantiable.concreteInstantiable).inserted else { continue }
			for dependency in instantiable.dependencies {
				if let next = map[dependency.asInstantiatedType], !reachedTypes.contains(next.concreteInstantiable) {
					toVisit.append(next)
				}
			}
		}
		return reachedTypes
	}

	/// Counts this run's declarations, and writes the keep list and file lists the oracle and the harness read.
	static func record(
		unnormalized: [Instantiable],
		normalized: [Instantiable],
		map: [TypeDescription: Instantiable],
		emitter: ModuleIdentity,
		plainTypeDeclarations: [PlainTypeDeclaration],
		additionalMocksToGenerate: [String],
	) {
		guard mode == .record, let moduleName = emitter.moduleName, let directory else { return }
		var isOwn = [Bool]()
		var isUnknown = [Bool]()
		var isUnnameable = [Bool]()
		for instantiable in unnormalized {
			isOwn.append(instantiable.moduleName == moduleName)
			isUnknown.append(instantiable.moduleName == nil)
			if let declarerName = instantiable.moduleName, declarerName != moduleName {
				isUnnameable.append(!canName(instantiable, declaredIn: ModuleIdentity(moduleName: declarerName, packageName: instantiable.packageName), from: emitter))
			} else {
				isUnnameable.append(false)
			}
		}
		let own = zip(normalized, isOwn).filter(\.1).map(\.0)
		let ownStarts = own.filter { $0.isRoot || $0.generatesDependencyTree || $0.generatesMock }
			+ map.values.filter { additionalMocksToGenerate.contains($0.concreteInstantiable.asSource) }
		// Every tree this run walks: a root another module declares is validated here too, today.
		let foreignRoots = zip(normalized, isOwn).filter { !$0.1 && $0.0.isRoot }.map(\.0)
		let reachedTypes = reached(from: ownStarts + foreignRoots, map: map)
		let reachedFromOwnStarts = reached(from: ownStarts, map: map)

		var counters: [String: Int] = [
			"held": normalized.count,
			"own": own.count,
			"unknownModule": isUnknown.count(where: \.self),
			"other": normalized.count - own.count - isUnknown.count(where: \.self),
			"otherUnnameable": isUnnameable.count(where: \.self),
			"plainDeclarations": plainTypeDeclarations.count,
			"plainDeclarationsOfOtherModules": plainTypeDeclarations.count(where: { $0.moduleName != nil && $0.moduleName != moduleName }),
			"mapEntries": map.count,
		]
		var keepLines = [String]()
		var unreachedFiles = [String: Bool]()
		var unnameableFiles = [String: Bool]()
		var reachedOther = 0
		var reachedOtherOnlyByForeignRoots = 0
		var reachedOtherUnnameable = 0
		var unreachedOtherUnnameable = 0
		for index in unnormalized.indices where !isOwn[index] && !isUnknown[index] {
			let type = normalized[index].concreteInstantiable
			let isReached = reachedTypes.contains(type)
			if isReached {
				keepLines.append(key(of: unnormalized[index]))
				reachedOther += 1
				if !reachedFromOwnStarts.contains(type) {
					reachedOtherOnlyByForeignRoots += 1
				}
				if isUnnameable[index] {
					reachedOtherUnnameable += 1
				}
			} else if isUnnameable[index] {
				unreachedOtherUnnameable += 1
			}
			if let path = unnormalized[index].sourceFilePath {
				unreachedFiles[path] = (unreachedFiles[path] ?? true) && !isReached
				unnameableFiles[path] = (unnameableFiles[path] ?? true) && isUnnameable[index]
			}
		}
		counters["reachedOther"] = reachedOther
		counters["reachedOtherOnlyByForeignRoots"] = reachedOtherOnlyByForeignRoots
		counters["unreachedOther"] = (counters["other"] ?? 0) - reachedOther
		counters["reachedOtherUnnameable"] = reachedOtherUnnameable
		counters["unreachedOtherUnnameable"] = unreachedOtherUnnameable
		counters["filesOnlyUnreached"] = unreachedFiles.values.count(where: \.self)
		counters["filesOnlyUnnameable"] = unnameableFiles.values.count(where: \.self)

		func write(_ lines: [String], suffix: String) {
			try? lines.sorted().joined(separator: "\n").write(
				toFile: (directory as NSString).appendingPathComponent("\(moduleName).\(suffix)"),
				atomically: true,
				encoding: .utf8,
			)
		}
		write(keepLines, suffix: "keep")
		write(unreachedFiles.filter(\.value).map(\.key), suffix: "files-unreached")
		write(unnameableFiles.filter(\.value).map(\.key), suffix: "files-unnameable")
		if let data = try? JSONSerialization.data(withJSONObject: counters, options: [.sortedKeys, .prettyPrinted]) {
			try? data.write(to: URL(fileURLWithPath: (directory as NSString).appendingPathComponent("\(moduleName).counters.json")))
		}
	}

	/// `module` as this run's `.safedi` holds it.
	static func moduleForFile(_ module: ModuleInfo, normalizedOwn: [Instantiable], map: [TypeDescription: Instantiable]) -> ModuleInfo {
		guard let writerMode else { return module }
		let keptBySeamOrPublicMock: Set<TypeDescription> = switch writerMode {
		case .nameable:
			[]
		case .reached:
			reached(from: normalizedOwn.filter { $0.generatesDependencyTree || $0.generateMock == .public }, map: map)
		}
		let kept = zip(module.instantiables, normalizedOwn)
			.filter { instantiable, normalized in
				AccessLevel.effective(ofTypeDeclaredBy: instantiable).satisfies(.package) || keptBySeamOrPublicMock.contains(normalized.concreteInstantiable)
			}
			.map(\.0)
		return module.spikeReplacing(instantiables: kept)
	}
}
