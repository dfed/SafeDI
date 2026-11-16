// Adds to this run's file of passed compile checks the checks that other runs of this repository passed under the
// same identity, read from the `passed-compile-checks-<os>` artifacts those runs uploaded
// (`.github/actions/upload-passed-compile-checks`). An artifact is readable from every branch and pull request,
// where a cache is readable only from its own branch and main, and a `workflow_run` workflow that follows a pull
// request's run may not save a cache at all, so a pull request's passes reached no other run through one.
//
// A line is added only when all of these hold, and anything else leaves the run to compile the check:
// - the artifact's run is of this repository, not a fork, and ran this repository's `ci.yml` or `verify.yml`;
// - the artifact's `identity.txt` is this job's identity (`.github/scripts/compile-check-identity.sh`);
// - the line is a SHA-256, as `PassedCompileCheckCache.key` writes one.
// A run uploads only the checks its own test processes passed, so no line here was ever restored by its uploader.
// Nothing here fails a job: whatever goes wrong is a warning, and the checks compile.
//
// `node restore-from-artifacts.js --self-test DIRECTORY` checks all of this against fixtures; "Check Line Coverage on Linux"
// runs it.

'use strict'

const fs = require('fs')
const path = require('path')
const zlib = require('zlib')

// The newest artifacts of this name that are looked at. A stack's top run needs the runs below it and main's, and
// Verify runs of other branches upload under the same name, so this is several stacks' worth.
const artifactsToExamine = 30
// After this long, what was read is kept and the rest is left to compile. A run with 30 artifacts took a few seconds.
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

