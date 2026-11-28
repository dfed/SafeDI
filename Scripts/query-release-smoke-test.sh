#!/bin/bash
# Scripts/query-release-smoke-test.sh PATH_TO_SAFEDITOOL
#
# Runs a built SafeDITool as a user runs it: `generate` once per module for a
# chain of 40 one-type modules, then `query graph` and `query needs` over all
# of them, read from `--include` directories and from `.safedi` files, three
# times each. It fails unless every command exits with status 0 and each
# query reports every module.
#
# It exists for the binaries SafeDI publishes. 2.3.1's release binaries
# (Swift 6.3 with `-Osize`) returned no modules with exit status 0, or
# crashed, when `query` read more than one module, while `generate` and every
# test were right: the tests run the tool's code in process, from a build
# with another compiler and other flags. Only running the binary built as
# `publish.yml` builds it shows such a miscompile, so "Build Release
# SafeDITool on Linux" runs this on its build and `publish.yml` runs it on
# each binary before uploading it. The failure came and went between runs,
# hence three runs of each query.
#
# Then, over a root whose child receives a value, it runs `query graph`,
# `query needs`, `generate` and `dump`, three times each. 2.4.2's release
# binaries (Swift 6.3.3 on Linux, Xcode 26.4 on macOS) crashed in
# `swift_task_localValuePush` on `query graph` over any module with a root,
# since reading where each received value comes from binds a task-local
# function, which those compilers' release builds cannot bind; the chain above
# declares no root, so it never read one. The fix holds every task-local
# function in a `TaskLocalFunction` (`taskLocalFunction` in
# `.claude/rules/source-rules.md`).
set -euo pipefail

tool=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
module_count=40
work_directory=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/query-smoke.XXXXXX")
trap 'rm -rf "$work_directory"' EXIT
cd "$work_directory"

