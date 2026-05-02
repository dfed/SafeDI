import Foundation
import ProjectDescription

// SafeDI integration helpers for Tuist projects.
//
// Two entry points cover the typical wiring:
//
//   `SafeDI.preCompileScript(module:dependents:)` — pre-compile script
//   phase that runs `SafeDITool generate --combined-output` against
//   one module. The producing target writes
//   `$(BUILT_PRODUCTS_DIR)/SafeDI/<module>.safedi`; downstream targets
//   list the producer's name in `dependents:` and the helper passes
//   that artifact through `--dependent-module-info-file-path`.
//
//   `SafeDI.generatedSource` — the single `.generated(...)` entry to
//   add to a target's `sources`. Always at
//   `$(DERIVED_FILE_DIR)/SafeDIGenerated.swift`. Adding or removing
//   `@Instantiable` declarations doesn't change this path — it just
//   changes the file's contents — so Tuist regeneration is *not*
//   required after annotation changes.
//
// Both helpers depend on the SafeDIToolBinary artifact bundle that
// `tuist install` resolves via `Tuist/Package.swift`. The bundle
// path is implementation detail of the plugin; consumers just need
// SafeDI declared as a package in `Tuist/Package.swift` with its
// default `prebuilt` trait so the bundle is downloaded.

public enum SafeDI {
	/// The single generated-Swift source entry to add to a target's
	/// `sources` for any module that uses
	/// `SafeDI.preCompileScript(...)`. Always resolves to
	/// `$(DERIVED_FILE_DIR)/SafeDIGenerated.swift` — the path is fixed,
	/// only its contents change with the dependency graph, so this
	/// registration never goes stale.
	public static let generatedSource: SourceFileGlob = .generated(
		"$(DERIVED_FILE_DIR)/SafeDIGenerated.swift",
	)

	/// A pre-compile `TargetScript` that runs `SafeDITool generate
	/// --combined-output` against `module`'s sources at build time.
	///
	/// Every call writes
	/// `$(BUILT_PRODUCTS_DIR)/SafeDI/<module>.safedi` (module info, for
	/// downstream consumers) and
	/// `$(DERIVED_FILE_DIR)/SafeDIGenerated.swift` (every generated
	/// dependency-tree, mock, and mock-configuration body
	/// concatenated into one file). Downstream targets pass the
	/// producer's name in `dependents:` so the helper feeds that
	/// `.safedi` artifact through `--dependent-module-info-file-path`.
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
	public static func preCompileScript(
		module: String,
		dependents: [String] = [],
	) -> TargetScript {
		let moduleSources: [FileListGlob] = [.glob("\(module)/**/*.swift")]
		let dependentInputPaths: [FileListGlob] = dependents.map {
			FileListGlob.glob("$(BUILT_PRODUCTS_DIR)/SafeDI/\($0).safedi")
		}
		let outputPaths: [Path] = [
			"$(BUILT_PRODUCTS_DIR)/SafeDI/\(module).safedi",
			"$(DERIVED_FILE_DIR)/SafeDIGenerated.swift",
		]

		return .pre(
			script: scriptBody(module: module, dependents: dependents),
			name: "Generate SafeDI",
			inputPaths: moduleSources + dependentInputPaths,
			outputPaths: outputPaths,
			basedOnDependencyAnalysis: true,
		)
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

	shared_safedi_dir="$BUILT_PRODUCTS_DIR/SafeDI"
	mkdir -p "$shared_safedi_dir"

	# `$module` may contain slashes (e.g. `Sources/App`). Create the
	# parent dir of the module-info output explicitly so the write
	# doesn't fail on the intermediate directories.
	module_info_output="$shared_safedi_dir/$module.safedi"
	mkdir -p "$(dirname "$module_info_output")"

	combined_output="$scratch_dir/SafeDIGenerated.swift"

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

	# Build a CSV of paths relative to $SRCROOT for `generate`.
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

	if [ -n "$dependent_csv" ]; then
		"$safedi_tool" generate \\
			"$input_csv" \\
			--combined-output "$combined_output" \\
			--module-info-output "$module_info_output" \\
			--dependent-module-info-file-path "$dependent_csv"
	else
		"$safedi_tool" generate \\
			"$input_csv" \\
			--combined-output "$combined_output" \\
			--module-info-output "$module_info_output"
	fi

	echo "SafeDI: wrote $module_info_output"
	echo "SafeDI: wrote $combined_output"
	"""
}

private func shellEscape(_ value: String) -> String {
	"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
