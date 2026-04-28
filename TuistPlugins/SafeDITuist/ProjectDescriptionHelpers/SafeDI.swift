import Foundation
import ProjectDescription

// SafeDI integration helpers for Tuist projects.
//
// Two entry points cover the typical wiring:
//
//   `SafeDI.preCompileScript(module:dependents:)` — pre-compile script
//   phase that runs `SafeDITool scan` + `generate` against one module.
//   The producing target writes
//   `$(BUILT_PRODUCTS_DIR)/SafeDI/<module>.safedi`; downstream targets
//   list the producer's name in `dependents:` and the helper passes
//   that artifact through `--dependent-module-info-file-path`.
//
//   `SafeDI.generatedSources(for:)` — runs `SafeDITool scan` at
//   `tuist generate` time, returns `[SourceFileGlob]` of `.generated`
//   entries pointing at `$(DERIVED_FILE_DIR)/<output>.swift`. Add
//   these to the consuming target's `sources` so Xcode wires the
//   build-time output files into the compile phase before they exist.
//
// Both helpers depend on the SafeDIToolBinary artifact bundle that
// `tuist install` resolves via `Tuist/Package.swift`. The bundle
// path is implementation detail of the plugin; consumers just need
// SafeDI declared as a package in `Tuist/Package.swift` with its
// default `prebuilt` trait so the bundle is downloaded.

public enum SafeDI {
	/// A pre-compile `TargetScript` that runs `SafeDITool scan` then
	/// `generate` against `module`'s sources at build time.
	///
	/// Every call writes
	/// `$(BUILT_PRODUCTS_DIR)/SafeDI/<module>.safedi`. Downstream
	/// targets pass the producer's name in `dependents:` so the
	/// helper feeds the artifact through
	/// `--dependent-module-info-file-path`.
	///
	/// The helper assumes the target's Swift sources live under
	/// `$SRCROOT/<module>/**/*.swift`. That single glob feeds both the
	/// script's `inputPaths` (so Xcode reruns the phase only when those
	/// files change) and the script's own scan (so SafeDITool sees the
	/// same set). If your module's sources don't fit that shape, build
	/// the `TargetScript.pre` yourself rather than risk drift between
	/// the two — Xcode would skip rebuilds when files outside
	/// `inputPaths` changed but the script still scanned them.
	///
	/// - Parameters:
	///   - module: Directory under `$SRCROOT` holding the target's
	///     Swift sources. Also the basename of the module-info
	///     artifact this target emits.
	///   - dependents: Modules whose `.safedi` artifacts this target
	///     consumes. Each resolves to
	///     `$(BUILT_PRODUCTS_DIR)/SafeDI/<name>.safedi`. Tuist target
	///     dependencies must guarantee build order.
	///   - generatedOutputs: `[Path]` of generated Swift files this
	///     module produces, typically `generatedSources(for:)` mapped
	///     to their `glob`. Empty for modules that publish a `.safedi`
	///     but don't host any `@Instantiable(isRoot: true)` /
	///     `@Instantiable(generateMock: true)` types themselves.
	public static func preCompileScript(
		module: String,
		dependents: [String] = [],
		generatedOutputs: [Path] = [],
	) -> TargetScript {
		let moduleSources: [FileListGlob] = [.glob("\(module)/**/*.swift")]
		let dependentInputPaths: [FileListGlob] = dependents.map {
			FileListGlob.glob("$(BUILT_PRODUCTS_DIR)/SafeDI/\($0).safedi")
		}
		let outputPaths: [Path] = generatedOutputs + [
			"$(BUILT_PRODUCTS_DIR)/SafeDI/\(module).safedi",
		]

		return .pre(
			script: scriptBody(module: module, dependents: dependents),
			name: "Generate SafeDI",
			inputPaths: moduleSources + dependentInputPaths,
			outputPaths: outputPaths,
			basedOnDependencyAnalysis: true,
		)
	}

	/// Runs `SafeDITool scan` against `module` at `tuist generate`
	/// time and returns `[SourceFileGlob]` of `.generated` entries
	/// pointing at `$(DERIVED_FILE_DIR)/<output>.swift`. Add the
	/// result to the target's `sources` so Xcode treats the
	/// build-time outputs as compile inputs.
	///
	/// - Parameter module: Directory under the manifest containing
	///   the module's Swift sources.
	public static func generatedSources(for module: String) -> [SourceFileGlob] {
		ManifestScanner.outputPaths(forModule: module).map { .generated($0) }
	}
}

// MARK: - Embedded build-time script

