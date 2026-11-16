// Adds to this run's file of passed compile checks the checks that other runs of this repository passed under the
// same identity, read from the `passed-compile-checks-v1-<os>-<identity>` artifacts those runs uploaded
// (`.github/actions/upload-passed-compile-checks`). An artifact is readable from every branch and pull request,
// where a cache is readable only from its own branch and main, and a `workflow_run` workflow that follows a pull
// request's run may not save a cache at all, so a pull request's passes reached no other run through one.
//
// A line is added only when all of these hold, and anything else leaves the run to compile the check:
// - the artifact's run is of this repository, not a fork, and ran this repository's `ci.yml` or `verify.yml`;
// - the artifact's name and its `identity.txt` both give this job's identity
//   (`.github/scripts/compile-check-identity.sh`);
// - the line is a SHA-256, as `PassedCompileCheckCache.key` writes one.
// A run uploads only the checks its own test processes passed, so no line here was ever restored by its uploader.
// Nothing here fails a job: whatever goes wrong is a warning, and the checks compile.
//
// What it costs: the token of a workflow may make 1,000 requests an hour for the whole repository, so this makes one
// request to list the artifacts of this job's identity (the name holds the identity, so GitHub does the filtering),
// and two for each of the newest `artifactsToRead` it has not read before: `artifacts-read.txt`, beside the list and
// cached with it, names the artifacts whose lines the list already holds. It reads nothing when few requests are
// left, and prints how many it made.
//
// To remove a check that should not have passed, "Share Passed Compile Checks" (share-compile-checks.yml) says what to
// delete; `artifactVersion` is the `v1` it names.
//
// `node restore-from-artifacts.js --self-test DIRECTORY` checks all of this against fixtures; "Check Line Coverage on Linux"
// runs it.

'use strict'

const fs = require('fs')
const path = require('path')
const zlib = require('zlib')

// Changing this leaves every artifact uploaded so far unread. `.github/actions/upload-passed-compile-checks` and
// share-compile-checks.yml spell the same name.
const artifactVersion = 'v1'
// The newest artifacts of this job's identity that are read. A stack's top run needs the runs below it and main's,
// and every one of these is of the same identity, so this is a stack and the Verify runs beside it.
const artifactsToRead = 15
// One page of the listing. More artifacts of one identity than this within the seven days they are kept would leave
// the oldest unlisted, which only costs compiles.
const artifactsToList = 100
// With fewer requests than this left in the hour, nothing is read: the rest belong to the steps that fail without
// them.
const requestsToLeave = 300
// After this long, what was read is kept and the rest is left to compile. Reading 30 artifacts took 11.5 and 15.2
// seconds (Verify runs 43952868099 and 43954840461).
const timeLimitInMilliseconds = 90_000
// A list of 3,400 keys is 220 KB, so nothing this repository uploads comes near.
const largestFileInBytes = 8 * 1024 * 1024
const workflowsWhoseArtifactsCount = ['.github/workflows/ci.yml', '.github/workflows/verify.yml']
const keyPattern = /^[0-9a-f]{64}$/

