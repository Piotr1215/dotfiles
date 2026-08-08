# ddgx test seam

How the bats suite reaches `extract()`'s media path and the media-to-page
fallback without touching the network. Round notes, appended, never rewritten.

## Round 1

### Settled: `--file` keeps its meaning

`__readable.mjs:792-795` states the decision in the source: "--file means a
document is already in hand, so it is that document that gets read." The
`html === null` gate on the media branch is deliberate, not accidental coupling.

Rejected: relaxing the gate so `--file` feeds the page half while `--url` drives
the media half. It reverses a written decision and would make `--file`, whose
whole point is a document in hand, sometimes hit the network.

Reverses this if: `--file` is ever redefined as "offline mode" rather than "here
is the document".

### Settled: the media branch already has a seam

`spawn('yt-dlp', ...)` at line 125 uses a bare command name, so PATH resolution
takes a stub. The suite already stubs `ddgr` (line 288) and the player chain
(line 781) this way. Channel-listing tests need no new production code: call
`node __readable.mjs --url <channel-url>` with no `--file`, stub `yt-dlp`, assert
on `YT_CHANNEL` (256), `channelListingUrl` (307), and the `media: null` branch
(483).

Cost accepted: dropping `--file` is what opens the media gate, and the same move
un-gates `extractPage`'s fetch on any test where yt-dlp's stub fails.

### Open: what "test the fallback" means

Two different things wear the name, and they need different machinery.

- (i) Routing. Given a media host and a failing yt-dlp, does control reach
  `extractPage`, and does line 828 report `mediaError` rather than `pageError`?
  This is what the vimeo.com/features bug actually was.
- (ii) Rendering. Does that URL come back as readable marketing text? Needs a
  real page, so it needs the network or a served fixture.

The suite's "no network" property is today a consequence of every test passing
`--file`, not a rule anything enforces. The file header claims it; nothing
checks it. A test that forgets `--file` reaches the internet silently.

Not yet decided. See the open question at the end of round 1.

## Round 1a: working definition of "seam"

Feathers: a place where you can alter behavior without editing in that place.
Every seam has an enabling point, the place you stand to flip it. No enabling
point, no seam. This is the test applied to each boundary below.

| boundary | enabling point | seam? |
|---|---|---|
| `--file` -> `html` param | the CLI flag | yes |
| `spawn(cmd)` line 125 | PATH (bare command name) | yes |
| `fetch(url)` line 89 | none | no |

### Corrected: escalate has a seam

Round 1 labelled the chrome/w3m rung NO SEAM. That was inferred, not read, and
it was wrong. There is exactly one `spawn` in all 931 lines, at 125 inside
`run()`, so chrome and w3m are PATH-addressable exactly like yt-dlp.

Consequence: every process boundary in the file is uniformly seamed through a
single call site, and `fetch` at 89 is the only unseamed exit in the extractor.

### Settled: no fixture-directory lever

`httpGet` lines 84-87 refuse any non-http scheme, with the reason written down:
"Previews are driven by search results; a file: or gopher: URL there must not
make us read the local disk." A `DDGX_FIXTURE_DIR` that resolves urls to local
files reintroduces exactly what that guard forbids.

Rejected: fixture-directory redirection inside `httpGet`.
Still open: a tripwire that makes `httpGet` refuse rather than redirect, which
runs with the grain of 87 instead of against it.

Reverses this if: the preview path stops being driven by untrusted search
results, which is the premise line 87 rests on.

## Round 1b: the diagram was doing two jobs

`shape.puml` had grown into a full control-flow trace of `extract()` with the
seam verdicts buried in side-notes. The flowchart was ten times the size of the
message and mostly restated the source.

Split:

- `shape.puml` now answers only the question being decided: of the four things
  the extractor depends on, which can a test control. Four boxes, three green,
  one red. 631x460.
- `flow.puml` keeps the control-flow trace, which is still worth having for
  finding the branch points. Not the decision surface.

Rule this came from: a diagram that only restates the prose is noise. The
control flow restates the code. The seam verdicts do not appear in the code at
all, which is exactly why they deserve the picture.
