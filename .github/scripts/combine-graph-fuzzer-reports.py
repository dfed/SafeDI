"""usage: combine-graph-fuzzer-reports.py SUMMARY REPORT...

Checks the graph fuzzer's whole-corpus pins across the reports of the shards
that ci.yml splits each corpus into. Each shard's long run ends its report with

    shard <starting seed> <count> <accepted count> <accepted seed-set sum> <corpus>
    corpus <seed count> <pinned accepted count> <pinned accepted seed-set sum> <corpus>
    features <corpus> <feature>=<accepted graphs showing it>,… <feature>=<pinned count>,…
    inspected <graphs the value oracle inspected> <pinned count> <corpus>
    compared <graphs the value comparator compared> <corpus>
    retention <corpus> <key>=<count>,… <key>=<pinned count>,…
    level-captures <corpus> <key>=<count>,… <key>=<pinned count>,…
    gating <corpus> <draw>=<graphs of the draw the oracles judged>,… <floor>
    gating-shapes <corpus> <shape>=<graphs of the shape the oracles judged>,…
    read-twins <graphs the oracle compared with their read twin> <pinned count> <corpus>
    seam-mock-builders <accepted graphs whose seam's own mock takes a builder that takes nothing> <corpus>
    omitted-values <graphs rejected because a caller holds a value its tier omits> <pinned count> <corpus>
    spellings <corpus> <spellings to draw, comma-separated> <spellings drawn in accepted graphs>
    draws <corpus> <draw>=<accepted graphs showing it>,… <draw>=<pinned count>,…
    errors <corpus> <graphs each pinned error rejects>,… <pinned counts>,…
    builder-surface <corpus> <kind>=<graphs the builder surface judged as it>,… <floored kind>,…
    outputs <corpus> <feature>=<accepted graphs showing it>,… <feature>=<pinned minimum percent>,…
    value-oracle <corpus> <key>=<value>,… <key>=<pinned value>,…
    cpu <corpus> <wall seconds> <test process CPU seconds> <child processes' CPU seconds> <phase>=<busy seconds>:<child CPU seconds>:<child processes>,…

where <corpus> names the corpus the shard fuzzed: `base`, or a generator
feature's name. For each corpus the shards must cover 0..<seed count exactly
once, and the accepted counts and seed-set sums (a wrapping sum of per-seed
hashes, so parts add up) must add up to the pins, the accepted graphs that show each feature must add up to its
pinned count wherever the corpus pins them (`features`), the graphs the value oracle
inspected, the graphs compared with their read twin, and the graphs rejected for an omitted value must add up to their
pins, every spelling the corpus draws must be
drawn in some accepted graph of some shard, each output feature with a pinned minimum must show in at least that
percentage of the corpus's accepted graphs (the public mock corpus reports `outputs`), what the retention oracle judged
must add up to its pins (`retention`: the graphs with a hole it judged, those that draw its own shape, those whose
hand-written builder it judged, and the experiments only one path ran), what the level function capture check
judged must add up to its pins (`level-captures`: the graphs with a level function, those with a member closure that
names its parameter, those member closures, the conversion functions and the fill functions; the seam corpus's first
two must reach ten graphs each), the graphs of each gating draw that the
oracles after acceptance judged must reach the floor (`gating`, a floor rather than a pin, since a draw gates only
while that many of its graphs are judged; `gating-shapes`, the shapes each draw rolls, checks nothing), the accepted
graphs that show
each draw a corpus counts must add up to its pinned count (`draws`), the graphs each error a corpus pins rejects must
add up to their pins (`errors`: a public mock's own errors, or a cycle's in a seam's tree), the graphs the builder
surface judges as each kind a corpus floors must add up to at least ten (`builder-surface`), what the base corpus's value oracle compares and
skips must add up to its pins (`value-oracle`: counts, and set sums whose keys end in `Sum`, which add up wrapping
like the accepted seed-set sum), fewer than one in twenty of the seam graphs the places oracle compares may have their
passed-up cases capped (`places-oracle`: capped, then compared), and no shard may report a failure,
a stale known issue, a misfiled seed, or a problem. Every long run writes `features`, `inspected`, `retention`, `gating`, `read-twins`, `draws`, `errors` and `builder-surface` for its corpus,
`value-oracle` for the base corpus, and `level-captures` for the seam corpus, so a complete report that names a corpus without one of them is a problem: a
run that stopped writing the line would otherwise skip that line's check silently. The `cpu` lines check nothing:
the summary adds them up per corpus into a table of what each phase of the oracle cost, a phase's busy seconds being
the seconds the batches of the corpus's shards spent in it. Writes a Markdown summary to
SUMMARY and the job summary, and exits non-zero when anything is missing or
does not match.
"""

