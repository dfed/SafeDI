#!/usr/bin/env python3
"""usage: cycle_cells.py TOOL VPROBES_DIR OUT.swift — the mock cycle kind's acceptance cells (see cells.py)."""
import sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
from cells import cell, spec_source, test_file

tool, vprobes, out_path = sys.argv[1:4]
import os
here = os.path.dirname(os.path.abspath(__file__))


def ring(count, wrapper="Instantiator"):
    types = {"Root": [["t0Builder", wrapper, "T0"]]}
    for index in range(count):
        types[f"T{index}"] = [[f"t{(index + 1) % count}Builder", wrapper, f"T{(index + 1) % count}"]]
    return types


def next_three(count, wrappers=None, root=True):
    types = {"Root": [["t0Builder", "Instantiator", "T0"]]} if root else {}
    for index in range(count):
        wrapper = (wrappers or {}).get(index, "Instantiator")
        types[f"T{index}"] = [[f"t{(index + step) % count}Builder", wrapper, f"T{(index + step) % count}"] for step in (1, 2, 3)]
    return types


def tangle(count, includingSelf):
    types = {"Root": [["t0Builder", "Instantiator", "T0"]]}
    for index in range(count):
        types[f"T{index}"] = [[f"t{other}Builder", "Instantiator", f"T{other}"] for other in range(count) if includingSelf or other != index]
    return types


def from_spec(name, spec, cycle_length, root_arguments="", comment=""):
    c = cell(tool, name, {"Types.swift": spec_source(spec)}, spec["root"], root_arguments=root_arguments, cycle_length=cycle_length)
    c["comment"] = comment
    return c


def from_files(name, directory, files, root, cycle_length, comment, extra_probes=()):
    sources = {file: open(f"{vprobes}/{directory}/{file}").read().replace(' print("State()") ', " ") for file in files}
    c = cell(tool, name, sources, root, cycle_length=cycle_length, extra_probes=extra_probes)
    c["comment"] = comment
    return c


cells = []
# The seven cycles of the rule's evidence, each entered from beneath the root.
cells.append(from_spec("mock_buildsWalksValues_whenEachOfFiveTypesBuildsTheNextThree", {"root": "Root", "types": next_three(5)}, 5,
                       comment="Five types, each builds the next three through `Instantiator`s: the lap-two difference."))
cells.append(from_spec("mock_buildsWalksValues_whenEachOfTenTypesBuildsTheNextThree", {"root": "Root", "types": next_three(10)}, 10,
                       comment="Ten types, each builds the next three."))
cells.append(from_spec("mock_buildsWalksValues_whenRingOfTenTypesBuildsTheNext", {"root": "Root", "types": ring(10)}, 10,
                       comment="A ring of ten `Instantiator`s."))
cells.append(from_spec("mock_buildsWalksValues_whenRingOfThirtyTypesBuildsTheNext", {"root": "Root", "types": ring(30)}, 30,
                       comment="A ring of thirty `Instantiator`s."))
for name, fixture, length, comment in [
    ("mock_buildsWalksValues_whenEvenTypesOfFiveTypeCycleHoldSendableInstantiators", "mixed5", 5, "Five types, each builds the next three, the even ones through `SendableInstantiator`s: types reached under two properties, across `@Sendable` functions."),
    ("mock_buildsWalksValues_whenEvenTypesOfSixTypeCycleHoldSendableInstantiators", "mixed6", 6, "Six types, each builds the next three, the even ones through `SendableInstantiator`s."),
    ("mock_buildsWalksValues_whenOneTypeOfSevenTypeCycleHoldsSendableInstantiators", "late7", 7, "Seven types, each builds the next three, only `T4` through `SendableInstantiator`s."),
]:
    source = open(f"/mnt/project-files/lanes/mock-switch/nearest-forms/fixtures/{fixture}/App/Types.swift").read()
    c = cell(tool, name, {"Types.swift": source}, "Hub", root_arguments='id: "id"', cycle_length=length)
    c["comment"] = comment
    cells.append(c)