include_arguments=()
module_info_arguments=()
dependent_module_infos=""
for index in $(seq -f %03g 0 $((module_count - 1))); do
	mkdir -p "Module$index"
	if [ "$index" = 000 ]; then
		body="    public init() {}"
	else
		previous=$(printf %03d $((10#$index - 1)))
		body="    public init(child: Type$previous) { self.child = child }
    @Instantiated let child: Type$previous"
	fi
	cat > "Module$index/Type$index.swift" <<SWIFT
import SafeDI

@Instantiable
public final class Type$index: Instantiable {
$body
}
SWIFT
	include_arguments+=(--include "Module$index")
	printf '%s' "$dependent_module_infos" > dependencies.csv
	"$tool" generate --include "Module$index" --module-name "Module$index" --module-info-output "Module$index.safedi" --dependent-module-info-file-path dependencies.csv --combined-output "Module$index.generated.swift"
	module_info_arguments+=(--module-info "$work_directory/Module$index.safedi")
	dependent_module_infos="${dependent_module_infos:+$dependent_module_infos,}$work_directory/Module$index.safedi"
done

fail() {
	echo "::error::$1"
	exit 1
}

for source in include module-info; do
	if [ "$source" = include ]; then
		arguments=("${include_arguments[@]}")
	else
		arguments=("${module_info_arguments[@]}")
	fi
	for run in 1 2 3; do
		"$tool" query graph "${arguments[@]}" --output graph.json || fail "query graph over $source failed on run $run."
		reported=$(grep -c '"id" :' graph.json || true)
		[ "$reported" = "$module_count" ] || fail "query graph over $source reported $reported of $module_count types on run $run."
		"$tool" query needs Type039 --json "${arguments[@]}" > needs.json || fail "query needs over $source failed on run $run."
		grep -q '"typeName" : "Type039"' needs.json || fail "query needs over $source did not report Type039 on run $run."
	done
done
# A root of 16 children, more than `generate` plans at once, each with two
# leaves, and a root of three branches, each of three twigs, each of two leaves.
# The expected code is what a debug build of the tool from this commit writes:
# a change to what `generate` writes for these roots rewrites it here.
mkdir -p Generated
instantiable() { # NAME IS_ROOT LABEL:TYPE…
	local name=$1 attribute=@Instantiable parameters="" assignments="" properties=""
	[ "$2" = root ] && attribute="@Instantiable(isRoot: true)"
	shift 2
	for dependency in "$@"; do
		label=${dependency%%:*}
		type=${dependency#*:}
		parameters="${parameters:+$parameters, }$label: $type"
		assignments="$assignments        self.$label = $label"$'\n'
		properties="$properties    @Instantiated let $label: $type"$'\n'
	done
	printf '%s\npublic final class %s: Instantiable {\n    public init(%s) {\n%s    }\n\n%s}\n\n' "$attribute" "$name" "$parameters" "$assignments" "$properties"
}
{
	echo "import SafeDI"
	mids=()
	for index in $(seq -f %02g 0 15); do
		mids+=("mid$index:Mid$index")
	done
	instantiable WideRoot root "${mids[@]}"
	for index in $(seq -f %02g 0 15); do
		instantiable "Mid$index" child leafA:LeafA leafB:LeafB
	done
	instantiable DeepRoot root branchA:BranchA branchB:BranchB branchC:BranchC
	for branch in A B C; do
		instantiable "Branch$branch" child twigA:TwigA twigB:TwigB twigC:TwigC
	done
	for twig in A B C; do
		instantiable "Twig$twig" child leafA:LeafA leafB:LeafB
	done
	instantiable LeafA child
	instantiable LeafB child
} > Generated/Roots.swift
# `generate` ends its file without a newline, which the command substitution drops.
expected=$(cat <<'GENERATED'
// This file was generated by the SafeDIGenerateDependencyTree build tool plugin.
// Any modifications made to this file will be overwritten on subsequent builds.
// Please refrain from editing this file directly.

#if canImport(SafeDI)
import SafeDI
#endif

extension DeepRoot {
    public convenience init() {
        func __safeDI_twigA() -> TwigA {
            let leafA = LeafA()
            let leafB = LeafB()
            return TwigA(leafA: leafA, leafB: leafB)
        }
        func __safeDI_twigB() -> TwigB {
            let leafA = LeafA()
            let leafB = LeafB()
            return TwigB(leafA: leafA, leafB: leafB)
        }
        func __safeDI_twigC() -> TwigC {
            let leafA = LeafA()
            let leafB = LeafB()
            return TwigC(leafA: leafA, leafB: leafB)
        }
        func __safeDI_branchA() -> BranchA {
            let twigA: TwigA = __safeDI_twigA()
            let twigB: TwigB = __safeDI_twigB()
            let twigC: TwigC = __safeDI_twigC()
            return BranchA(twigA: twigA, twigB: twigB, twigC: twigC)
        }
        let branchA: BranchA = __safeDI_branchA()
        func __safeDI_branchB() -> BranchB {
            let twigA: TwigA = __safeDI_twigA()
            let twigB: TwigB = __safeDI_twigB()
            let twigC: TwigC = __safeDI_twigC()
            return BranchB(twigA: twigA, twigB: twigB, twigC: twigC)
        }
        let branchB: BranchB = __safeDI_branchB()
        func __safeDI_branchC() -> BranchC {
            let twigA: TwigA = __safeDI_twigA()
            let twigB: TwigB = __safeDI_twigB()
            let twigC: TwigC = __safeDI_twigC()
            return BranchC(twigA: twigA, twigB: twigB, twigC: twigC)
        }
        let branchC: BranchC = __safeDI_branchC()
        self.init(branchA: branchA, branchB: branchB, branchC: branchC)
    }
}

extension WideRoot {
    public convenience init() {
        func __safeDI_mid00() -> Mid00 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid00(leafA: leafA, leafB: leafB)
        }
        let mid00: Mid00 = __safeDI_mid00()
        func __safeDI_mid01() -> Mid01 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid01(leafA: leafA, leafB: leafB)
        }
        let mid01: Mid01 = __safeDI_mid01()
        func __safeDI_mid02() -> Mid02 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid02(leafA: leafA, leafB: leafB)
        }
        let mid02: Mid02 = __safeDI_mid02()
        func __safeDI_mid03() -> Mid03 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid03(leafA: leafA, leafB: leafB)
        }
        let mid03: Mid03 = __safeDI_mid03()
        func __safeDI_mid04() -> Mid04 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid04(leafA: leafA, leafB: leafB)
        }
        let mid04: Mid04 = __safeDI_mid04()
        func __safeDI_mid05() -> Mid05 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid05(leafA: leafA, leafB: leafB)
        }
        let mid05: Mid05 = __safeDI_mid05()
        func __safeDI_mid06() -> Mid06 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid06(leafA: leafA, leafB: leafB)
        }
        let mid06: Mid06 = __safeDI_mid06()
        func __safeDI_mid07() -> Mid07 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid07(leafA: leafA, leafB: leafB)
        }
        let mid07: Mid07 = __safeDI_mid07()
        func __safeDI_mid08() -> Mid08 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid08(leafA: leafA, leafB: leafB)
        }
        let mid08: Mid08 = __safeDI_mid08()
        func __safeDI_mid09() -> Mid09 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid09(leafA: leafA, leafB: leafB)
        }
        let mid09: Mid09 = __safeDI_mid09()
        func __safeDI_mid10() -> Mid10 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid10(leafA: leafA, leafB: leafB)
        }
        let mid10: Mid10 = __safeDI_mid10()
        func __safeDI_mid11() -> Mid11 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid11(leafA: leafA, leafB: leafB)
        }
        let mid11: Mid11 = __safeDI_mid11()
        func __safeDI_mid12() -> Mid12 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid12(leafA: leafA, leafB: leafB)
        }
        let mid12: Mid12 = __safeDI_mid12()
        func __safeDI_mid13() -> Mid13 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid13(leafA: leafA, leafB: leafB)
        }
        let mid13: Mid13 = __safeDI_mid13()
        func __safeDI_mid14() -> Mid14 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid14(leafA: leafA, leafB: leafB)
        }
        let mid14: Mid14 = __safeDI_mid14()
        func __safeDI_mid15() -> Mid15 {
            let leafA = LeafA()
            let leafB = LeafB()
            return Mid15(leafA: leafA, leafB: leafB)
        }
        let mid15: Mid15 = __safeDI_mid15()
        self.init(mid00: mid00, mid01: mid01, mid02: mid02, mid03: mid03, mid04: mid04, mid05: mid05, mid06: mid06, mid07: mid07, mid08: mid08, mid09: mid09, mid10: mid10, mid11: mid11, mid12: mid12, mid13: mid13, mid14: mid14, mid15: mid15)
    }
}
GENERATED
)
printf '%s' "$expected" > expected.swift
for run in 1 2 3; do
	"$tool" generate --include Generated --module-name Generated --combined-output generated.swift || fail "generate failed on run $run."
	diff -u expected.swift generated.swift || fail "generate wrote other code than expected on run $run."