import os
import sys

summary_path = sys.argv[1]
# An unmatched shell glob arrives as the pattern itself, so keep only reports that exist.
report_paths = sorted(path for path in sys.argv[2:] if os.path.isfile(path))
problems = []
shards_by_corpus = {}
pins_by_corpus = {}
inspected_by_corpus = {}
inspected_pins_by_corpus = {}
compared_by_corpus = {}
retention_by_corpus = {}
retention_pins_by_corpus = {}
level_captures_by_corpus = {}
level_captures_pins_by_corpus = {}
# The counts of the level function capture check that must reach ten graphs in the seam corpus.
LEVEL_CAPTURES_FLOOR = 10
LEVEL_CAPTURES_FLOORED_KEYS = ("judged", "judgedWithNamed")
SEAM_CORPUS = "generateDependencyTree"
gating_by_corpus = {}
gating_floors_by_corpus = {}
read_twins_by_corpus = {}
read_twins_pins_by_corpus = {}
# The accepted graphs, per corpus, whose seam's own internal mock takes a builder as a closure that takes nothing: at least
# `SEAM_MOCK_BUILDER_FLOOR`, the only count of that shape the seam corpus draws.
seam_mock_builders_by_corpus = {}
# The seam graphs the places oracle compared, and those whose passed-up cases it capped (`places-oracle`), by corpus.
places_oracle_by_corpus = {}
SEAM_MOCK_BUILDER_FLOOR = 10
omitted_values_by_corpus = {}
# The graphs the builder surface judged per kind, added up across shards, and the kinds each corpus floors.
builder_surface_counts_by_corpus = {}
builder_surface_floored_by_corpus = {}
BUILDER_SURFACE_FLOOR = 10
omitted_values_pins_by_corpus = {}
required_spellings_by_corpus = {}
accepted_spellings_by_corpus = {}
feature_counts_by_corpus = {}
feature_pins_by_corpus = {}
output_counts_by_corpus = {}
output_minimums_by_corpus = {}
# The output features of a public mock that takes a builder taking nothing, each the only count of its shape in the public
# mock corpus: at least `NEW_BUILDER_OUTPUT_FLOOR` accepted graphs show each, whatever its share.
NEW_BUILDER_OUTPUT_FEATURES = [
    "generatedOnlyMockFunction",
    "consumerPassesLevelFunctionsStruct",
    "holeLoopBuilderOfBuilderStruct",
]
NEW_BUILDER_OUTPUT_FLOOR = 10
error_counts_by_corpus = {}
error_pins_by_corpus = {}
draw_counts_by_corpus = {}
draw_pins_by_corpus = {}
value_oracle_by_corpus = {}
value_oracle_pins_by_corpus = {}
cost_by_corpus = {}


def value_oracle_fields(field):
    """The `key=value` pairs of a `value-oracle` field, each value an integer (a set sum is hexadecimal)."""
    values = {}
    for item in filter(None, field.split(",")):
        key, value = item.split("=")
        values[key] = int(value, 0)
    return values