# The four-type graph and the tangles.
cells.append(from_spec("mock_buildsWalksValues_whenEachOfFourTypesBuildsEveryOther", {"root": "Root", "types": tangle(4, includingSelf=False)}, 4,
                       comment="Four types, each builds every other: the four-type graph."))
cells.append(from_spec("mock_buildsWalksValues_whenEachOfThreeTypesBuildsEveryMemberAndItself", {"root": "Root", "types": tangle(3, includingSelf=True)}, 3,
                       comment="A three-member all-to-all tangle, each member building itself too."))
cells.append(from_spec("mock_buildsWalksValues_whenEachOfFourTypesBuildsEveryMemberAndItself", {"root": "Root", "types": tangle(4, includingSelf=True)}, 4,
                       comment="A four-member all-to-all tangle, each member building itself too."))
# Where the cycle is entered.
cells.append(from_spec("mock_buildsWalksValues_whenMockRootIsInsideItsOwnCycle", {"root": "T0", "types": next_three(5, root=False)}, 5,
                       comment="The mock’s root is a member of its cycle: a step back to its type enters a new place."))
both = next_three(5)
both["Root"] = [["t0Builder", "Instantiator", "T0"], ["entry", "", "Entry"]]
both["Entry"] = [["t2Builder", "Instantiator", "T2"]]
cells.append(from_spec("mock_buildsWalksValues_whenCycleIsEnteredFromRootAndFromBeneathIt", {"root": "Root", "types": both}, 5,
                       comment="`Root` enters the cycle at `T0`, and the `Entry` it builds enters it at `T2`."))
# One type under two labels, and across `@Sendable` functions.
two_labels = {"root": "Root", "types": {
    "Root": [["t0Builder", "Instantiator", "T0"]],
    "T0": [["t1Builder", "Instantiator", "T1"], ["sendableT1Builder", "SendableInstantiator", "T1"]],
    "T1": [["t2Builder", "SendableInstantiator", "T2"]],
    "T2": [["t0Builder", "Instantiator", "T0"], ["t1Builder", "Instantiator", "T1"]],
}}
cells.append(from_spec("mock_buildsWalksValues_whenCycleTypeIsBuiltUnderTwoLabels", two_labels, 3,
                       comment="`T1` is built under `t1Builder` and `sendableT1Builder`, so a new place of it takes the nearest configuration of its type."))
sendable_ring = {"root": "Root", "sendable": ["Root"] + [f"T{index}" for index in range(5)], "types": ring(5, "SendableInstantiator")}
cells.append(from_spec("mock_buildsWalksValues_whenRingOfSendableClassesCrossesSendableFunctions", sendable_ring, 5,
                       comment="A ring of `SendableInstantiator`s of `Sendable` classes: every function on the cycle is `@Sendable`."))
struct_ring = {"root": "Root", "structs": ["Root"] + [f"T{index}" for index in range(5)], "types": ring(5, "SendableInstantiator")}
cells.append(from_spec("mock_buildsWalksValues_whenRingOfSendableStructsCrossesSendableFunctions", struct_ring, 5,
                       comment="The same ring of `Sendable` structs."))
# Lazy closing and twins (the lazy kind's records).
cells.append(from_spec("mock_buildsWalksValues_whenCycleClosesOnLazilyInstantiated", {"root": "Hub", "types": {
    "Hub": [["t0", "LazilyInstantiated", "T0"]],
    "T0": [["t1Builder", "Instantiator", "T1"], ["t2Builder", "Instantiator", "T2"]],
    "T1": [["t0", "LazilyInstantiated", "T0"], ["t2Builder", "Instantiator", "T2"]],
    "T2": [["t0", "LazilyInstantiated", "T0"], ["t1Builder", "Instantiator", "T1"]]}}, 3,
    comment="Each member closes the cycle on the `LazilyInstantiated<T0>` `Hub` declares."))