/// The files of a zip archive, by name. Reads sizes and offsets from the central directory, since an archive
/// written as a stream (as `actions/upload-artifact` writes one) leaves them out of each file's own header.
function filesInZip(archive) {
	let end = -1
	for (let offset = archive.length - 22; offset >= Math.max(0, archive.length - 22 - 65535); offset -= 1) {
		if (archive.readUInt32LE(offset) === 0x06054b50) {
			end = offset
			break
		}
	}
	if (end < 0) {
		throw new Error('the archive has no central directory')
	}
	const count = archive.readUInt16LE(end + 10)
	let entry = archive.readUInt32LE(end + 16)
	const files = new Map()
	for (let index = 0; index < count; index += 1) {
		if (archive.readUInt32LE(entry) !== 0x02014b50) {
			throw new Error('the archive’s central directory is not one')
		}
		const method = archive.readUInt16LE(entry + 10)
		const compressedSize = archive.readUInt32LE(entry + 20)
		const size = archive.readUInt32LE(entry + 24)
		const nameLength = archive.readUInt16LE(entry + 28)
		const extraLength = archive.readUInt16LE(entry + 30)
		const commentLength = archive.readUInt16LE(entry + 32)
		const header = archive.readUInt32LE(entry + 42)
		const name = archive.toString('utf8', entry + 46, entry + 46 + nameLength)
		if (archive.readUInt32LE(header) !== 0x04034b50) {
			throw new Error(`${name} has no header in the archive`)
		}
		if (size > largestFileInBytes || compressedSize > largestFileInBytes) {
			throw new Error(`${name} is larger than any list of passed checks`)
		}
		const start = header + 30 + archive.readUInt16LE(header + 26) + archive.readUInt16LE(header + 28)
		if (start + compressedSize > archive.length) {
			throw new Error(`${name} ends after the archive does`)
		}
		const stored = archive.subarray(start, start + compressedSize)
		if (method === 0) {
			files.set(name, Buffer.from(stored))
		} else if (method === 8) {
			files.set(name, zlib.inflateRawSync(stored, { maxOutputLength: largestFileInBytes }))
		} else {
			throw new Error(`${name} is compressed in a way this script does not read`)
		}
		entry += 46 + nameLength + extraLength + commentLength
	}
	return files
}

/// The name a run's list of passed checks is uploaded under.
function artifactName(os, identity) {
	return `passed-compile-checks-${artifactVersion}-${os}-${identity}`
}