done
mkdir -p Received
cat > Received/Received.swift <<'SWIFT'
import SafeDI

@Instantiable(isRoot: true)
public final class ReceivedRoot: Instantiable {
    public init(service: ReceivedService, child: ReceivedChild) {
        self.service = service
        self.child = child
    }

    @Instantiated let service: ReceivedService
    @Instantiated let child: ReceivedChild
}

@Instantiable
public final class ReceivedService: Instantiable {
    public init() {}
}

@Instantiable
public final class ReceivedChild: Instantiable {
    public init(service: ReceivedService) {
        self.service = service
    }

    @Received let service: ReceivedService
}
SWIFT
for run in 1 2 3; do
	"$tool" query graph --include Received --output received-graph.json || fail "query graph over a root failed on run $run."
	grep -q '"completeness" : "trees"' received-graph.json || fail "query graph over a root did not build its trees on run $run."
	grep -q '"provenance" :' received-graph.json || fail "query graph over a root reported no provenance on run $run."
	"$tool" query needs ReceivedRoot --json --include Received > received-needs.json || fail "query needs over a root failed on run $run."
	grep -q '"typeName" : "ReceivedRoot"' received-needs.json || fail "query needs over a root did not report ReceivedRoot on run $run."
	"$tool" generate --include Received --module-name Received --module-info-output Received.safedi --combined-output received.swift || fail "generate over a root failed on run $run."
	grep -q 'extension ReceivedRoot' received.swift || fail "generate over a root wrote no initializer for ReceivedRoot on run $run."
	"$tool" dump Received.safedi > received-dump.json || fail "dump of a module info file failed on run $run."
	grep -q '"ReceivedChild"' received-dump.json || fail "dump of a module info file did not list ReceivedChild on run $run."
done
echo "query graph and query needs reported all $module_count modules, generate wrote the expected code, and query graph, query needs, generate and dump ran over a root whose child receives a value."