cells.append(from_spec("mock_buildsWalksValues_whenCycleRunsThroughLazyWrappersAndTypeIsBuiltUnderTwoLabels", {"root": "Hub", "types": {
    "Hub": [["t0Builder", "Instantiator", "T0"]],
    "T0": [["t1", "LazilyInstantiated", "T1"], ["t2Builder", "Instantiator", "T2"]],
    "T1": [["t2Builder", "Instantiator", "T2"], ["t0Builder", "Instantiator", "T0"], ["other", "Instantiator", "T0"]],
    "T2": [["t0Builder", "Instantiator", "T0"], ["t1", "LazilyInstantiated", "T1"], ["t1Builder", "Instantiator", "T1"]]}}, 3,
    comment="A cycle through lazy wrappers, `T0` built under `t0Builder` and `other`."))
cells.append(from_spec("mock_buildsWalksValues_whenValueAndItsLazyTwinShareOneSlotAndOneIsOffTheCycle", {"root": "Hub", "types": {
    "Hub": [["aBuilder", "Instantiator", "A"], ["bBuilder", "Instantiator", "B"]],
    "A": [["t0", "", "T0"], ["cBuilder", "Instantiator", "C"]],
    "B": [["t0", "LazilyInstantiated", "T0"], ["cBuilder", "Instantiator", "C"]],
    "C": [["t0", "", "T0"]],
    "T0": [["aBuilder", "Instantiator", "A"], ["bBuilder", "Instantiator", "B"], ["again", "Instantiator", "A"], ["other", "Instantiator", "B"]]}}, 4,
    comment="Twins: `t0: T0` and `t0: LazilyInstantiated<T0>` are one place, whichever the path entered first."))
# The value harness's nine graphs that differed from 2.4.0 on the mock writer (V1 to V3).
for name, directory, files, root, length, comment, *extra in [
    ("mock_buildsWalksValues_whenReenteredLazyCycleBuildsFreshDefault", "ms-probe-values/h5", ["A.swift"], "Profile", 2, "V1 (h5): a re-entered cycle builds a fresh `State` default, as 2.4.0 does.", ["{ let p0 = Profile.mock(); let p1 = p0.followersBuilder.instantiate().profileBuilder.instantiate(); let p2 = p1.followersBuilder.instantiate().profileBuilder.instantiate(); let p3 = p2.followersBuilder.instantiate().profileBuilder.instantiate(); return [p0.state === p1.state, p1.state === p2.state, p2.state === p3.state] }()"]),
    ("mock_buildsWalksValues_whenReenteredCycleBuildsFreshDefaultBeneathSibling", "ms-probe-values/h7", ["A.swift"], "Profile", 2, "V1 (h7): the same beneath `settingsBuilder`.", ["{ let p0 = Profile.mock(); let p1 = p0.followersBuilder.instantiate().profileBuilder.instantiate(); let p2 = p1.followersBuilder.instantiate().profileBuilder.instantiate(); return [p0.settingsBuilder.instantiate().state === p1.settingsBuilder.instantiate().state, p1.settingsBuilder.instantiate().state === p2.settingsBuilder.instantiate().state, p2.settingsBuilder.instantiate().state === p2.settingsBuilder.instantiate().state] }()"]),
    ("mock_buildsWalksValues_whenBuilderIsReachedThroughDeeperPath", "ms-probe-values/h11", ["A.swift"], "App", 3, "V2 (h11): a builder reached through a deeper path reads the deeper override."),
    ("mock_buildsWalksValues_whenBuilderIsReachedThroughDeeperPathOnLapTwo", "ms-probe-ref-lap2/h11", ["G.swift"], "App", 3, "V2 (lap two of h11)."),
    ("mock_buildsWalksValues_whenBuilderOfPublicPropertiesIsReachedThroughDeeperPathOnLapTwo", "ms-probe-ref-lap2/h11b", ["G.swift"], "App", 3, "V2 (lap two of h11, public properties)."),
    ("mock_buildsWalksValues_whenBuilderOfInternalPropertiesIsReachedThroughDeeperPath", "ms-probe-refute-oracle/w/h11", ["G.swift"], "App", 3, "V2 (h11 as the oracle’s refutation wrote it)."),
    ("mock_buildsWalksValues_whenSiblingOfCycleReadsItsOwnOverride", "ms-probe-values/h16", ["A.swift"], "App", 3, "V3 (h16): `footer` reads its own override, not its sibling `header`’s."),
    ("mock_buildsWalksValues_whenSiblingOfCycleReadsItsOwnOverrideOnLapTwo", "ms-probe-ref-lap2/h16", ["G.swift"], "App", 3, "V3 (lap two of h16)."),
    ("mock_buildsWalksValues_whenSiblingOfPublicPropertiesReadsItsOwnOverrideOnLapTwo", "ms-probe-ref-lap2/h16b", ["G.swift"], "App", 3, "V3 (lap two of h16, public properties)."),
]:
    cells.append(from_files(name, directory, files, root, length, comment, extra[0] if extra else ()))