// Xcode pre-compile script phases run under `/bin/sh` by default and
// don't honor in-content shebangs. The body below sticks to POSIX
// shell — no arrays, no process substitution — so behavior is
// identical regardless of which sh-compatible shell Xcode picks.
private func scriptBody(module: String, dependents: [String]) -> String {
	let escapedModule = shellEscape(module)
	let escapedDependentNames = shellEscape(dependents.joined(separator: ","))

	return """
	set -eu

	module=\(escapedModule)
	dependent_names_csv=\(escapedDependentNames)

	: "${SRCROOT:?SRCROOT must be set}"
	: "${DERIVED_FILE_DIR:?DERIVED_FILE_DIR must be set}"
	: "${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR must be set}"

	scratch_dir="$DERIVED_FILE_DIR"
	mkdir -p "$scratch_dir"

	manifest_file="$scratch_dir/SafeDIManifest.json"
	shared_safedi_dir="$BUILT_PRODUCTS_DIR/SafeDI"
	mkdir -p "$shared_safedi_dir"

	module_info_output="$shared_safedi_dir/$module.safedi"

	host_os=$(uname -s)
	host_arch=$(uname -m)
	case "$host_os:$host_arch" in
		Darwin:arm64)               tool_variant="SafeDITool-macos-arm64" ;;
		Darwin:x86_64)              tool_variant="SafeDITool-macos-x86_64" ;;
		Linux:aarch64|Linux:arm64)  tool_variant="SafeDITool-linux-arm64" ;;
		Linux:x86_64|Linux:amd64)   tool_variant="SafeDITool-linux-x86_64" ;;
		*)
			echo "error: SafeDI plugin: unsupported host $host_os/$host_arch" >&2
			exit 3
			;;
	esac

	artifact_bundle="$SRCROOT/Tuist/.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle"
	safedi_tool="$artifact_bundle/$tool_variant/bin/SafeDITool"

	if [ ! -x "$safedi_tool" ]; then
		echo "error: SafeDI plugin: SafeDITool not found at $safedi_tool" >&2
		echo "       run \\`tuist install\\` to fetch it." >&2
		exit 5
	fi

	module_dir="$SRCROOT/$module"
	if [ ! -d "$module_dir" ]; then
		echo "error: SafeDI plugin: module directory not found at $module_dir" >&2
		exit 4
	fi

	# Build a CSV of paths relative to $SRCROOT for `scan` and `generate`.
	# Run `find` standalone so `set -e` catches a non-zero exit (e.g.
	# unreadable subdir or broken symlink) — a pipeline would mask it
	# under POSIX sh, which has no pipefail.
	sources_list="$scratch_dir/SourcesList.txt"
	find -L "$module_dir" -type f -name '*.swift' >"$sources_list"

	input_csv="$scratch_dir/InputSwiftFiles.csv"
	: >"$input_csv"
	first=1
	while IFS= read -r abs; do
		rel=${abs#"$SRCROOT/"}
		if [ "$first" = 1 ]; then
			printf '%s' "$rel" >>"$input_csv"
			first=0
		else
			printf ',%s' "$rel" >>"$input_csv"
		fi
	done <"$sources_list"

	if [ ! -s "$input_csv" ]; then
		echo "error: SafeDI plugin: no .swift sources found under $module_dir" >&2
		exit 4
	fi

	# Resolve dependent .safedi artifacts. Caller passes the
	# comma-separated list of module *names*; we construct paths
	# inside the build env so $BUILT_PRODUCTS_DIR expands correctly.
	dependent_csv=""
	if [ -n "$dependent_names_csv" ]; then
		dependent_csv="$scratch_dir/DependentModuleInfo.csv"
		: >"$dependent_csv"

		old_ifs="$IFS"
		IFS=','
		# shellcheck disable=SC2086
		set -- $dependent_names_csv
		IFS="$old_ifs"

		first=1
		for dependent_name in "$@"; do
			dependent_path="$shared_safedi_dir/$dependent_name.safedi"
			if [ ! -f "$dependent_path" ]; then
				echo "error: SafeDI plugin: $dependent_name.safedi not found at $dependent_path — the $dependent_name target must build first" >&2
				exit 1
			fi
			if [ "$first" = 1 ]; then
				printf '%s' "$dependent_path" >>"$dependent_csv"
				first=0
			else
				printf ',%s' "$dependent_path" >>"$dependent_csv"
			fi
		done
	fi

	cd "$SRCROOT"

	"$safedi_tool" scan \\
		--input-sources-file "$input_csv" \\
		--project-root "$SRCROOT" \\
		--output-directory "$scratch_dir" \\
		--manifest-file "$manifest_file"

	if [ -n "$dependent_csv" ]; then
		"$safedi_tool" generate \\
			"$input_csv" \\
			--swift-manifest "$manifest_file" \\
			--module-info-output "$module_info_output" \\
			--dependent-module-info-file-path "$dependent_csv"
	else
		"$safedi_tool" generate \\
			"$input_csv" \\
			--swift-manifest "$manifest_file" \\
			--module-info-output "$module_info_output"
	fi

	echo "SafeDI: wrote $module_info_output"
	echo "SafeDI: wrote generated code into $scratch_dir"
	"""
}

