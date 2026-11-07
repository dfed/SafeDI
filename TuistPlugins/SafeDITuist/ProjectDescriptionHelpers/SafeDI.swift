import Foundation
import ProjectDescription

// SafeDI integration helpers for Tuist projects.
//
// Two entry points cover the typical wiring:
//
//   `SafeDI.preCompileScript(module:dependencies:)` — pre-compile script
//   phase that runs `SafeDITool generate --combined-output` against
//   one module. The producing target writes
//   `$(BUILT_PRODUCTS_DIR)/SafeDI/<module>.safedi`; downstream targets
//   list the producer's name in `dependencies:` and the helper passes
//   that artifact through `--dependent-module-info-file-path`.
//
//   `SafeDI.generatedSource` — the single `.generated(...)` entry to
//   add to a target's `sources`. Always at
//   `$(DERIVED_FILE_DIR)/SafeDIGenerated.swift`. Adding or removing
//   `@Instantiable` declarations doesn't change this path — it just
//   changes the file's contents — so a change to a file the target
//   already lists needs a build, not `tuist generate`. A new Swift file
//   needs `tuist generate`, which makes it one of the script's inputs
//   (see `preCompileScript`).
//
// Both helpers depend on the SafeDIToolBinary artifact bundle that
// `tuist install` resolves via `Tuist/Package.swift`. The bundle
// path is implementation detail of the plugin; consumers just need
// SafeDI declared as a package in `Tuist/Package.swift` with its
// default `prebuilt` trait so the bundle is downloaded. The script
// finds the bundle from any project of the workspace, including one
// in a subdirectory (`Projects/Feature/Project.swift`).

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
	/// producer's name in `dependencies:` so the helper feeds that
	/// `.safedi` artifact through `--dependent-module-info-file-path`.
	/// The script reports the conditions the target compiles with by
	/// passing its `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and
	/// `OTHER_SWIFT_FLAGS` build settings, so a `-D` flag counts too.
	/// The script names the module with `--module-name
	/// $PRODUCT_MODULE_NAME`, and its package with `--package-name
	/// $SWIFT_PACKAGE_NAME` when the target sets that build setting, for
	/// a SafeDITool that accepts them.
	///
	/// The helper assumes the target's Swift sources live under
	/// `$SRCROOT/<module>/**/*.swift`. That single glob feeds both the
	/// script's `inputPaths` and the script's own `find` of files to pass
	/// to `SafeDITool generate`. Tuist expands the glob when `tuist
	/// generate` runs, so the inputs are the files that existed then:
	/// Xcode reruns the phase when one of them changes, and a Swift file
	/// added since is read only when the phase next runs for another
	/// change. After adding a file, run `tuist generate`, which a target
	/// with buildable folders also needs: it compiles the new file
	/// without it, but its phase does not run for the file. If your
	/// module's sources don't fit that shape, build the
	/// `TargetScript.pre` yourself rather than risk drift between the
	/// two — Xcode would skip rebuilds when files outside `inputPaths`
	/// changed but the script still read them.
	///
	/// - Parameters:
	///   - module: Directory under `$SRCROOT` holding the target's
	///     Swift sources. Also the basename of the module-info
	///     artifact this target emits, so it must be distinct across
	///     the workspace's projects (name the sources directory after
	///     the module, as the example's `Projects/Subproject/Subproject/`
	///     does).
	///   - dependencies: Modules whose `.safedi` artifacts this target
	///     consumes. Each resolves to
	///     `$(BUILT_PRODUCTS_DIR)/SafeDI/<name>.safedi`. Tuist target
	///     dependencies must guarantee build order.
	public static func preCompileScript(
		module: String,
		dependencies: [String] = [],
	) -> TargetScript {
		let moduleSources: [FileListGlob] = [.glob("\(module)/**/*.swift")]
		let dependencyInputPaths: [FileListGlob] = dependencies.map {
			FileListGlob.glob("$(BUILT_PRODUCTS_DIR)/SafeDI/\($0).safedi")
		}
		let outputPaths: [Path] = [
			"$(BUILT_PRODUCTS_DIR)/SafeDI/\(module).safedi",
			"$(DERIVED_FILE_DIR)/SafeDIGenerated.swift",
		]

		return .pre(
			script: scriptBody(module: module, dependencies: dependencies),
			name: "Generate SafeDI",
			inputPaths: moduleSources + dependencyInputPaths,
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
private func scriptBody(module: String, dependencies: [String]) -> String {
	let escapedModule = shellEscape(module)
	let escapedDependencyNames = shellEscape(dependencies.joined(separator: ","))

	return """
	set -eu

	module=\(escapedModule)
	dependency_names_csv=\(escapedDependencyNames)

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
			echo "error: SafeDI plugin: unsupported host $host_os/$host_arch. SafeDITool is published for macOS and Linux on arm64 and x86_64." >&2
			exit 3
			;;
	esac

	# `tuist install` unpacks SafeDITool into `Tuist/.build` beside
	# `Tuist/Package.swift`, in the workspace's root. A project in a
	# subdirectory (`Projects/Feature/Project.swift`) has that
	# subdirectory as its `$SRCROOT`, so look in the nearest directory,
	# from `$SRCROOT` up, that holds `Tuist/Package.swift`.
	tuist_root="$SRCROOT"
	while [ ! -f "$tuist_root/Tuist/Package.swift" ]; do
		parent_directory=$(dirname "$tuist_root")
		if [ "$parent_directory" = "$tuist_root" ]; then
			echo "error: SafeDI plugin: no Tuist/Package.swift found in $SRCROOT or any directory above it. Depend on SafeDI in the workspace's Tuist/Package.swift, and run \\`tuist install\\` to fetch SafeDITool." >&2
			exit 5
		fi
		tuist_root="$parent_directory"
	done
	artifact_bundle="$tuist_root/Tuist/.build/artifacts/safedi/SafeDIToolBinary/SafeDITool.artifactbundle"
	safedi_tool="$artifact_bundle/$tool_variant/bin/SafeDITool"

	if [ ! -x "$safedi_tool" ]; then
		echo "error: SafeDI plugin: SafeDITool not found at $safedi_tool" >&2
		echo "       run \\`tuist install\\` in $tuist_root to fetch it." >&2
		exit 5
	fi

	module_dir="$SRCROOT/$module"
	if [ ! -d "$module_dir" ]; then
		echo "error: SafeDI plugin: module directory not found at $module_dir. The module argument of SafeDI.preCompileScript must name the directory under SRCROOT that holds the target's Swift sources." >&2
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
		echo "error: SafeDI plugin: no .swift sources found under $module_dir. Check the module argument of SafeDI.preCompileScript." >&2
		exit 4
	fi

	# Resolve dependent .safedi artifacts. Caller passes the
	# comma-separated list of module *names*; we construct paths
	# inside the build env so $BUILT_PRODUCTS_DIR expands correctly.
	dependency_csv=""
	if [ -n "$dependency_names_csv" ]; then
		dependency_csv="$scratch_dir/DependencyModuleInfo.csv"
		: >"$dependency_csv"

		old_ifs="$IFS"
		IFS=','
		# shellcheck disable=SC2086
		set -- $dependency_names_csv
		IFS="$old_ifs"

		first=1
		for dependency_name in "$@"; do
			dependency_path="$shared_safedi_dir/$dependency_name.safedi"
			if [ ! -f "$dependency_path" ]; then
				echo "error: SafeDI plugin: $dependency_name.safedi not found at $dependency_path. Add $dependency_name to this target's dependencies so it builds first, and check that it also runs SafeDI.preCompileScript." >&2
				exit 1
			fi
			if [ "$first" = 1 ]; then
				printf '%s' "$dependency_path" >>"$dependency_csv"
				first=0
			else
				printf ',%s' "$dependency_path" >>"$dependency_csv"
			fi
		done
	fi

	cd "$SRCROOT"

	set -- "$input_csv" \\
		--combined-output "$combined_output" \\
		--module-info-output "$module_info_output"
	if [ -n "$dependency_csv" ]; then
		set -- "$@" --dependent-module-info-file-path "$dependency_csv"
	fi

	# SafeDITool releases before an option existed reject it, so a
	# plugin newer than the pinned binary forwards an option only when
	# the binary's help, read once here, advertises it.
	generate_help=$("$safedi_tool" generate --help) || generate_help=""

	# Report the conditions swiftc compiles this target with, so SafeDITool
	# scans the same `#if` clauses. swiftc defines each condition in
	# `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and each `-D` flag in
	# `OTHER_SWIFT_FLAGS`, so pass both settings as this shell expands
	# them, in brackets that keep an empty setting a value: SafeDITool
	# reads the `-D` flags and takes the two settings as the complete set
	# of conditions, as it does for the `SafeDIGenerator` plugin. A
	# SafeDITool older than 2.1.0-rc-3 has neither option, so give it
	# `SWIFT_ACTIVE_COMPILATION_CONDITIONS` alone, which Xcode exports
	# space-separated and which is left unquoted to word-split. The longer
	# option name is matched first, since it contains the shorter one.
	case "$generate_help" in
		*--build-setting-active-compilation-conditions*)
			set -- "$@" \\
				"--build-setting-active-compilation-conditions=[${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}]" \\
				"--build-setting-other-swift-flags=[${OTHER_SWIFT_FLAGS:-}]"
			;;
		*--active-compilation-conditions*)
			if [ -n "${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-}" ]; then
				# shellcheck disable=SC2086
				set -- "$@" --active-compilation-conditions $SWIFT_ACTIVE_COMPILATION_CONDITIONS
			fi
			;;
	esac

	# Name the module this target compiles and its package, which
	# SafeDITool records in this target's `.safedi` artifact, beside the
	# modules the dependencies' `.safedi` artifacts record. The package
	# is named only when the target sets `SWIFT_PACKAGE_NAME`, which
	# Xcode passes the compiler as `-package-name`.
	case "$generate_help" in
		*--module-name*)
			if [ -n "${PRODUCT_MODULE_NAME:-}" ]; then
				set -- "$@" --module-name "$PRODUCT_MODULE_NAME"
			fi
			if [ -n "${SWIFT_PACKAGE_NAME:-}" ]; then
				set -- "$@" --package-name "$SWIFT_PACKAGE_NAME"
			fi
			;;
	esac

	"$safedi_tool" generate "$@"

	echo "SafeDI: wrote $module_info_output"
	echo "SafeDI: wrote $combined_output"
	"""
}

private func shellEscape(_ value: String) -> String {
	"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