/// Reads the artifacts and merges their lines into `<directory>/passed.txt`. Returns what it printed, for the
/// self-test. `github` is an Octokit client, `context` the workflow's context, and `core` what warns.
async function restore({ github, context, core, identity, os, directory, now = Date.now }) {
	const started = now()
	const file = path.join(directory, 'passed.txt')
	const fileOfArtifactsRead = path.join(directory, 'artifacts-read.txt')
	const reason = 'so this run compiles every check its own cache does not hold'
	if (!keyPattern.test(identity || '')) {
		core.warning(`This job’s compile check identity is not a SHA-256, ${reason}.`)
		return null
	}
	const owner = context.repo.owner
	const repo = context.repo.repo
	const repositoryID = context.payload.repository && context.payload.repository.id
	let requests = 0
	let listed
	try {
		if (!repositoryID) {
			throw new Error('the event names no repository')
		}
		requests += 1
		const response = await github.rest.actions.listArtifactsForRepo({ owner, repo, name: artifactName(os, identity), per_page: artifactsToList })
		listed = response.data.artifacts
		const left = Number(response.headers && response.headers['x-ratelimit-remaining'])
		if (left < requestsToLeave) {
			core.warning(`Only ${left} requests are left to this repository’s workflows this hour, so other runs’ passed compile checks are left unread and this run compiles every check its own cache does not hold.`)
			return null
		}
	} catch (error) {
		core.warning(`Could not list other runs’ passed compile checks, ${reason}: ${error.message}`)
		return null
	}

	const linesOf = name => (fs.existsSync(name) ? fs.readFileSync(name, 'utf8').split('\n').filter(line => line !== '') : [])
	const own = linesOf(file)
	const together = new Set(own)
	const linesAlreadyHere = together.size
	// Only a list that is here can hold what an artifact added to it.
	const readBefore = new Set(own.length > 0 ? linesOf(fileOfArtifactsRead) : [])
	const counts = { read: 0, readBefore: 0, older: 0, expired: 0, ofThisRun: 0, ofAFork: 0, ofAnotherIdentity: 0, ofAnotherWorkflow: 0, unreadable: 0, leftUnread: 0 }
	// Those another run of this repository uploaded, newest first, whatever order the listing came in.
	const candidates = []
	for (const artifact of listed) {
		const run = artifact.workflow_run
		if (artifact.expired) {
			counts.expired += 1
		} else if (!run || run.head_repository_id !== repositoryID || run.repository_id !== repositoryID) {
			counts.ofAFork += 1
		} else if (run.id === context.runId) {
			// An earlier attempt's passes came back with this run's own cache.
			counts.ofThisRun += 1
		} else {
			candidates.push(artifact)
		}
	}
	candidates.sort((first, second) => String(second.created_at).localeCompare(String(first.created_at)) || second.id - first.id)
	counts.older = Math.max(0, candidates.length - artifactsToRead)
	const settled = []
	let firstFailure = null
	const whetherRunCounts = new Map()
	for (const artifact of candidates.slice(0, artifactsToRead)) {
		if (readBefore.has(String(artifact.id))) {
			counts.readBefore += 1
			settled.push(artifact.id)
			continue
		}
		if (now() - started > timeLimitInMilliseconds) {
			counts.leftUnread += 1
			continue
		}
		const run = artifact.workflow_run
		try {
			if (artifact.size_in_bytes > largestFileInBytes) {
				throw new Error('the artifact is larger than any list of passed checks')
			}
			if (!whetherRunCounts.has(run.id)) {
				requests += 1
				const response = await github.rest.actions.getWorkflowRun({ owner, repo, run_id: run.id })
				whetherRunCounts.set(
					run.id,
					workflowsWhoseArtifactsCount.includes(response.data.path)
						&& Boolean(response.data.head_repository)
						&& response.data.head_repository.id === repositoryID,
				)
			}
			if (!whetherRunCounts.get(run.id)) {
				counts.ofAnotherWorkflow += 1
				settled.push(artifact.id)
				continue
			}
			requests += 1
			const download = await github.rest.actions.downloadArtifact({ owner, repo, artifact_id: artifact.id, archive_format: 'zip' })
			const files = filesInZip(Buffer.from(download.data))
			const artifactIdentity = files.get('identity.txt')
			const passed = files.get('passed.txt')
			if (!artifactIdentity || !passed) {
				throw new Error('the artifact holds no identity or no passed checks')
			}
			if (artifactIdentity.toString('utf8').split('\n')[0] !== identity) {
				counts.ofAnotherIdentity += 1
				settled.push(artifact.id)
				continue
			}
			for (const line of passed.toString('utf8').split('\n')) {
				if (keyPattern.test(line)) {
					together.add(line)
				}
			}
			counts.read += 1
			settled.push(artifact.id)
		} catch (error) {
			counts.unreadable += 1
			firstFailure = firstFailure || `artifact ${artifact.id}: ${error.message}`
		}
	}

	// Whenever a line is new. The file may hold a line twice, so its length does not say.
	if (together.size > linesAlreadyHere) {
		fs.mkdirSync(directory, { recursive: true })
		const merged = path.join(directory, 'merged.txt')
		fs.writeFileSync(merged, [...together].sort().join('\n') + '\n')
		fs.renameSync(merged, file)
	}
	// After the list, so that an artifact is never named as read while the list lacks its lines.
	if (fs.existsSync(file)) {
		fs.writeFileSync(fileOfArtifactsRead, settled.map(id => `${id}\n`).join(''))
	}
	if (counts.unreadable > 0) {
		core.warning(`Could not read ${counts.unreadable} of other runs’ lists of passed compile checks, so this run compiles what only they hold. The first: ${firstFailure}`)
	}
	if (counts.leftUnread > 0) {
		core.warning(`Reading other runs’ passed compile checks took over ${timeLimitInMilliseconds / 1000} seconds, so ${counts.leftUnread} lists were left unread and this run compiles what only they hold.`)
	}
	const skipped = [
		[counts.readBefore, 'read by an earlier run'],
		[counts.older, `older than the newest ${artifactsToRead}`],
		[counts.ofThisRun, 'of this run'],
		[counts.ofAnotherIdentity, 'of another identity'],
		[counts.ofAFork, 'of a fork’s run'],
		[counts.ofAnotherWorkflow, 'of a run that is not this repository’s CI or Verify'],
		[counts.expired, 'expired'],
		[counts.unreadable, 'unreadable'],
		[counts.leftUnread, 'left unread'],
	].filter(([count]) => count > 0).map(([count, what]) => `${count} ${what}`)
	const summary = `Passed compile checks: ${linesAlreadyHere} already here, ${together.size} with the lists of ${counts.read} other runs`
		+ ` (${listed.length} artifacts of this identity${skipped.length > 0 ? ': ' + skipped.join(', ') : ''}),`
		+ ` in ${requests} requests and ${((now() - started) / 1000).toFixed(1)} seconds.`
	core.info(summary)
	return summary
}