private func shellEscape(_ value: String) -> String {
	"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - Manifest-time scan

private enum ManifestScanner {
	static func outputPaths(forModule module: String) -> [Path] {
		let manifestDirectory = manifestDirectoryURL()
		let moduleDirectory = manifestDirectory.appendingPathComponent(module, isDirectory: true)

		guard FileManager.default.fileExists(atPath: moduleDirectory.path) else {
			fatal("module directory not found at \(moduleDirectory.path)")
		}

		guard let tool = resolvedSafeDIToolURL(manifestDirectory: manifestDirectory) else {
			fatal("""
			SafeDITool binary not found under Tuist/.build/artifacts/...
			Run `tuist install` before `tuist generate`.
			""")
		}

		let scratch = manifestDirectory
			.appendingPathComponent(".build/safedi-tuist-plugin", isDirectory: true)
			.appendingPathComponent(module, isDirectory: true)
		do {
			try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
		} catch {
			fatal("failed to create scratch directory at \(scratch.path): \(error)")
		}

		let inputCSV = scratch.appendingPathComponent("InputSwiftFiles.csv")
		let sources = swiftSourcePaths(relativeTo: manifestDirectory, in: moduleDirectory)
		guard !sources.isEmpty else {
			fatal("no .swift sources found under \(moduleDirectory.path)")
		}
		do {
			try sources.joined(separator: ",").write(to: inputCSV, atomically: true, encoding: .utf8)
		} catch {
			fatal("failed to write input CSV at \(inputCSV.path): \(error)")
		}

		let manifestFile = scratch.appendingPathComponent("SafeDIManifest.json")

		let process = Process()
		process.executableURL = tool
		process.currentDirectoryURL = manifestDirectory
		process.arguments = [
			"scan",
			"--input-sources-file", inputCSV.path,
			"--project-root", manifestDirectory.path,
			"--output-directory", scratch.path,
			"--manifest-file", manifestFile.path,
		]
		let stderrPipe = Pipe()
		process.standardError = stderrPipe
		do {
			try process.run()
		} catch {
			fatal("failed to launch SafeDITool scan: \(error)")
		}
		process.waitUntilExit()
		guard process.terminationStatus == 0 else {
			let stderr = String(
				data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
				encoding: .utf8,
			) ?? "<unavailable>"
			fatal("""
			SafeDITool scan exited \(process.terminationStatus):
			\(stderr)
			""")
		}

		guard let data = try? Data(contentsOf: manifestFile),
		      let manifest = try? JSONDecoder().decode(ScanManifest.self, from: data)
		else {
			fatal("SafeDITool scan succeeded but its manifest at \(manifestFile.path) is unreadable.")
		}

		var outputs: [Path] = []
		for entry in manifest.dependencyTreeGeneration + manifest.mockGeneration {
			outputs.append("$(DERIVED_FILE_DIR)/\((entry.outputFilePath as NSString).lastPathComponent)")
		}
		if let mockConfiguration = manifest.mockConfigurationOutputFilePath {
			outputs.append("$(DERIVED_FILE_DIR)/\((mockConfiguration as NSString).lastPathComponent)")
		}
		return outputs
	}

	// Tuist runs the manifest binary with its working directory set to
	// the manifest's directory. Use that to resolve consumer paths
	// rather than `#filePath`, which would point at this plugin source.
	private static func manifestDirectoryURL() -> URL {
		URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
	}

	private static func resolvedSafeDIToolURL(manifestDirectory: URL) -> URL? {
		#if arch(arm64)
			let variant = "SafeDITool-macos-arm64"
		#else
			let variant = "SafeDITool-macos-x86_64"
		#endif
		let tool = manifestDirectory
			.appendingPathComponent("Tuist/.build/artifacts/safedi/SafeDIToolBinary", isDirectory: true)
			.appendingPathComponent("SafeDITool.artifactbundle", isDirectory: true)
			.appendingPathComponent("\(variant)/bin/SafeDITool")
		return FileManager.default.isExecutableFile(atPath: tool.path) ? tool : nil
	}

	private static func swiftSourcePaths(relativeTo base: URL, in directory: URL) -> [String] {
		guard let enumerator = FileManager.default.enumerator(
			at: directory,
			includingPropertiesForKeys: nil,
		) else { return [] }
		var results = [String]()
		let basePath = base.standardizedFileURL.path
		for case let url as URL in enumerator where url.pathExtension == "swift" {
			let absolute = url.standardizedFileURL.path
			if absolute.hasPrefix(basePath + "/") {
				results.append(String(absolute.dropFirst(basePath.count + 1)))
			}
		}
		return results.sorted()
	}

	private struct ScanManifest: Decodable {
		struct Entry: Decodable { let outputFilePath: String }
		let dependencyTreeGeneration: [Entry]
		let mockGeneration: [Entry]
		let mockConfigurationOutputFilePath: String?
	}
}

private func fatal(_ message: String) -> Never {
	FileHandle.standardError.write(Data("error: SafeDI plugin: \(message)\n".utf8))
	exit(1)
}
