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

import Foundation
import SafeDICore

/// The targets whose Swift files the SafeDIGenerator plugin lists in its input CSV, as the plugin writes them beside
/// that CSV, in a file named after it with `.targets.json` appended. Plugins cannot import SafeDITool, so the plugin
/// writes the same keys with a type of its own (`TargetGraph` in `Plugins/Shared.swift`). The Xcode project plugin
/// knows no targets and writes none.
struct PluginTargetGraph: Codable {
	/// The target the plugin generates code for.
	let target: Target
	/// Every other target whose Swift files the input CSV lists: the target's first-party dependencies, directly or
	/// through another target, by the rule that decides which files the CSV lists. Sorted.
	let dependencyTargets: [Target]

	/// A target of a Swift package.
	struct Target: Codable {
		/// The name of the module the target compiles.
		let moduleName: String
		/// SwiftPM's identity of the package that declares the target, from which SwiftPM derives the
		/// `-package-name` it hands the compiler, or `nil` when the plugin found the target in no package.
		let packageID: String?
		/// The directory that holds the target's sources, absolute, as SwiftPM reports it to the plugin.
		let directoryPath: String
		/// The modules the target depends on directly, through a target or a product, sorted.
		let dependencyModuleNames: [String]
	}

	/// What the plugin appends to the input CSV's path to name the file it writes the target graph to.
	static let fileNameSuffix = ".targets.json"
}

extension PluginTargetGraph {
	/// The target graph the plugin wrote beside the input CSV at `inputSourcesFilePath`, or `nil` when no file is
	/// there, as for the Xcode project plugin, a SafeDIGenerator plugin that predates the file, or a script.
	init?(besideInputSourcesFileAt inputSourcesFilePath: String) throws {
		let filePath = inputSourcesFilePath + Self.fileNameSuffix
		guard FileManager.default.fileExists(atPath: filePath) else {
			return nil
		}
		do {
			self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: URL(fileURLWithPath: filePath)))
		} catch {
			throw UnreadableTargetGraphError(path: filePath)
		}
	}
}

/// A target graph the SafeDIGenerator plugin wrote that this SafeDITool cannot read. The reason is left out: the
/// cure is the same whatever it is, and Foundation words it differently on each platform.
struct UnreadableTargetGraphError: Error, CustomStringConvertible {
	let path: String

	var description: String {
		"Could not read the target graph the SafeDIGenerator plugin wrote at \(path) as this SafeDITool reads it. A different version of SafeDI most likely wrote this file. To fix this, clean your build (in Xcode: Product > Clean Build Folder) and build again, so that the plugin writes it again."
	}
}

/// The module, and the package of that module, that declares a file `generate` reads. Either is `nil` when SafeDITool
/// does not know it.
struct DeclaringModule: Hashable, Sendable {
	let moduleName: String?
	let packageName: String?
}

/// What the build system tells `generate` about modules: the module whose code it generates, and the module that
/// declares each file it reads.
struct ModuleMembership: Sendable {
	/// Every input file, and no other file, belongs to the module `generate` generates code for. The options that name
	/// that module say this for a build system that runs `generate` once per module, such as the Bazel rule and the
	/// Tuist plugin.
	/// - Parameter inputFilePaths: The files the input CSV and `--include` name, which are the module's own files.
	///   Files reached through `#SafeDIConfiguration(additionalDirectoriesToInclude:)` belong to another module.
	init(
		moduleName: String?,
		packageName: String?,
		dependencyModuleNames: [String],
		inputFilePaths: Set<ProjectFilePath>,
	) {
		self.moduleName = moduleName
		self.packageName = packageName
		self.dependencyModuleNames = dependencyModuleNames
		let declaringModule = DeclaringModule(moduleName: moduleName, packageName: packageName)
		declaringModuleOfFile = { filePath in
			inputFilePaths.contains(filePath) ? declaringModule : nil
		}
	}