/// Reads the artifacts and merges their lines into `<directory>/passed.txt`. Returns what it printed, for the
/// self-test. `github` is an Octokit client, `context` the workflow's context, and `core` what warns.
async function restore({ github, context, core, identity, os, directory, now = Date.now }) {
	const started = now()
	const file = path.join(directory, 'passed.txt')
	const reason = 'so this run compiles every check its own cache does not hold'
	if (!keyPattern.test(identity || '')) {
		core.warning(`This job’s compile check identity is not a SHA-256, ${reason}.`)
		return null
	}
	const owner = context.repo.owner
	const repo = context.repo.repo
	const repositoryID = context.payload.repository && context.payload.repository.id
	let artifacts
	try {
		if (!repositoryID) {
			throw new Error('the event names no repository')
		}
		const response = await github.rest.actions.listArtifactsForRepo({ owner, repo, name: `passed-compile-checks-${os}`, per_page: artifactsToExamine })
		artifacts = response.data.artifacts
	} catch (error) {
		core.warning(`Could not list other runs’ passed compile checks, ${reason}: ${error.message}`)
		return null
	}

	const own = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(line => line !== '') : []
	const together = new Set(own)
	const counts = { read: 0, expired: 0, ofAFork: 0, ofAnotherIdentity: 0, ofAnotherWorkflow: 0, unreadable: 0, leftUnread: 0 }
	let firstFailure = null
	const whetherRunCounts = new Map()
	for (const artifact of artifacts) {
		if (now() - started > timeLimitInMilliseconds) {
			counts.leftUnread += 1
			continue
		}
		if (artifact.expired) {
			counts.expired += 1
			continue
		}
		const run = artifact.workflow_run
		if (!run || run.head_repository_id !== repositoryID || run.repository_id !== repositoryID) {
			counts.ofAFork += 1
			continue
		}
		try {
			const download = await github.rest.actions.downloadArtifact({ owner, repo, artifact_id: artifact.id, archive_format: 'zip' })
			const files = filesInZip(Buffer.from(download.data))
			const artifactIdentity = files.get('identity.txt')
			const passed = files.get('passed.txt')
			if (!artifactIdentity || !passed) {
				throw new Error('the artifact holds no identity or no passed checks')
			}
			if (artifactIdentity.toString('utf8').split('\n')[0] !== identity) {
				counts.ofAnotherIdentity += 1
				continue
			}
			if (!whetherRunCounts.has(run.id)) {
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
				continue
			}
			for (const line of passed.toString('utf8').split('\n')) {
				if (keyPattern.test(line)) {
					together.add(line)
				}
			}
			counts.read += 1
		} catch (error) {
			counts.unreadable += 1
			firstFailure = firstFailure || `artifact ${artifact.id}: ${error.message}`
		}
	}

	if (together.size > own.length) {
		fs.mkdirSync(directory, { recursive: true })
		const merged = path.join(directory, 'merged.txt')
		fs.writeFileSync(merged, [...together].sort().join('\n') + '\n')
		fs.renameSync(merged, file)
	}
	if (counts.unreadable > 0) {
		core.warning(`Could not read ${counts.unreadable} of other runs’ lists of passed compile checks, so this run compiles what only they hold. The first: ${firstFailure}`)
	}
	if (counts.leftUnread > 0) {
		core.warning(`Reading other runs’ passed compile checks took over ${timeLimitInMilliseconds / 1000} seconds, so ${counts.leftUnread} lists were left unread and this run compiles what only they hold.`)
	}
	const skipped = [
		[counts.ofAnotherIdentity, 'of another identity'],
		[counts.ofAFork, 'of a fork’s run'],
		[counts.ofAnotherWorkflow, 'of a run that is not this repository’s CI or Verify'],
		[counts.expired, 'expired'],
		[counts.unreadable, 'unreadable'],
		[counts.leftUnread, 'left unread'],
	].filter(([count]) => count > 0).map(([count, what]) => `${count} ${what}`)
	const summary = `Passed compile checks: ${own.length} already here, ${together.size} with the lists of ${counts.read} other runs`
		+ ` (${artifacts.length} artifacts examined${skipped.length > 0 ? ': ' + skipped.join(', ') : ''}),`
		+ ` in ${((now() - started) / 1000).toFixed(1)} seconds.`
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

	/// Runs `restore` against `artifacts` (each `{ files | archive, run, expired, path, headRepositoryID }`) with
	/// `existing` in the file, and returns the file's lines, the warnings and the summary.
	async function run({ artifacts, existing = null, identityOfJob = identity, failListing = false, clock = null }) {
		cases += 1
		const directory = path.join(scratch, `case-${cases}`)
		fs.mkdirSync(directory, { recursive: true })
		try {
			const file = path.join(directory, 'checks', 'passed.txt')
			if (existing !== null) {
				fs.mkdirSync(path.dirname(file))
				fs.writeFileSync(file, existing)
			}
			const warnings = []
			const requested = []
			const github = { rest: { actions: {
				listArtifactsForRepo: async parameters => {
					requested.push(parameters)
					if (failListing) {
						throw new Error('Resource not accessible by integration')
					}
					return { data: { artifacts: artifacts.map((artifact, index) => ({
						id: index,
						expired: artifact.expired === true,
						workflow_run: artifact.run === null ? null : {
							id: artifact.run === undefined ? 100 + index : artifact.run,
							head_repository_id: artifact.headRepositoryID === undefined ? repositoryID : artifact.headRepositoryID,
							repository_id: repositoryID,
						},
					})) } }
				},
				downloadArtifact: async ({ artifact_id }) => {
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
				context: { repo: { owner: 'owner', repo: 'repository' }, payload: { repository: { id: repositoryID } } },
				core: { warning: message => warnings.push(message), info: () => {} },
				identity: identityOfJob,
				os: 'Linux',
				directory: path.dirname(file),
				now: clock || Date.now,
			})
			const lines = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
			return { lines, warnings, summary, requested }
		} finally {
			fs.rmSync(scratch, { recursive: true, force: true })
		}
	}
	const list = (...keys) => ({ 'identity.txt': identity + '\n', 'passed.txt': keys.join('\n') + '\n' })

	// Merges the lists of two runs with what the run's own cache restored, sorted, each line once.
	let result = await run({ artifacts: [{ files: list(key(3), key(1)) }, { files: list(key(2), key(3)) }], existing: key(9) + '\n' + key(1) + '\n' })
	assert.strictEqual(result.lines, [key(1), key(2), key(3), key(9)].join('\n') + '\n')
	assert.deepStrictEqual(result.warnings, [])
	assert.match(result.summary, /^Passed compile checks: 2 already here, 4 with the lists of 2 other runs \(2 artifacts examined\), in /)
	assert.deepStrictEqual(result.requested, [{ owner: 'owner', repo: 'repository', name: 'passed-compile-checks-Linux', per_page: 30 }])

	// Makes the file when the run restored none.
	result = await run({ artifacts: [{ files: list(key(1)) }] })
	assert.strictEqual(result.lines, key(1) + '\n')

	// Reads an archive whose files are stored uncompressed, with sizes in their own headers.
	result = await run({ artifacts: [{ archive: zip(list(key(1)), { streamed: false, compressed: false }) }] })
	assert.strictEqual(result.lines, key(1) + '\n')

	// Adds nothing from a list made under another identity.
	result = await run({ artifacts: [{ files: { 'identity.txt': 'b'.repeat(64) + '\n', 'passed.txt': key(1) + '\n' } }], existing: key(9) + '\n' })
	assert.strictEqual(result.lines, key(9) + '\n')
	assert.match(result.summary, /1 artifacts examined: 1 of another identity\)/)

	// Adds nothing from a fork's run, whichever of the two places says it is one.
	result = await run({ artifacts: [{ files: list(key(1)), headRepositoryID: 8 }, { files: list(key(2)), runHeadRepositoryID: 8 }, { files: list(key(3)), run: null }] })
	assert.strictEqual(result.lines, null)
	assert.match(result.summary, /3 artifacts examined: 2 of a fork’s run, 1 of a run that is not this repository’s CI or Verify\)/)

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