module.exports = restore

// MARK: Self-test

/// A zip archive of `files`, written as a stream writes one when `streamed`: each file's own header gives no sizes.
function zip(files, { streamed = true, compressed = true } = {}) {
	const parts = []
	const directory = []
	let offset = 0
	for (const [name, content] of Object.entries(files)) {
		const data = Buffer.from(content)
		const stored = compressed ? zlib.deflateRawSync(data) : data
		const header = Buffer.alloc(30)
		header.writeUInt32LE(0x04034b50, 0)
		header.writeUInt16LE(streamed ? 8 : 0, 6)
		header.writeUInt16LE(compressed ? 8 : 0, 8)
		header.writeUInt32LE(streamed ? 0 : stored.length, 18)
		header.writeUInt32LE(streamed ? 0 : data.length, 22)
		header.writeUInt16LE(Buffer.byteLength(name), 26)
		const entry = Buffer.alloc(46)
		entry.writeUInt32LE(0x02014b50, 0)
		entry.writeUInt16LE(compressed ? 8 : 0, 10)
		entry.writeUInt32LE(stored.length, 20)
		entry.writeUInt32LE(data.length, 24)
		entry.writeUInt16LE(Buffer.byteLength(name), 28)
		entry.writeUInt32LE(offset, 42)
		directory.push(entry, Buffer.from(name))
		const descriptor = streamed ? Buffer.alloc(16) : Buffer.alloc(0)
		parts.push(header, Buffer.from(name), stored, descriptor)
		offset += 30 + Buffer.byteLength(name) + stored.length + descriptor.length
	}
	const directoryBytes = Buffer.concat(directory)
	const end = Buffer.alloc(22)
	end.writeUInt32LE(0x06054b50, 0)
	end.writeUInt16LE(Object.keys(files).length, 8)
	end.writeUInt16LE(Object.keys(files).length, 10)
	end.writeUInt32LE(directoryBytes.length, 12)
	end.writeUInt32LE(offset, 16)
	return Buffer.concat([...parts, directoryBytes, end])
}