	/// Each file belongs to the target whose directory holds it, nested most deeply when targets nest, and the module
	/// `generate` generates code for is the target the plugin planned. A file no target's directory holds, such as one
	/// of a checkout package reached through `additionalDirectoriesToInclude`, belongs to no module SafeDITool knows,
	/// and neither does a file in a directory two targets share: SwiftPM lets targets split one directory with
	/// `sources:`, which the directories alone cannot tell apart.
	/// - Parameter projectFilePaths: How the files' paths are compared with the targets' directories.
	init(targetGraph: PluginTargetGraph, projectFilePaths: ProjectFilePaths) {
		moduleName = targetGraph.target.moduleName
		packageName = targetGraph.target.packageID
		dependencyModuleNames = targetGraph.target.dependencyModuleNames
		let targetsByDirectory = Dictionary(
			grouping: [targetGraph.target] + targetGraph.dependencyTargets,
			by: { projectFilePaths.projectFilePath(of: $0.directoryPath) },
		)
		// The longest directory first, so a file is attributed to the most deeply nested target that holds it: the
		// directories that hold a file all enclose one another, and two directories of one length cannot.
		let directories = targetsByDirectory
			.map { directory, targets in
				(
					directory: directory,
					declaringModule: targets.count == 1 ? DeclaringModule(moduleName: targets[0].moduleName, packageName: targets[0].packageID) : nil,
				)
			}
			.sorted { $0.directory.path.count > $1.directory.path.count }
		declaringModuleOfFile = { filePath in
			directories.first { filePath.liesInside($0.directory) }?.declaringModule
		}
	}

	/// The module `generate` generates code for, or `nil` when the build system did not say.
	let moduleName: String?
	/// The package of the module `generate` generates code for, or `nil` when the build system did not say.
	let packageName: String?
	/// The modules the module `generate` generates code for depends on directly.
	let dependencyModuleNames: [String]

	/// The module that declares the file at `filePath`, or `nil` when SafeDITool does not know it.
	func declaringModule(ofFileAt filePath: ProjectFilePath) -> DeclaringModule? {
		declaringModuleOfFile(filePath)
	}

	private let declaringModuleOfFile: @Sendable (ProjectFilePath) -> DeclaringModule?
}

extension ModuleInfo {
	/// This module as `membership` describes it: the module `generate` generates code for, and each declaration with
	/// the module that declares its file.
	/// - Parameter projectFilePaths: How each declaration's file is spelled for comparison with what `membership` knows.
	func declared(by membership: ModuleMembership, filePathsSpelledBy projectFilePaths: ProjectFilePaths) -> ModuleInfo {
		// A file usually declares one or two types, and spelling a path for comparison costs more than looking it up.
		let declaringModuleByFilePath = Dictionary(
			uniqueKeysWithValues: Set(instantiables.compactMap(\.sourceFilePath)).compactMap { sourceFilePath in
				membership.declaringModule(ofFileAt: projectFilePaths.projectFilePath(of: sourceFilePath)).map { (sourceFilePath, $0) }
			},
		)
		return replacing(
			instantiables: instantiables.map { instantiable in
				instantiable.declared(in: instantiable.sourceFilePath.flatMap { declaringModuleByFilePath[$0] })
			},
			moduleName: membership.moduleName,
			packageName: membership.packageName,
			dependencyModuleNames: membership.dependencyModuleNames,
		)
	}

	/// This module with `instantiables`, generated code for the module `moduleName` names.
	private func replacing(
		instantiables: [Instantiable],
		moduleName: String?,
		packageName: String?,
		dependencyModuleNames: [String],
	) -> ModuleInfo {
		ModuleInfo(
			imports: imports,
			mockImports: mockImports,
			instantiables: instantiables,
			configurations: configurations,
			filesWithUnexpectedNodes: filesWithUnexpectedNodes,
			conditionalCompilationDecisions: conditionalCompilationDecisions,
			instantiableTypeNamesInAnyClause: instantiableTypeNamesInAnyClause,
			moduleName: moduleName,
			packageName: packageName,
			dependencyModuleNames: dependencyModuleNames,
		)
	}
}

extension Instantiable {
	/// This declaration in `declaringModule`, which also declares its hand-written mock, if it has one: a `mockOnly`
	/// declaration's mock reaches another declaration only when the two are merged.
	func declared(in declaringModule: DeclaringModule?) -> Instantiable {
		var instantiable = self
		instantiable.moduleName = declaringModule?.moduleName
		instantiable.packageName = declaringModule?.packageName
		instantiable.mockDeclarationModuleName = mockInitializer == nil ? nil : declaringModule?.moduleName
		instantiable.mockDeclarationPackageName = mockInitializer == nil ? nil : declaringModule?.packageName
		return instantiable
	}
}