# The draws lane's D1 and D4: an actor, and an unfulfilled `@Instantiated(onlyIfAvailable:)`, named apart on a lazy cycle.
d1 = open(os.path.join(here, "fixtures", "D1.swift")).read()
c = cell(tool, "mock_compilesAndBuildsWalksValues_whenActorNamedApartSitsOnLazyCycle", {"Types.swift": d1}, "Host", cycle_length=2,
         extra_probes=["{ let host = Host.mock(); return host.peer.node === host.peer.node }()"])
c["comment"] = "D1: `Node`, an actor, is on the cycle through `Loop` and is named apart from `Peer`’s `node: Other`. Neither path compiles today (2.4.1 fails the same way): the cycle kind’s cell."
c["knownIssue"] = "D1: the function that closes the lazy cycle captures the actor’s builder, which reads overrides that are not Sendable"
cells.append(c)
d4 = open(os.path.join(here, "fixtures", "D4.swift")).read()
c = cell(tool, "mock_readsOnlyIfAvailableOverride_whenUnfulfilledDependencyIsNamedApartOnLazyCycle", {"Types.swift": d4}, "Host", cycle_length=2,
         extra_probes=[
             "{ let token = Token(); return Host.mock(safeDIOverrides: .init(token: token)).node.token === token }()",
             "{ let token = Token(); return Host.mock(safeDIOverrides: .init(token: token)).node.loopBuilder.instantiate().node.token === token }()",
             "{ let token = Token(); return Host.mock(safeDIOverrides: .init(token: token)).node.loopBuilder.instantiate().node.loopBuilder.instantiate().node.token === token }()",
             "Host.mock().node.loopBuilder.instantiate().node.token == nil",
         ])
c["comment"] = "D4: `Node`’s unfulfilled `token` is offered as an override, and read on every lap of the cycle."
cells.append(c)

# W2: which emission a lazy cycle's members got on the mock writer followed type names. Both namings.
for suffix, file in (("WhenMemberNameSortsFirst", "W2.swift"), ("WhenMemberNameSortsLast", "W2Zeta.swift")):
    c = cell(tool, "mock_buildsWalksValues_whenLazyCycleOfSendableBuildersPassesItselfOnlyIfAvailable" + "And" + suffix.removeprefix("When"), {"Types.swift": open(os.path.join(here, "fixtures", file)).read()}, "Beta", cycle_length=2)
    c["comment"] = "W2: `Beta`’s mock builds `Alpha` (renamed `Zeta` in the other cell, so it sorts after `Beta`), which builds `Beta` again, passed itself only if available."
    cells.append(c)

header = open(__import__("os").path.join(__import__("os").path.dirname(__file__), "cycle_header.swift")).read().rstrip("\n")
open(out_path, "w").write(test_file(cells, header))
print(len(cells), "cells")