/// Checks `restore` against fixtures it writes under `scratch`, a directory it makes and removes.
async function selfTest(scratch) {
	const assert = require('assert')
	const identity = 'a'.repeat(64)
	const key = digit => String(digit).repeat(64)
	const repositoryID = 7
	let cases = 0

	/// Runs `restore` against `artifacts` (each `{ files | archive, run, expired, path, headRepositoryID, size, created }`,
	/// listed newest first unless `created` says otherwise) with `existing` in the file and `existingRead` in the file of
	/// artifacts read, and returns both files, the warnings, the summary and the requests made.
	async function run({ artifacts, existing = null, existingRead = null, identityOfJob = identity, failListing = false, clock = null, requestsLeft = '900' }) {
		cases += 1
		const directory = path.join(scratch, `case-${cases}`)
		fs.mkdirSync(directory, { recursive: true })
		try {
			const file = path.join(directory, 'checks', 'passed.txt')
			if (existing !== null) {
				fs.mkdirSync(path.dirname(file))
				fs.writeFileSync(file, existing)
			}
			if (existingRead !== null) {
				fs.mkdirSync(path.dirname(file), { recursive: true })
				fs.writeFileSync(path.join(path.dirname(file), 'artifacts-read.txt'), existingRead)
			}
			const warnings = []
			const requested = []
			const downloaded = []
			const github = { rest: { actions: {
				listArtifactsForRepo: async parameters => {
					requested.push(parameters)
					if (failListing) {
						throw new Error('Resource not accessible by integration')
					}
					return { headers: { 'x-ratelimit-remaining': requestsLeft }, data: { artifacts: artifacts.map((artifact, index) => ({
						id: index,
						expired: artifact.expired === true,
						size_in_bytes: artifact.size === undefined ? 300 : artifact.size,
						created_at: new Date(1_800_000_000_000 - 1000 * (artifact.created === undefined ? index : artifact.created)).toISOString(),
						workflow_run: artifact.run === null ? null : {
							id: artifact.run === undefined ? 100 + index : artifact.run,
							head_repository_id: artifact.headRepositoryID === undefined ? repositoryID : artifact.headRepositoryID,
							repository_id: repositoryID,
						},
					})) } }
				},
				downloadArtifact: async ({ artifact_id }) => {
					downloaded.push(artifact_id)
					const artifact = artifacts[artifact_id]
					const archive = artifact.archive || zip(artifact.files)
					return { data: archive.buffer.slice(archive.byteOffset, archive.byteOffset + archive.length) }
				},
				getWorkflowRun: async ({ run_id }) => {
					const artifact = artifacts.find((candidate, index) => (candidate.run === undefined ? 100 + index : candidate.run) === run_id)
					return { data: {
						path: artifact.path || '.github/workflows/ci.yml',
						head_repository: { id: artifact.runHeadRepositoryID === undefined ? repositoryID : artifact.runHeadRepositoryID },
					} }
				},
			} } }
			const summary = await restore({
				github,
				context: { repo: { owner: 'owner', repo: 'repository' }, payload: { repository: { id: repositoryID } }, runId: 99 },
				core: { warning: message => warnings.push(message), info: () => {} },
				identity: identityOfJob,
				os: 'Linux',
				directory: path.dirname(file),
				now: clock || Date.now,
			})
			const lines = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
			const fileOfArtifactsRead = path.join(path.dirname(file), 'artifacts-read.txt')
			const read = fs.existsSync(fileOfArtifactsRead) ? fs.readFileSync(fileOfArtifactsRead, 'utf8') : null
			return { lines, read, warnings, summary, requested, downloaded }
		} finally {
			fs.rmSync(scratch, { recursive: true, force: true })
		}
	}
	const list = (...keys) => ({ 'identity.txt': identity + '\n', 'passed.txt': keys.join('\n') + '\n' })

	// Merges the lists of two runs with what the run's own cache restored, sorted, each line once.
	let result = await run({ artifacts: [{ files: list(key(3), key(1)) }, { files: list(key(2), key(3)) }], existing: key(9) + '\n' + key(1) + '\n' })
	assert.strictEqual(result.lines, [key(1), key(2), key(3), key(9)].join('\n') + '\n')
	assert.deepStrictEqual(result.warnings, [])
	assert.match(result.summary, /^Passed compile checks: 2 already here, 4 with the lists of 2 other runs \(2 artifacts of this identity\), in 5 requests and /)
	assert.deepStrictEqual(result.requested, [{ owner: 'owner', repo: 'repository', name: `passed-compile-checks-v1-Linux-${identity}`, per_page: 100 }])
	assert.strictEqual(result.read, '0\n1\n')

	// Makes the file when the run restored none.
	result = await run({ artifacts: [{ files: list(key(1)) }] })
	assert.strictEqual(result.lines, key(1) + '\n')

	// Reads an archive whose files are stored uncompressed, with sizes in their own headers.
	result = await run({ artifacts: [{ archive: zip(list(key(1)), { streamed: false, compressed: false }) }] })
	assert.strictEqual(result.lines, key(1) + '\n')

	// Adds nothing from a list made under another identity.
	result = await run({ artifacts: [{ files: { 'identity.txt': 'b'.repeat(64) + '\n', 'passed.txt': key(1) + '\n' } }], existing: key(9) + '\n' })
	assert.strictEqual(result.lines, key(9) + '\n')
	assert.match(result.summary, /1 artifacts of this identity: 1 of another identity\)/)

	// Adds nothing from a fork's run, whichever of the two places says it is one.
	result = await run({ artifacts: [{ files: list(key(1)), headRepositoryID: 8 }, { files: list(key(2)), runHeadRepositoryID: 8 }, { files: list(key(3)), run: null }] })
	assert.strictEqual(result.lines, null)
	assert.match(result.summary, /3 artifacts of this identity: 2 of a fork’s run, 1 of a run that is not this repository’s CI or Verify\)/)
	assert.deepStrictEqual(result.downloaded, [])

	// Adds nothing from a run of a workflow other than CI and Verify, and asks about a run once.
	result = await run({ artifacts: [{ files: list(key(1)), path: '.github/workflows/other.yml', run: 5 }, { files: list(key(2)), path: '.github/workflows/verify.yml' }] })
	assert.strictEqual(result.lines, key(2) + '\n')

	// Adds nothing from an expired artifact.
	result = await run({ artifacts: [{ files: list(key(1)), expired: true }] })
	assert.strictEqual(result.lines, null)

	// Drops every line that is not a key, so no other text reaches the file the tests read.
	result = await run({ artifacts: [{ files: list(key(1), 'not a key', 'A'.repeat(64), key(2) + ' ', '') }] })
	assert.strictEqual(result.lines, key(1) + '\n')

	// Warns about an artifact it cannot read and still adds the others.
	result = await run({ artifacts: [{ archive: Buffer.from('not an archive, and long enough to hold a directory') }, { files: { 'passed.txt': key(1) + '\n' } }, { files: list(key(2)) }] })
	assert.strictEqual(result.lines, key(2) + '\n')
	assert.strictEqual(result.warnings.length, 1)
	assert.match(result.warnings[0], /^Could not read 2 of other runs’ lists of passed compile checks, so this run compiles what only they hold\. The first: artifact 0: the archive has no central directory$/)

	// Warns and leaves the file as it was when the artifacts cannot be listed.
	result = await run({ artifacts: [], existing: key(9) + '\n', failListing: true })
	assert.strictEqual(result.lines, key(9) + '\n')
	assert.deepStrictEqual(result.warnings, ['Could not list other runs’ passed compile checks, so this run compiles every check its own cache does not hold: Resource not accessible by integration'])

	// Warns and reads nothing when the job has no identity.
	result = await run({ artifacts: [{ files: list(key(1)) }], identityOfJob: '' })
	assert.strictEqual(result.lines, null)
	assert.strictEqual(result.requested.length, 0)
	assert.deepStrictEqual(result.warnings, ['This job’s compile check identity is not a SHA-256, so this run compiles every check its own cache does not hold.'])

	// Keeps what it read and warns when reading takes longer than the limit.
	let time = 0
	result = await run({ artifacts: [{ files: list(key(1)) }, { files: list(key(2)) }, { files: list(key(3)) }], clock: () => (time += 40_000) })
	assert.strictEqual(result.lines, [key(1), key(2)].join('\n') + '\n')
	assert.deepStrictEqual(result.warnings, ['Reading other runs’ passed compile checks took over 90 seconds, so 1 lists were left unread and this run compiles what only they hold.'])

	// Refuses a file larger than any list, before inflating it.
	const large = zip({ 'identity.txt': identity + '\n', 'passed.txt': Buffer.alloc(largestFileInBytes + 1, 0x61) })
	result = await run({ artifacts: [{ archive: large }] })
	assert.strictEqual(result.lines, null)
	assert.match(result.warnings[0], /passed\.txt is larger than any list of passed checks$/)

	// Refuses an artifact larger than any list, before downloading it.
	result = await run({ artifacts: [{ files: list(key(1)), size: largestFileInBytes + 1 }, { files: list(key(2)) }] })
	assert.strictEqual(result.lines, key(2) + '\n')
	assert.deepStrictEqual(result.downloaded, [1])
	assert.match(result.warnings[0], /artifact 0: the artifact is larger than any list of passed checks$/)

	// Reads an archive Python's `zipfile` wrote to a stream, as `actions/upload-artifact` writes one: deflated, with
	// no sizes in each file's own header and a data descriptor after it. This script's own `zip` did not write it.
	const writtenByAnotherProgram = Buffer.from(
		'UEsDBBQACAAIAMOpcF0AAAAAAAAAAAAAAAAMAAAAaWRlbnRpdHkudHh0S0ykDHABAFBLBwiNF18pBwAAAEEAAABQSwMEFAAIAAgAw6lwXQAAAAAAAAAAAAAAAAoA'
			+ 'AABwYXNzZWQudHh0MzGhDHCZUgi4AFBLBwh7oPOZCgAAAIIAAABQSwECFAMUAAgACADDqXBdjRdfKQcAAABBAAAADAAAAAAAAAAAAAAAgAEAAAAAaWRlbnRp'
			+ 'dHkudHh0UEsBAhQDFAAIAAgAw6lwXXug85kKAAAAggAAAAoAAAAAAAAAAAAAAIABQQAAAHBhc3NlZC50eHRQSwUGAAAAAAIAAgByAAAAgwAAAAAA',
		'base64',
	)
	result = await run({ artifacts: [{ archive: writtenByAnotherProgram }] })
	assert.strictEqual(result.lines, [key(4), key(5)].join('\n') + '\n')
	assert.deepStrictEqual(result.warnings, [])

	// Reads the newest fifteen however the listing is ordered, and leaves the older ones: a line starts with `b` in
	// the fifteen newest lists and with `c` in the two oldest.
	const seventeen = Array.from({ length: 17 }, (_, index) => {
		const created = (index * 7) % 17
		return { files: list((created < 15 ? 'b' : 'c') + String(index).padStart(63, '0')), created }
	})
	result = await run({ artifacts: seventeen })
	assert.strictEqual(result.lines.split('\n').filter(line => line.startsWith('b')).length, 15)
	assert.strictEqual(result.lines.split('\n').filter(line => line.startsWith('c')).length, 0)
	assert.match(result.summary, /17 artifacts of this identity: 2 older than the newest 15\), in 31 requests and /)

	// Downloads nothing an earlier run read into the list it restored, and names what the list now holds.
	result = await run({ artifacts: [{ files: list(key(1)) }, { files: list(key(2)) }, { files: list(key(3)), path: '.github/workflows/other.yml' }], existing: key(2) + '\n', existingRead: '1\n7\n' })
	assert.strictEqual(result.lines, [key(1), key(2)].join('\n') + '\n')
	assert.deepStrictEqual(result.downloaded, [0])
	assert.strictEqual(result.read, '0\n1\n2\n')
	assert.match(result.summary, /3 artifacts of this identity: 1 read by an earlier run, 1 of a run that is not this repository’s CI or Verify\), in 4 requests and /)

	// Reads again what a list that is not here was said to hold.
	result = await run({ artifacts: [{ files: list(key(1)) }], existingRead: '0\n' })
	assert.strictEqual(result.lines, key(1) + '\n')

	// Does not name an artifact it could not read as read, so the next run tries it again.
	result = await run({ artifacts: [{ archive: Buffer.from('not an archive, and long enough to hold a directory') }, { files: list(key(1)) }] })
	assert.strictEqual(result.read, '1\n')

	// Reads nothing an earlier attempt of this run uploaded.
	result = await run({ artifacts: [{ files: list(key(1)), run: 99 }, { files: list(key(2)) }] })
	assert.strictEqual(result.lines, key(2) + '\n')
	assert.match(result.summary, /2 artifacts of this identity: 1 of this run\)/)

	// Reads nothing when few requests are left this hour.
	result = await run({ artifacts: [{ files: list(key(1)) }], requestsLeft: '299' })
	assert.strictEqual(result.lines, null)
	assert.deepStrictEqual(result.downloaded, [])
	assert.deepStrictEqual(result.warnings, ['Only 299 requests are left to this repository’s workflows this hour, so other runs’ passed compile checks are left unread and this run compiles every check its own cache does not hold.'])

	// Writes the list when an artifact adds a line to one that held a line twice, and leaves alone one it adds nothing to.
	result = await run({ artifacts: [{ files: list(key(3)) }], existing: key(1) + '\n' + key(1) + '\n' })
	assert.strictEqual(result.lines, [key(1), key(3)].join('\n') + '\n')
	result = await run({ artifacts: [{ files: list(key(1)) }], existing: key(2) + '\n' + key(1) + '\n' + key(1) + '\n' })
	assert.strictEqual(result.lines, key(2) + '\n' + key(1) + '\n' + key(1) + '\n')
	assert.match(result.summary, /^Passed compile checks: 2 already here, 2 with the lists of 1 other runs /)

	console.log(`restore-from-artifacts.js: ${cases} cases passed.`)
}

if (require.main === module) {
	if (process.argv[2] === '--self-test' && process.argv[3]) {
		selfTest(process.argv[3]).catch(error => {
			console.error(error)
			process.exitCode = 1
		})
	} else {
		console.error('usage: node restore-from-artifacts.js --self-test DIRECTORY')
		process.exitCode = 2
	}
}