# Every corpus the long run knows, from the `corpora` line each report carries: a corpus whose shards all left no
# report would otherwise go unchecked.
expected_corpora = set()
for path in report_paths:
    shard_lines = []
    completed = False
    reported_corpora = set()
    featured_corpora = set()
    inspected_corpora = set()
    retention_corpora = set()
    level_captures_corpora = set()
    gating_corpora = set()
    read_twin_corpora = set()
    builder_surface_corpora = set()
    drawn_corpora = set()
    error_corpora = set()
    value_oracle_corpora = set()
    with open(path) as report:
        for line in report:
            fields = line.split()
            if not fields:
                continue
            if fields[0] == "shard" and len(fields) == 6:
                shard_lines.append((fields[5], int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4], 16)))
            elif fields[0] == "corpus" and len(fields) == 5:
                pins_by_corpus.setdefault(fields[4], set()).add((int(fields[1]), int(fields[2]), int(fields[3], 16)))
                reported_corpora.add(fields[4])
            elif fields[0] == "corpora":
                expected_corpora.update(fields[1:])
            elif fields[0] == "inspected" and len(fields) == 4:
                inspected_corpora.add(fields[3])
                inspected_by_corpus[fields[3]] = inspected_by_corpus.get(fields[3], 0) + int(fields[1])
                inspected_pins_by_corpus.setdefault(fields[3], set()).add(int(fields[2]))
            elif fields[0] == "compared" and len(fields) == 3:
                compared_by_corpus[fields[2]] = compared_by_corpus.get(fields[2], 0) + int(fields[1])
            elif fields[0] == "retention" and len(fields) == 4:
                retention_corpora.add(fields[1])
                totals = retention_by_corpus.setdefault(fields[1], {})
                for key, value in value_oracle_fields(fields[2]).items():
                    totals[key] = totals.get(key, 0) + value
                retention_pins_by_corpus.setdefault(fields[1], set()).add(fields[3])
            elif fields[0] == "level-captures" and len(fields) == 4:
                level_captures_corpora.add(fields[1])
                totals = level_captures_by_corpus.setdefault(fields[1], {})
                for key, value in value_oracle_fields(fields[2]).items():
                    totals[key] = totals.get(key, 0) + value
                level_captures_pins_by_corpus.setdefault(fields[1], set()).add(fields[3])
            elif fields[0] == "gating" and len(fields) in (3, 4):
                # A corpus with no gating draw reports an empty list, an absent field.
                gating_corpora.add(fields[1])
                totals = gating_by_corpus.setdefault(fields[1], {})
                for key, value in value_oracle_fields(fields[2] if len(fields) == 4 else "").items():
                    totals[key] = totals.get(key, 0) + value
                gating_floors_by_corpus.setdefault(fields[1], set()).add(int(fields[-1]))
            elif fields[0] == "read-twins" and len(fields) == 4:
                read_twin_corpora.add(fields[3])
                read_twins_by_corpus[fields[3]] = read_twins_by_corpus.get(fields[3], 0) + int(fields[1])
                read_twins_pins_by_corpus.setdefault(fields[3], set()).add(int(fields[2]))
            elif fields[0] == "places-oracle" and len(fields) == 4:
                totals = places_oracle_by_corpus.setdefault(fields[3], [0, 0])
                totals[0] += int(fields[1])
                totals[1] += int(fields[2])
            elif fields[0] == "seam-mock-builders" and len(fields) == 3:
                seam_mock_builders_by_corpus[fields[2]] = seam_mock_builders_by_corpus.get(fields[2], 0) + int(fields[1])
            elif fields[0] == "builder-surface" and len(fields) >= 3:
                builder_surface_corpora.add(fields[1])
                counts = builder_surface_counts_by_corpus.setdefault(fields[1], {})
                for item in filter(None, fields[2].split(",")):
                    kind, count = item.split("=")
                    counts[kind] = counts.get(kind, 0) + int(count)
                # An empty list is an absent field, so a corpus that floors no kind reports three fields.
                builder_surface_floored_by_corpus.setdefault(fields[1], set()).add(fields[3] if len(fields) > 3 else "")
            elif fields[0] == "omitted-values" and len(fields) == 4:
                omitted_values_by_corpus[fields[3]] = omitted_values_by_corpus.get(fields[3], 0) + int(fields[1])
                omitted_values_pins_by_corpus.setdefault(fields[3], set()).add(int(fields[2]))
            elif fields[0] == "spellings" and len(fields) >= 2:
                # An empty list is an absent field, so a corpus that draws no spelling reports two fields.
                required_spellings_by_corpus.setdefault(fields[1], set()).update(filter(None, (fields[2] if len(fields) > 2 else "").split(",")))
                accepted_spellings_by_corpus.setdefault(fields[1], set()).update(filter(None, (fields[3] if len(fields) > 3 else "").split(",")))
            elif fields[0] == "features" and len(fields) >= 3:
                featured_corpora.add(fields[1])
                counts = feature_counts_by_corpus.setdefault(fields[1], {})
                for item in filter(None, fields[2].split(",")):
                    feature, count = item.split("=")
                    counts[feature] = counts.get(feature, 0) + int(count)
                # An empty list is an absent field, so a corpus that pins no feature reports three fields.
                feature_pins_by_corpus.setdefault(fields[1], set()).add(fields[3] if len(fields) > 3 else "")
            elif fields[0] == "outputs" and len(fields) >= 3:
                counts = output_counts_by_corpus.setdefault(fields[1], {})
                for item in filter(None, fields[2].split(",")):
                    feature, count = item.split("=")
                    counts[feature] = counts.get(feature, 0) + int(count)
                output_minimums_by_corpus.setdefault(fields[1], set()).add(fields[3] if len(fields) > 3 else "")
            elif fields[0] == "draws" and len(fields) >= 2:
                drawn_corpora.add(fields[1])
                counts = draw_counts_by_corpus.setdefault(fields[1], {})
                for item in filter(None, (fields[2] if len(fields) > 2 else "").split(",")):
                    draw, count = item.split("=")
                    counts[draw] = counts.get(draw, 0) + int(count)
                # An empty list is an absent field, so a corpus that counts no draw reports two fields.
                draw_pins_by_corpus.setdefault(fields[1], set()).add(fields[3] if len(fields) > 3 else "")
            elif fields[0] == "errors" and len(fields) >= 2:
                error_corpora.add(fields[1])
                counts = [int(count) for count in (fields[2] if len(fields) > 2 else "").split(",") if count]
                totals = error_counts_by_corpus.setdefault(fields[1], [0] * len(counts))
                error_counts_by_corpus[fields[1]] = [total + count for total, count in zip(totals, counts)] if len(totals) == len(counts) else counts
                error_pins_by_corpus.setdefault(fields[1], set()).add(fields[3] if len(fields) > 3 else "")
            elif fields[0] == "value-oracle" and len(fields) == 4:
                value_oracle_corpora.add(fields[1])
                totals = value_oracle_by_corpus.setdefault(fields[1], {})
                for key, value in value_oracle_fields(fields[2]).items():
                    totals[key] = (totals.get(key, 0) + value) % (1 << 64)
                value_oracle_pins_by_corpus.setdefault(fields[1], set()).add(fields[3])
            elif fields[0] == "cpu" and len(fields) == 6:
                cost = cost_by_corpus.setdefault(fields[1], {"shards": 0, "wall": 0.0, "longest wall": 0.0, "process": 0.0, "children": 0.0, "phases": {}})
                cost["shards"] += 1
                cost["wall"] += float(fields[2])
                cost["longest wall"] = max(cost["longest wall"], float(fields[2]))
                cost["process"] += float(fields[3])
                cost["children"] += float(fields[4])
                for item in filter(None, fields[5].split(",")):
                    phase, values = item.split("=")
                    busy, cpu, processes = values.split(":")
                    totals = cost["phases"].setdefault(phase, [0.0, 0.0, 0])
                    totals[0] += float(busy)
                    totals[1] += float(cpu)
                    totals[2] += int(processes)
            elif fields[0] == "completed":
                completed = True
            elif fields[0] in ("failure", "stale", "misfiled", "problem"):
                problems.append(f"{path}: {line.strip()}")
    if len(shard_lines) != 1 or not completed:
        problems.append(f"{path} has no complete shard result; that shard failed or did not finish.")
    else:
        for corpus in sorted(reported_corpora - featured_corpora):
            problems.append(f"The {corpus} corpus reported no per-feature counts in {path}.")
        for corpus in sorted(reported_corpora - inspected_corpora):
            problems.append(f"The {corpus} corpus reported no count of the graphs the value oracle inspected in {path}.")
        for corpus in sorted(reported_corpora - retention_corpora):
            problems.append(f"The {corpus} corpus reported no count of the graphs the retention oracle judged in {path}.")
        for corpus in sorted(reported_corpora - gating_corpora):
            problems.append(f"The {corpus} corpus reported no count of the graphs of its gating draws the oracles judged in {path}.")
        for corpus in sorted(reported_corpora - read_twin_corpora):
            problems.append(f"The {corpus} corpus reported no count of the graphs compared with their read twin in {path}.")
        for corpus in sorted(reported_corpora - builder_surface_corpora):
            problems.append(f"The {corpus} corpus reported no counts of the graphs the builder surface judged in {path}.")
        for corpus in sorted(reported_corpora - drawn_corpora):
            problems.append(f"The {corpus} corpus reported no counts of the draws it counts in accepted graphs in {path}.")
        for corpus in sorted(reported_corpora - error_corpora):
            problems.append(f"The {corpus} corpus reported no counts of the graphs each error it pins rejects in {path}.")
        # Only the base corpus has a value oracle of its own, which every long run of it reports.
        if "base" in reported_corpora and "base" not in value_oracle_corpora:
            problems.append(f"The base corpus reported nothing its value oracle compared in {path}.")
        # Only the seam corpus's level functions are floored, so only its long runs must report what the check judged.
        if SEAM_CORPUS in reported_corpora and SEAM_CORPUS not in level_captures_corpora:
            problems.append(f"The {SEAM_CORPUS} corpus reported no count of what the level function capture check judged in {path}.")
    for corpus, starting_seed, count, accepted_count, accepted_sum in shard_lines:
        shards_by_corpus.setdefault(corpus, []).append((starting_seed, count, accepted_count, accepted_sum))

