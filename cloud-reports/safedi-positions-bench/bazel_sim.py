#!/usr/bin/env python3
"""Runs `SafeDITool generate` per module as `bazel/safedi.bzl` does, and decides reruns as Bazel's action cache does.

An action reruns when the digest of any of its inputs changed. Inputs per the current rule: the module's sources and the
`.safedi` of every module beneath it (`transitive_module_infos`). Other input models are evaluated on the same runs:

  current       sources + every transitive `.safedi` file (what the rule declares today)
  unused        sources + direct `.safedi` + transitive ones the run may read (all of them for a module with a root or
                seam, none otherwise), as an `unused_inputs_list` would narrow it
  split         as current, but over the position-free part of each `.safedi` (the prototype's `<name>.safedi`)
  split+unused  both

The tool always runs with every input present; a model only changes which edits rerun an action.
"""
import hashlib, json, os, shutil, subprocess, sys

def sha(path):
	with open(path, "rb") as handle:
		return hashlib.sha256(handle.read()).hexdigest()

class Graph:
	def __init__(self, root):
		self.root = root
		self.order = [line.strip() for line in open(os.path.join(root, "order.txt")) if line.strip()]
		self.dependencies = {m: [l.strip() for l in open(os.path.join(root, m, "dependencies.txt")) if l.strip()] for m in self.order}
		self.transitive = {}
		for m in self.order:
			closure = set()
			for d in self.dependencies[m]:
				closure.add(d)
				closure |= self.transitive[d]
			self.transitive[m] = closure
		self.has_tree = {}
		for m in self.order:
			text = "".join(open(os.path.join(root, m, "Sources", f)).read() for f in sorted(os.listdir(os.path.join(root, m, "Sources"))))
			self.has_tree[m] = ("isRoot: true" in text) or ("generateDependencyTree: true" in text)

	def sources(self, m):
		directory = os.path.join(m, "Sources")
		return [os.path.join(directory, f) for f in sorted(os.listdir(os.path.join(self.root, directory)))]

	def dependents(self, m):
		return [x for x in self.order if m in self.transitive[x]]

class Runner:
	def __init__(self, graph, tool, out, split):
		self.graph, self.tool, self.out, self.split = graph, tool, out, split
		os.makedirs(os.path.join(graph.root, out), exist_ok=True)

	def path(self, m, suffix):
		return os.path.join(self.out, m + suffix)

	def run(self, m, timing_file=None):
		g = self.graph
		root = g.root
		with open(os.path.join(root, self.path(m, "_sources.csv")), "w") as handle:
			handle.write(",".join(g.sources(m)))
		arguments = [self.path(m, "_sources.csv"),
			"--combined-output", self.path(m, ".swift"),
			"--module-info-output", self.path(m, ".safedi"),
			"--compiler-receives-input-paths-unchanged",
			"--active-compilation-conditions", "DEBUG",
			"--module-name", m, "--package-name", open(os.path.join(root, m, "package.txt")).read().strip()]
		if g.dependencies[m]:
			with open(os.path.join(root, self.path(m, "_dep_module_infos.csv")), "w") as handle:
				handle.write(",".join(self.path(d, ".safedi") for d in g.dependencies[m]))
			# Bazel's depset order is not this one, but the tool orders module infos by path itself.
			with open(os.path.join(root, self.path(m, "_transitive_module_infos.csv")), "w") as handle:
				handle.write(",".join(self.path(d, ".safedi") for d in g.order if d in g.transitive[m]))
			arguments += ["--dependent-module-info-file-path", self.path(m, "_dep_module_infos.csv"),
				"--transitive-module-info-file-path", self.path(m, "_transitive_module_infos.csv")]
		if self.split:
			arguments += ["--split-module-info-positions", "--unused-inputs-list-output", self.path(m, ".unused")]
		command = [self.tool, "generate"] + arguments
		if timing_file:
			command = ["/usr/bin/time", "-v", "-o", timing_file] + command
		result = subprocess.run(command, cwd=root, capture_output=True, text=True)
		if result.returncode != 0:
			raise SystemExit(f"generate {m} failed:\n{result.stdout}\n{result.stderr}")
		return result.stdout + result.stderr

	def outputs(self, m):
		files = [".swift", ".safedi"] + ([".safedipositions", ".unused"] if self.split else [])
		return {s: sha(os.path.join(self.graph.root, self.path(m, s))) for s in files if os.path.exists(os.path.join(self.graph.root, self.path(m, s)))}

	def input_files(self, m):
		"""The `.safedi` inputs of m's action: each transitive module's file and, under the prototype, its sidecar."""
		files = []
		for d in self.graph.order:
			if d in self.graph.transitive[m]:
				files.append(self.path(d, ".safedi"))
				if self.split:
					files.append(self.path(d, ".safedipositions"))
		return files

	def unused_list(self, m):
		"""The inputs m's last run reported unused (prototype only)."""
		path = os.path.join(self.graph.root, self.path(m, ".unused"))
		return set(l.strip() for l in open(path) if l.strip()) if os.path.exists(path) else set()

	def input_digests(self, m, unused):
		"""Digest of the action's inputs under each model. `unused` is what m's previous run reported unused."""
		g = self.graph
		h_sources = hashlib.sha256()
		for s in g.sources(m):
			h_sources.update(s.encode() + b"\0" + open(os.path.join(g.root, s), "rb").read() + b"\0")
		def digest(files):
			h = h_sources.copy()
			for f in files:
				full = os.path.join(g.root, f)
				h.update(f.encode() + b"\0" + (sha(full) if os.path.exists(full) else "absent").encode())
			return h.hexdigest()
		files = self.input_files(m)
		result = {"current": digest(files)}
		if self.split:
			result["split+unused"] = digest([f for f in files if f not in unused])
		else:
			# What an `unused_inputs_list` without the split could drop: the files beneath that a module with no
			# root or seam never opens (an upper bound for modules with trees: every file beneath counts as read).
			used = set(g.dependencies[m]) | (g.transitive[m] if g.has_tree[m] else set())
			result["unused"] = digest([f for f in files if os.path.basename(f)[:-len(".safedi")] in used])
		return result

def parse_time(path):
	user = wall = 0.0
	for line in open(path):
		line = line.strip()
		if line.startswith("User time (seconds):"):
			user = float(line.split(":")[1])
		elif line.startswith("Elapsed (wall clock) time"):
			value = line.split("):", 1)[1].strip()
			parts = [float(p) for p in value.split(":")]
			wall = parts[-1] + (parts[-2] * 60 if len(parts) > 1 else 0) + (parts[-3] * 3600 if len(parts) > 2 else 0)
	return user, wall