if not report_paths:
    problems.append("No shard reports were found. The shards fail, or are skipped when \"Build Tests on Linux\" fails.")
if report_paths and not pins_by_corpus:
    problems.append("No report names its corpus and the corpus's pins, so nothing can be checked against them.")
for corpus in sorted(expected_corpora - set(pins_by_corpus)):
    problems.append(f"The {corpus} corpus has no report: its shards did not run, or their reports were not uploaded.")
for corpus, pins in sorted(pins_by_corpus.items()):
    if len(pins) > 1:
        problems.append(f"The shards of the {corpus} corpus disagree about its pins: {sorted(pins)}.")
if not problems:
    for corpus, pins in sorted(pins_by_corpus.items()):
        seed_count, pinned_accepted_count, pinned_accepted_sum = next(iter(pins))
        shards = shards_by_corpus.get(corpus, [])
        covered = []
        for starting_seed, count, _, _ in sorted(shards):
            covered.append((starting_seed, starting_seed + count))
        expected_start = 0
        for start, end in covered:
            if start != expected_start:
                problems.append(f"The shards do not cover the {corpus} corpus 0..<{seed_count} exactly once: {covered}.")
                break
            expected_start = end
        else:
            if expected_start != seed_count:
                problems.append(f"The shards cover 0..<{expected_start} of the {corpus} corpus, not 0..<{seed_count}.")
        inspected_pins = inspected_pins_by_corpus.get(corpus, set())
        if len(inspected_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about how many graphs the value oracle inspects: {sorted(inspected_pins)}.")
        elif inspected_pins and inspected_by_corpus.get(corpus, 0) != next(iter(inspected_pins)):
            problems.append(
                f"The value oracle inspected {inspected_by_corpus.get(corpus, 0)} graphs of the {corpus} corpus, but "
                f"{next(iter(inspected_pins))} are pinned."
            )
        retention_pins = retention_pins_by_corpus.get(corpus, set())
        if len(retention_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about the retention oracle's pins: {sorted(retention_pins)}.")
        elif retention_pins:
            pinned_retention = value_oracle_fields(next(iter(retention_pins)))
            retention = retention_by_corpus.get(corpus, {})
            mismatches = [
                f"{key} {retention.get(key, 0)} (pinned {pinned})"
                for key, pinned in sorted(pinned_retention.items())
                if retention.get(key, 0) != pinned
            ]
            if mismatches:
                problems.append(
                    f"The retention oracle judged, over the {corpus} corpus, other numbers than pinned (`retentionCounts`): "
                    f"{', '.join(mismatches)}."
                )
        level_captures_pins = level_captures_pins_by_corpus.get(corpus, set())
        if len(level_captures_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about the level function capture check's pins: {sorted(level_captures_pins)}.")
        elif level_captures_pins:
            pinned_level_captures = value_oracle_fields(next(iter(level_captures_pins)))
            level_captures = level_captures_by_corpus.get(corpus, {})
            mismatches = [
                f"{key} {level_captures.get(key, 0)} (pinned {pinned})"
                for key, pinned in sorted(pinned_level_captures.items())
                if level_captures.get(key, 0) != pinned
            ]
            if mismatches:
                problems.append(
                    f"The level function capture check judged, over the {corpus} corpus, other numbers than pinned "
                    f"(`levelFunctionCaptureCounts`): {', '.join(mismatches)}."
                )
        if corpus == SEAM_CORPUS:
            level_captures = level_captures_by_corpus.get(corpus, {})
            thin = [f"{key} {level_captures.get(key, 0)}" for key in LEVEL_CAPTURES_FLOORED_KEYS if level_captures.get(key, 0) < LEVEL_CAPTURES_FLOOR]
            if thin:
                problems.append(
                    f"The level function capture check judged fewer than {LEVEL_CAPTURES_FLOOR} graphs of the {corpus} corpus: "
                    f"{', '.join(thin)}. It gates nothing until that many are judged."
                )
        gating_floors = gating_floors_by_corpus.get(corpus, set())
        if len(gating_floors) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about the gating draws' floor: {sorted(gating_floors)}.")
        elif gating_floors:
            floor = next(iter(gating_floors))
            thin = [f"{draw} ({count})" for draw, count in sorted(gating_by_corpus.get(corpus, {}).items()) if count < floor]
            if thin:
                problems.append(
                    f"The oracles judged fewer than {floor} graphs of the {corpus} corpus that draw {', '.join(thin)}: "
                    "such a draw gates nothing until that many of its graphs are judged."
                )
        builder_surface_floored = builder_surface_floored_by_corpus.get(corpus, set())
        if len(builder_surface_floored) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about which builder surface kinds are floored: {sorted(builder_surface_floored)}.")
        elif builder_surface_floored:
            builder_surface_counts = builder_surface_counts_by_corpus.get(corpus, {})
            for kind in filter(None, next(iter(builder_surface_floored)).split(",")):
                if builder_surface_counts.get(kind, 0) < BUILDER_SURFACE_FLOOR:
                    problems.append(
                        f"The builder surface judged {builder_surface_counts.get(kind, 0)} graphs of the {corpus} corpus as {kind}, "
                        f"below its floor of {BUILDER_SURFACE_FLOOR}."
                    )
        read_twins_pins = read_twins_pins_by_corpus.get(corpus, set())
        if len(read_twins_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about how many graphs run as a read twin: {sorted(read_twins_pins)}.")
        elif read_twins_pins and read_twins_by_corpus.get(corpus, 0) != next(iter(read_twins_pins)):
            problems.append(
                f"The oracle compared {read_twins_by_corpus.get(corpus, 0)} graphs of the {corpus} corpus with their read twin, "
                f"but {next(iter(read_twins_pins))} are pinned."
            )
        capped_graphs, oracle_graphs = places_oracle_by_corpus.get(corpus, [0, 0])
        if capped_graphs > 0 and capped_graphs * 20 >= oracle_graphs:
            problems.append(
                f"The places oracle capped the passed-up cases of {capped_graphs} of the {oracle_graphs} seam graphs of the "
                f"{corpus} corpus, 5% or more: raise `SeamPlacesOracle.passedUpCaseLimit` to the percentile of passed-up cases "
                f"that compares 95% of graphs whole."
            )
        if corpus in seam_mock_builders_by_corpus and seam_mock_builders_by_corpus[corpus] < SEAM_MOCK_BUILDER_FLOOR:
            problems.append(
                f"The seam's own mock takes a builder that takes nothing in {seam_mock_builders_by_corpus[corpus]} accepted graphs of "
                f"the {corpus} corpus, below its floor of {SEAM_MOCK_BUILDER_FLOOR}."
            )
        omitted_values_pins = omitted_values_pins_by_corpus.get(corpus, set())
        if len(omitted_values_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about how many graphs the tool rejects for an omitted value: {sorted(omitted_values_pins)}.")
        elif omitted_values_pins and omitted_values_by_corpus.get(corpus, 0) != next(iter(omitted_values_pins)):
            problems.append(
                f"The tool rejected {omitted_values_by_corpus.get(corpus, 0)} graphs of the {corpus} corpus because a caller holds "
                f"a value its tier omits, but {next(iter(omitted_values_pins))} are pinned."
            )
        missing_spellings = required_spellings_by_corpus.get(corpus, set()) - accepted_spellings_by_corpus.get(corpus, set())
        if missing_spellings:
            problems.append(f"No accepted graph of the {corpus} corpus draws {', '.join(sorted(missing_spellings))}.")
        accepted_count = sum(shard[2] for shard in shards)
        accepted_sum = sum(shard[3] for shard in shards) % (1 << 64)
        error_pins = error_pins_by_corpus.get(corpus, set())
        if len(error_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about its error pins: {sorted(error_pins)}.")
        elif error_pins and next(iter(error_pins)):
            pinned_errors = [int(count) for count in next(iter(error_pins)).split(",")]
            if error_counts_by_corpus.get(corpus) != pinned_errors:
                problems.append(
                    f"The tool rejected {error_counts_by_corpus.get(corpus)} graphs of the {corpus} corpus with each error it "
                    f"pins, but {pinned_errors} are pinned."
                )
        draw_pins = draw_pins_by_corpus.get(corpus, set())
        if len(draw_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about its per-draw pins: {sorted(draw_pins)}.")
        elif draw_pins:
            pinned_draws = dict(item.split("=") for item in filter(None, next(iter(draw_pins)).split(",")))
            draw_counts = draw_counts_by_corpus.get(corpus, {})
            mismatches = []
            for draw in sorted(set(draw_counts) | set(pinned_draws)):
                count = draw_counts.get(draw, 0)
                if draw not in pinned_draws:
                    mismatches.append(f"{draw} {count} (no pin)")
                elif count != int(pinned_draws[draw]):
                    mismatches.append(f"{draw} {count} (pinned {pinned_draws[draw]})")
            if mismatches:
                problems.append(
                    f"The accepted graphs of the {corpus} corpus show these draws in other numbers than pinned: "
                    f"{', '.join(mismatches)}."
                )
        feature_pins = feature_pins_by_corpus.get(corpus, set())
        if len(feature_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about its per-feature pins: {sorted(feature_pins)}.")
        elif feature_pins and next(iter(feature_pins)):
            pinned_features = dict(item.split("=") for item in next(iter(feature_pins)).split(","))
            feature_counts = feature_counts_by_corpus.get(corpus, {})
            mismatches = []
            for feature in sorted(set(feature_counts) | set(pinned_features)):
                count = feature_counts.get(feature, 0)
                if feature not in pinned_features:
                    mismatches.append(f"{feature} {count} (no pin)")
                elif count != int(pinned_features[feature]):
                    mismatches.append(f"{feature} {count} (pinned {pinned_features[feature]})")
            if mismatches:
                problems.append(
                    f"The accepted graphs of the {corpus} corpus show these features in other numbers than pinned: "
                    f"{', '.join(mismatches)}. A generator or tool change that draws or accepts other graphs must update "
                    "the per-feature pins deliberately, with the hashes and the accepted-seed pins."
                )
        output_minimums = output_minimums_by_corpus.get(corpus, set())
        if len(output_minimums) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about its output features' minimum shares: {sorted(output_minimums)}.")
        elif output_minimums:
            output_counts = output_counts_by_corpus.get(corpus, {})
            for feature in NEW_BUILDER_OUTPUT_FEATURES:
                if output_counts.get(feature, 0) < NEW_BUILDER_OUTPUT_FLOOR:
                    problems.append(
                        f"The generated code of {output_counts.get(feature, 0)} accepted graphs of the {corpus} corpus shows {feature}, "
                        f"below its floor of {NEW_BUILDER_OUTPUT_FLOOR}."
                    )
            for item in filter(None, next(iter(output_minimums)).split(",")):
                feature, minimum = item.split("=")
                if output_counts.get(feature, 0) * 100 < int(minimum) * accepted_count:
                    problems.append(
                        f"The generated code of {output_counts.get(feature, 0)} of the {accepted_count} accepted graphs of the {corpus} "
                        f"corpus shows {feature}, fewer than the pinned {minimum} percent."
                    )
        value_oracle_pins = value_oracle_pins_by_corpus.get(corpus, set())
        if len(value_oracle_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about its value oracle's pins: {sorted(value_oracle_pins)}.")
        elif value_oracle_pins:
            pinned_value_oracle = value_oracle_fields(next(iter(value_oracle_pins)))
            value_oracle = value_oracle_by_corpus.get(corpus, {})
            mismatches = [
                f"{key} {value_oracle.get(key, 0):#x} (pinned {pinned:#x})" if key.endswith("Sum") else f"{key} {value_oracle.get(key, 0)} (pinned {pinned})"
                for key, pinned in sorted(pinned_value_oracle.items())
                if value_oracle.get(key, 0) != pinned
            ]
            if mismatches:
                problems.append(
                    f"The value oracle of the {corpus} corpus compared and skipped other pairs than its pins "
                    f"(`corpusValueOracleCounts`): {'; '.join(mismatches)}."
                )
        if (accepted_count, accepted_sum) != (pinned_accepted_count, pinned_accepted_sum):
            problems.append(
                f"The tool accepted {accepted_count} of seeds 0..<{seed_count} of the {corpus} corpus (sum 0x{accepted_sum:X}), but "
                f"{pinned_accepted_count} are pinned (sum 0x{pinned_accepted_sum:X}). A tool change that rejects or "
                "accepts different graphs must update that corpus's accepted-seed pins deliberately."
            )

with open(summary_path, "w") as summary:
    summary.write("### Graph fuzzer corpus\n\n")
    if problems:
        summary.writelines(f"- **Problem:** {problem}\n" for problem in problems)
    else:
        for corpus, shards in sorted(shards_by_corpus.items()):
            summary.write(f"{len(shards)} shards covered the whole {corpus} corpus, and the accepted set matches its pins.\n")
            if any(feature_pins_by_corpus.get(corpus, set())):
                summary.write(f"The accepted graphs of the {corpus} corpus show each feature the pinned number of times.\n")
            if any(draw_pins_by_corpus.get(corpus, set())):
                summary.write(f"The accepted graphs of the {corpus} corpus show each draw it counts the pinned number of times.\n")
            if inspected_by_corpus.get(corpus, 0) > 0:
                summary.write(
                    f"The value oracle inspected {inspected_by_corpus[corpus]} graphs of the {corpus} corpus and compared "
                    f"{compared_by_corpus.get(corpus, 0)} of them.\n"
                )
            if retention_by_corpus.get(corpus, {}).get("judged", 0) > 0:
                summary.write(f"The retention oracle judged {retention_by_corpus[corpus]['judged']} graphs with a hole of the {corpus} corpus.\n")
            if level_captures_by_corpus.get(corpus, {}).get("judged", 0) > 0:
                level_captures = level_captures_by_corpus[corpus]
                summary.write(
                    f"The level function capture check judged {level_captures['judged']} graphs of the {corpus} corpus with a level "
                    f"function ({level_captures.get('judgedWithNamed', 0)} with a member closure that names its parameter): "
                    f"{level_captures.get('named', 0)} such member closures, {level_captures.get('fills', 0)} fill functions, and "
                    f"{level_captures.get('conversions', 0)} conversion functions it does not judge.\n"
                )
            if read_twins_by_corpus.get(corpus, 0) > 0:
                summary.write(f"The oracle compared {read_twins_by_corpus[corpus]} graphs of the {corpus} corpus with their read twin.\n")
    for corpus, cost in sorted(cost_by_corpus.items()):
        summary.write(
            f"\n#### What the {corpus} corpus cost\n\n"
            f"{cost['shards']} shards ran for {cost['wall']:.0f} wall seconds in all, the longest for {cost['longest wall']:.0f}. "
            f"Their test processes used {cost['process']:.0f} CPU seconds and their child processes {cost['children']:.0f}.\n\n"
            "| Phase | Busy seconds | Child CPU seconds | Child processes |\n|---|---|---|---|\n"
        )
        for phase, (busy, cpu, processes) in cost["phases"].items():
            summary.write(f"| {phase} | {busy:.0f} | {cpu:.0f} | {processes} |\n")
step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
if step_summary:
    with open(summary_path) as summary, open(step_summary, "a") as job_summary:
        job_summary.write(summary.read())
sys.exit(1 if problems else 0)
