#!/usr/bin/env node
// Extract the readable content of a web page as markdown.
//
// Uses Mozilla's Readability (the Firefox Reader View algorithm) to choose the
// article, and Turndown to render it. That is the same pair the MarkDownload
// extension composes, so terminal output matches what the browser gives you.
// Readability decides what to keep; Turndown only formats what it chose.
//
//   __readable.mjs --url https://example.com/post
//   __readable.mjs --file page.html --url https://example.com/post
//   __readable.mjs --deep --url https://linear.app/docs
//   __readable.mjs --url https://youtu.be/ID --cache ~/.cache/ddgx
//   __readable.mjs --batch results.json --cache ~/.cache/ddgx
//   __readable.mjs --deep --batch results.json --cache ~/.cache/ddgx
//
// A video has no article to find, so a link to one reads as its own text
// instead: yt-dlp supplies the description and captions for YouTube, Vimeo,
// Twitch, Dailymotion, Odysee and Rumble. A YouTube playlist reads as its
// track listing.
//
// --deep escalates a page Readability cannot read, and only when asked for,
// because it spends seconds and a browser: headless Chrome renders the page,
// then w3m lays that render out as text if the page turns out not to be an
// article at all. Every escalated extract says which step produced it.
//
// Exits 1 when a page cannot be fetched or holds no article, so callers can
// avoid caching a failure.

import { createRequire } from 'node:module'
import { createHash } from 'node:crypto'
import { spawn } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import path from 'node:path'

// Dependencies live outside the dotfiles repo so 36MB of node_modules is never
// committed. __ddgx.sh --setup installs them.
const MODULES_DIR = process.env.DDGX_MODULES || path.join(homedir(), '.local', 'share', 'ddgx')
let Readability, TurndownService, gfm, JSDOM
try {
  const require = createRequire(path.join(MODULES_DIR, 'package.json'))
  ;({ Readability } = require('@mozilla/readability'))
  TurndownService = require('turndown')
  ;({ gfm } = require('turndown-plugin-gfm'))
  ;({ JSDOM } = require('jsdom'))
} catch {
  process.stderr.write(`[missing extraction engine: run __ddgx.sh --setup]\n`)
  process.exit(2)
}

const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
const TIMEOUT_MS = 10000
const SE_ANSWERS = 3
const MIN_CHARS = 40

// One yt-dlp call carries metadata, description and the caption index, and it
// is a network round trip to a site that sometimes stalls, so it gets twice
// the page timeout and no more.
const MEDIA_TIMEOUT_MS = 20000
// How many entries a playlist or channel listing shows. A channel with years
// of uploads would otherwise page through thousands of them to build a preview
// nobody scrolls to the bottom of.
const LISTING_MAX = 40
// Captions arrive four words to a line. Run them back together and break near
// this, where a paragraph stops being a wall of text.
const PARAGRAPH_CHARS = 450

// --deep only. A page that keeps less than this did not read, whatever the
// extractor claims: 154 characters of a nav bar is a failure wearing a
// success's clothes. Overridable because the right floor is per corpus.
const DEEP_MIN = parseInt(process.env.DDGX_DEEP_MIN || '', 10) || 400
const RENDER_BUDGET_MS = 8000
const RENDER_TIMEOUT_MS = 25000
const W3M_TIMEOUT_MS = 10000
// Wide enough that w3m's wrapping is not the thing you notice first. It has to
// wrap something: it is a text dumper, not a markdown converter.
const W3M_COLS = 100

// ---------------------------------------------------------------------------
// Fetching
// ---------------------------------------------------------------------------

async function httpGet (url, { json = false, raw = false } = {}) {
  const scheme = new URL(url).protocol
  // Previews are driven by search results; a file: or gopher: URL there must
  // not make us read the local disk.
  if (scheme !== 'http:' && scheme !== 'https:') throw new Error(`unsupported scheme: ${scheme}`)

  // The only lever a test has on the network. Every subprocess here is reached
  // by bare name through run(), so a stub on PATH replaces it; fetch has no
  // equivalent, and this is the one call site that makes one.
  //
  // The suite's "no test fetches over the network" was never enforced, it was
  // a side effect of every test passing --file, which skips both fetch paths.
  // That stops holding the moment a test drives the media branch, because
  // dropping --file is exactly what opens it. Without this an unstubbed test
  // reaches the real internet and fails later as an unattributable flake.
  //
  // It refuses rather than redirecting to a fixture directory on purpose: the
  // scheme guard above exists to keep search-driven previews off the local
  // disk, and a fixture lever would hand that back.
  if (process.env.DDGX_NO_NETWORK) throw new Error(`network disabled: ${url}`)

  const res = await fetch(url, {
    headers: {
      'User-Agent': UA,
      Accept: json ? 'application/json' : 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9'
    },
    redirect: 'follow',
    signal: AbortSignal.timeout(TIMEOUT_MS)
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  if (json) return res.json()

  const ctype = res.headers.get('content-type') || ''
  // The gate exists to keep a pdf or a zip away from the html parser. A
  // caption track is text/vtt and would fail it, so that one caller opts out
  // rather than the gate widening for every page fetch: yt-dlp already told us
  // the url is a subtitle file.
  if (!raw && ctype && !/html|xml|text\/plain/i.test(ctype)) {
    throw new Error(`not a web page: ${ctype.split(';')[0].trim()}`)
  }
  return res.text()
}

// ---------------------------------------------------------------------------
// Subprocesses
//
// Every external tool here sits on a preview path, so none of them may hang
// the pane: each call carries its own cap, and a binary that is not installed
// comes back as an ordinary result the caller can step over rather than as a
// crash. stderr is never the verdict. yt-dlp warns about a missing JS runtime
// and succeeds anyway, Chrome complains about the GPU while dumping a perfect
// DOM; only the exit code and the output say what happened.
// ---------------------------------------------------------------------------

function run (cmd, args, { input = null, timeoutMs = 10000 } = {}) {
  return new Promise(resolve => {
    const child = spawn(cmd, args)
    const out = []
    const err = []
    let timer = null
    let settled = false
    const finish = result => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve(result)
    }

    timer = setTimeout(() => {
      child.kill('SIGKILL')
      finish({ code: null, stdout: '', stderr: `timed out after ${Math.round(timeoutMs / 1000)}s`, missing: false })
    }, timeoutMs)

    child.on('error', e => finish({ code: null, stdout: '', stderr: e.message, missing: e.code === 'ENOENT' }))
    child.stdout.on('data', d => out.push(d))
    child.stderr.on('data', d => err.push(d))
    child.on('close', code => finish({
      code,
      stdout: Buffer.concat(out).toString('utf8'),
      stderr: Buffer.concat(err).toString('utf8'),
      missing: false
    }))

    // w3m closes its input the moment it has read enough, and an unhandled
    // EPIPE on that write takes the whole process down.
    child.stdin.on('error', () => {})
    child.stdin.end(input === null ? '' : input)
  })
}

// A failed tool describes its own failure better than we can guess it. Its
// warnings are not that description.
function toolError (result, fallback) {
  const last = result.stderr.split('\n')
    .map(line => line.trim())
    .filter(line => line && !/^WARNING:/i.test(line))
    .pop()
  return last ? last.replace(/^ERROR:\s*/i, '').slice(0, 200) : fallback
}

// ---------------------------------------------------------------------------
// Stack Exchange adapter
//
// Every Stack Exchange site rejects clients without a real browser's TLS
// fingerprint, so no header set gets the HTML. Their API needs no key (300
// requests/day/IP, and we cache) and returns better material than the page:
// the question plus the top-voted answers.
// ---------------------------------------------------------------------------

const SE_HOSTS = {
  'stackoverflow.com': 'stackoverflow',
  'serverfault.com': 'serverfault',
  'superuser.com': 'superuser',
  'askubuntu.com': 'askubuntu',
  'mathoverflow.net': 'mathoverflow'
}

function seSite (host) {
  host = host.toLowerCase().replace(/^www\./, '')
  if (SE_HOSTS[host]) return SE_HOSTS[host]
  if (host.endsWith('.stackexchange.com')) return host.split('.')[0]
  return null
}

async function seApi (pathPart, site) {
  const url = `https://api.stackexchange.com/2.3/${pathPart}?site=${site}` +
    '&filter=withbody&sort=votes&order=desc'
  return httpGet(url, { json: true })
}

async function stackExchangeHtml (url) {
  const parsed = new URL(url)
  const site = seSite(parsed.hostname)
  if (!site) return null

  let qid
  const direct = parsed.pathname.match(/\/(?:questions|q)\/(\d+)/)
  if (direct) {
    qid = direct[1]
  } else {
    const answer = parsed.pathname.match(/\/a\/(\d+)/)
    if (!answer) return null
    const data = await seApi(`answers/${answer[1]}`, site)
    if (!data.items?.length) return null
    qid = String(data.items[0].question_id)
  }

  const question = (await seApi(`questions/${qid}`, site)).items?.[0]
  if (!question) return null
  const answers = (await seApi(`questions/${qid}/answers`, site)).items || []

  const parts = ['<article>', `<h1>${question.title}</h1>`, question.body]
  for (const a of answers.slice(0, SE_ANSWERS)) {
    parts.push(`<h2>${a.is_accepted ? 'Accepted answer' : 'Answer'} (score ${a.score})</h2>`)
    parts.push(a.body)
  }
  if (!answers.length) parts.push('<p>(no answers)</p>')
  parts.push('</article>')
  return parts.join('\n')
}

// ---------------------------------------------------------------------------
// Media adapter
//
// A video holds no article, so Readability answers "no article found" and a
// YouTube hit in the picker is a result you cannot read at all. The video's
// own text is the extract: what the channel wrote about it, and what is said
// in it.
//
// yt-dlp already speaks every one of these sites, so one call stands in for a
// scraper per host and keeps working when a player is rewritten. This sits on
// the cheap path beside Stack Exchange, not behind --deep, because it costs
// about two seconds and it is the only path on which a video renders at all.
// ---------------------------------------------------------------------------

// Matched on hostname and path, never as a substring of the url: a blog post
// about youtube.com is still a blog post, and a /watch page is the only part
// of youtube.com that is a video.
//
// Each matcher is handed the parsed url as well as the path, because YouTube's
// playlist page is the one address whose meaning lives in the query: bare
// /playlist is an empty page, /playlist?list=ID is 21 videos.
// A channel is a list of videos, so it reads like a playlist rather than like
// a page. Left to Readability a channel url renders Google's cookie consent
// text, which is the least useful thing on the page and says nothing about the
// channel. The four url shapes are the four YouTube has used over the years:
// /channel/UC..., the modern /@handle, and the older /c/ and /user/ forms.
const YT_CHANNEL = /^\/(?:channel\/|c\/|user\/|@)[^/]+/

const MEDIA_HOSTS = {
  'youtube.com': (p, u) => /^\/(?:watch$|shorts\/)/.test(p) ||
    (p === '/playlist' && u.searchParams.has('list')) ||
    YT_CHANNEL.test(p),
  'youtu.be': p => p.length > 1,
  'vimeo.com': p => p.length > 1,
  'twitch.tv': p => /^\/(?:videos|clips)\//.test(p),
  'dailymotion.com': p => p.length > 1,
  'odysee.com': p => p.length > 1,
  'rumble.com': p => p.length > 1
}

function mediaSite (host) {
  // m. is the mobile front of the same site and player. is one embed of it.
  // Everything else keeps its host, so a lookalike domain cannot match.
  host = host.toLowerCase().replace(/^(?:www|m)\./, '')
  if (MEDIA_HOSTS[host]) return MEDIA_HOSTS[host]
  const parent = Object.keys(MEDIA_HOSTS).find(h => host.endsWith(`.${h}`))
  return parent ? MEDIA_HOSTS[parent] : null
}

function isMediaUrl (url) {
  try {
    const parsed = new URL(url)
    const isVideoPath = mediaSite(parsed.hostname)
    return Boolean(isVideoPath && isVideoPath(parsed.pathname, parsed))
  } catch {
    // A url the parser rejects is not this adapter's to report. The normal
    // path throws on it with the message the caller already handles.
    return false
  }
}

// Only YouTube serves a page that is a list of videos rather than one video.
// A /watch url carrying &list= is still a single video and keeps the video
// path: what it opens on is the video, with the list beside it.
function playlistId (parsed) {
  if (mediaSite(parsed.hostname) !== MEDIA_HOSTS['youtube.com']) return null
  if (parsed.pathname !== '/playlist') return null
  return parsed.searchParams.get('list')
}

// The url to hand yt-dlp for a channel, or null when this is not one.
//
// A bare channel url does not list videos. yt-dlp reads it as the channel's
// tab index and returns entries named "NiCE - Videos", "NiCE - Shorts", which
// is a menu rather than the thing you asked for. Naming the /videos tab is
// what produces uploads, so a url that stops at the channel gets it appended
// and a url that already names a tab is left exactly as it is.
function channelListingUrl (parsed) {
  if (mediaSite(parsed.hostname) !== MEDIA_HOSTS['youtube.com']) return null
  const match = parsed.pathname.match(YT_CHANNEL)
  if (!match) return null
  const root = match[0]
  const rest = parsed.pathname.slice(root.length).replace(/\/$/, '')
  return `https://www.youtube.com${root}${rest || '/videos'}`
}

// The five escapes WebVTT defines for cue text, plus the non-breaking space
// YouTube pads its alignment with.
const VTT_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', lrm: '', rlm: '' }

function decodeEntities (text) {
  return text.replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, (whole, name) => {
    if (name[0] !== '#') {
      const named = VTT_ENTITIES[name.toLowerCase()]
      return named === undefined ? whole : named
    }
    const code = /^#x/i.test(name) ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10)
    return code >= 0 && code <= 0x10ffff ? String.fromCodePoint(code) : whole
  })
}

// Prefer a transcript a person wrote over one a machine guessed, and vtt over
// the timing formats the same endpoint also serves.
function captionTrack (info) {
  const sources = [
    { map: info.subtitles, generated: false },
    { map: info.automatic_captions, generated: true }
  ]
  for (const { map, generated } of sources) {
    if (!map) continue
    const langs = Object.keys(map)
    const lang = langs.find(l => l === 'en') || langs.find(l => l.startsWith('en'))
    if (!lang) continue
    const track = (map[lang] || []).find(t => t.ext === 'vtt' && t.url)
    if (track) return { url: track.url, generated }
  }
  return null
}

// VTT is a cue list for a player, and reading one as prose means undoing what
// it does for the player's benefit.
//
// Auto-captions are why this is not a one-line strip. YouTube ships them as a
// rolling two-line window, so every cue reprints the line before it and a
// naive concatenation says everything twice. Dropping a line that only repeats
// the last one kept rolls the window back out into a script.
function vttToProse (vtt) {
  const spoken = []
  // A blank line ends a cue, so blocks are the format's own unit. A block with
  // no timestamp is the WEBVTT header, a NOTE or a STYLE, none of them speech.
  for (const block of vtt.replace(/\r\n?/g, '\n').split(/\n{2,}/)) {
    const rows = block.split('\n')
    const timing = rows.findIndex(row => row.includes('-->'))
    if (timing < 0) continue
    for (const row of rows.slice(timing + 1)) {
      // Karaoke timings and <c> spans inside the cue: markup for a player to
      // highlight words as they are said, and noise to a reader.
      const text = decodeEntities(row.replace(/<[^>]*>/g, '')).replace(/\s+/g, ' ').trim()
      if (!text || text === spoken[spoken.length - 1]) continue
      spoken.push(text)
    }
  }

  const paragraphs = []
  let buffer = ''
  for (const line of spoken) {
    buffer = buffer ? `${buffer} ${line}` : line
    // Break where the speaker finished a thought, once there is enough of one
    // to be a paragraph. Captions carrying no punctuation at all would never
    // reach that, so length alone eventually breaks them too.
    const ended = /[.!?]["')\]]?$/.test(line)
    if ((ended && buffer.length >= PARAGRAPH_CHARS) || buffer.length >= PARAGRAPH_CHARS * 2) {
      paragraphs.push(buffer)
      buffer = ''
    }
  }
  if (buffer) paragraphs.push(buffer)
  return paragraphs.join('\n\n')
}

async function ytDlpInfo (url, extraArgs) {
  const probe = await run('yt-dlp',
    ['--dump-single-json', '--skip-download', '--no-warnings', ...extraArgs, url],
    { timeoutMs: MEDIA_TIMEOUT_MS })
  if (probe.missing) throw new Error('yt-dlp not installed')

  try {
    if (probe.code !== 0) throw new Error('exit')
    return JSON.parse(probe.stdout)
  } catch {
    throw new Error(toolError(probe, 'yt-dlp returned nothing readable'))
  }
}

// The flat playlist path reports a length in seconds and leaves
// duration_string null, so the clock face is ours to build.
function clock (seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) return ''
  const total = Math.round(seconds)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const secs = String(total % 60).padStart(2, '0')
  return hours ? `${hours}:${String(minutes).padStart(2, '0')}:${secs}` : `${minutes}:${secs}`
}

// The picker paints this into a preview pane, so the biggest one is the one
// worth having. yt-dlp tends to list them smallest first but never promises
// to, and info.thumbnail is the older single-value field some extractors
// still fill instead.
function bestThumbnail (info) {
  let best = null
  for (const shot of Array.isArray(info?.thumbnails) ? info.thumbnails : []) {
    if (!shot?.url) continue
    if (!best || (shot.width || 0) > (best.width || 0)) best = shot
  }
  return best?.url || info?.thumbnail || ''
}

// A playlist has no prose of its own: what a reader wants from one is what is
// in it and how long each piece runs.
function playlistMarkdown (info, entries) {
  const facts = []
  if (info.channel || info.uploader) facts.push(info.channel || info.uploader)
  const count = Number.isFinite(info.playlist_count) ? info.playlist_count : entries.length
  if (count) facts.push(`${count} video${count === 1 ? '' : 's'}`)

  const parts = []
  if (facts.length) parts.push(facts.join(' | '))
  const description = String(info.description || '').trim()
  if (description) parts.push(description)

  const listing = entries.map((entry, i) => {
    const length = clock(entry.duration)
    return `${i + 1}. ${String(entry.title || 'untitled').trim()}${length ? ` (${length})` : ''}`
  })
  if (listing.length) parts.push(listing.join('\n'))

  // Say what the cap dropped, because a list that stops at 40 with nothing
  // said looks exactly like a list of 40. The header above already prints the
  // real total for a playlist, so without this line the two quietly disagree
  // and the reader has to notice the arithmetic.
  //
  // The two cases are not symmetric, measured rather than assumed: with
  // --playlist-end 40 a playlist over the cap still reports playlist_count as
  // its true length (917 for one uploads list), while a channel reports null
  // and offers no total at all. So a playlist can name what it dropped and a
  // channel can only name what it is showing.
  //
  // A known total that equals what we have dropped nothing, so it stays quiet:
  // over-warning on a complete list teaches the reader to ignore the line.
  if (Number.isFinite(info.playlist_count) && info.playlist_count > entries.length) {
    parts.push(`[showing ${entries.length} of ${info.playlist_count}]`)
  } else if (!Number.isFinite(info.playlist_count) && entries.length >= LISTING_MAX) {
    parts.push(`[showing the first ${entries.length}, no total reported]`)
  }

  if (!parts.length) throw new Error('no playlist text found')
  return parts.join('\n\n')
}

async function mediaMarkdown (url) {
  // A playlist takes a different argument set and a different renderer, so the
  // two paths split before the call rather than after it. --flat-playlist is
  // what keeps it one request: without it yt-dlp resolves every video in the
  // list, which was 21 network round trips for one preview.
  const listing = playlistId(new URL(url))
    ? url
    : channelListingUrl(new URL(url))
  if (listing) {
    // Capped, because a channel with a decade of uploads would otherwise page
    // through thousands of entries for a preview nobody scrolls to the end of.
    // A playlist gets the same cap for the same reason.
    const info = await ytDlpInfo(listing, ['--flat-playlist', '--playlist-end', String(LISTING_MAX)])
    const entries = (info.entries || []).filter(Boolean)
    return {
      markdown: playlistMarkdown(info, entries),
      // A playlist owns no image on the flat path, so the first video's still
      // stands in for it, and no single duration describes a list.
      //
      // A channel deliberately gets no media record at all. The picker treats
      // the presence of one as "this is playable", and playing a channel means
      // queueing every upload it has, which nobody asks for by pressing play on
      // a search result. Without the record the channel reads as an ordinary
      // page whose text happens to be its video list, which is what it is.
      media: playlistId(new URL(url))
        ? {
            kind: 'playlist',
            title: String(info.title || ''),
            thumbnail: bestThumbnail(entries[0]),
            webpage_url: String(info.webpage_url || url),
            duration: 0
          }
        : null
    }
  }

  const info = await ytDlpInfo(url, [])

  const facts = []
  if (info.channel || info.uploader) facts.push(info.channel || info.uploader)
  if (info.duration_string) facts.push(info.duration_string)
  if (Number.isFinite(info.view_count)) facts.push(`${info.view_count.toLocaleString('en-US')} views`)
  const day = String(info.upload_date || '')
  if (/^\d{8}$/.test(day)) facts.push(`${day.slice(0, 4)}-${day.slice(4, 6)}-${day.slice(6)}`)

  const parts = []
  if (facts.length) parts.push(facts.join(' | '))
  const description = String(info.description || '').trim()
  if (description) parts.push(description)

  const track = captionTrack(info)
  if (track) {
    // The caption url is signed and short lived, and it came out of the call
    // already made. Asking yt-dlp for the subtitles separately is a second hit
    // on the same video, which YouTube answers with HTTP 429.
    const prose = await httpGet(track.url, { raw: true }).then(vttToProse).catch(() => '')
    // Say which kind it is. A machine transcript mishears, and on the test
    // video "A full commitment's" arrives as "I feel commitments": quotable
    // looking text that the speaker never said. Under a bare heading the two
    // are indistinguishable, so the heading carries the warning.
    if (prose) parts.push(track.generated ? '## Transcript (auto-generated)' : '## Transcript', prose)
  }

  if (!parts.length) throw new Error('no video text found')
  return {
    markdown: parts.join('\n\n'),
    media: {
      kind: 'video',
      title: String(info.title || ''),
      thumbnail: bestThumbnail(info),
      webpage_url: String(info.webpage_url || url),
      duration: Number.isFinite(info.duration) ? info.duration : 0
    }
  }
}

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

// MarkDownload's own defaults, from deathau/markdownload
// src/shared/default-options.js. Overridden by the extension's settings export
// when one is installed, so the terminal follows whatever the browser button
// is set to.
const DEFAULT_OPTIONS = {
  headingStyle: 'atx',
  hr: '___',
  bulletListMarker: '-',
  codeBlockStyle: 'fenced',
  fence: '```',
  emDelimiter: '_',
  strongDelimiter: '**',
  linkStyle: 'inlined',
  linkReferenceStyle: 'full'
}

// The extension's Options page has an Export button. That export is checked
// into the dotfiles and stowed here, so the browser button and the terminal
// agree by construction instead of by me copying values between them.
const OPTIONS_FILE = process.env.DDGX_OPTIONS || path.join(
  process.env.XDG_CONFIG_HOME || path.join(homedir(), '.config'),
  'ddgx', 'markdownload-options.json'
)

function loadOptions () {
  try {
    const saved = JSON.parse(readFileSync(OPTIONS_FILE, 'utf8'))
    // Only the keys turndown understands. The rest of the export drives
    // downloads, frontmatter and Obsidian, none of which exist here.
    const opts = { ...DEFAULT_OPTIONS }
    for (const key of Object.keys(DEFAULT_OPTIONS)) {
      if (typeof saved[key] === 'string') opts[key] = saved[key]
    }
    if (typeof saved.turndownEscape === 'boolean') opts.turndownEscape = saved.turndownEscape
    return opts
  } catch {
    return { ...DEFAULT_OPTIONS }
  }
}

// Turndown configured the way MarkDownload configures it, so the markdown here
// is the markdown the extension produces.
//
// Nothing is post-processed afterwards. Wrapping, image rewriting and
// whitespace tidying all belong to the delivery end: fzf's preview window
// already soft-wraps, and a pipe should receive markdown unaltered.
function makeTurndown (baseURI) {
  const options = loadOptions()
  const td = new TurndownService(options)

  // MarkDownload's 'links' rule (background.js): rewrite every href through
  // validateUri, then decline to match so turndown's own link rule renders it.
  // Readability absolutises path links but leaves same-page anchors alone, so
  // without this a heading link reaches the terminal as a bare "#what-is-a-pod"
  // with no page attached. Resolved with the URL parser rather than their
  // string concatenation, which doubles the slash.
  td.addRule('links', {
    filter: node => {
      if (node.nodeName === 'A' && node.getAttribute('href')) {
        try {
          node.setAttribute('href', new URL(node.getAttribute('href'), baseURI).href)
        } catch { /* an href neither absolute nor resolvable: leave it be */ }
        // Bootstrap and every other tooltip library moves title into a data-
        // attribute on init, so the live DOM the extension reads has none. We
        // read the served HTML, where a glossary definition still sits in
        // there and would paste itself into every other link.
        if (node.hasAttribute('data-bs-toggle') || node.hasAttribute('data-toggle')) {
          node.removeAttribute('title')
        }
      }
      return options.linkStyle === 'stripLinks'
    },
    replacement: content => content
  })

  // The one place this deliberately differs from the extension. Turndown
  // writes "-   item" with the three spaces as a literal in its listItem rule,
  // and indents continuation lines to match, which leaves a line of nothing
  // but spaces between every pair of items. That reads as noise in an editor.
  // Same rule as turndown's, with a two-space prefix and blank lines left
  // blank. There is no option for this: bulletListMarker only picks the
  // character.
  td.addRule('listItem', {
    filter: 'li',
    replacement: (content, node) => {
      const parent = node.parentNode
      let prefix = options.bulletListMarker + ' '
      if (parent.nodeName === 'OL') {
        const start = parent.getAttribute('start')
        const index = Array.prototype.indexOf.call(parent.children, node)
        prefix = `${start ? Number(start) + index : index + 1}. `
      }
      const indent = ' '.repeat(prefix.length)
      const trailingNewline = /\n$/.test(content)
      content = content.replace(/^\n+/, '').replace(/\n+$/, '') + (trailingNewline ? '\n' : '')
      content = content.split('\n')
        .map((line, i) => (i === 0 || line === '' ? line : indent + line))
        .join('\n')
      return prefix + content + (node.nextSibling ? '\n' : '')
    }
  })

  // Tables, strikethrough and task lists. Without the GFM plugin a reference
  // page's tables collapse into a run-on line, which is most of what makes
  // API documentation readable.
  td.use(gfm)
  td.keep(['iframe', 'sub', 'sup', 'u', 'ins', 'del', 'small', 'big'])
  return td
}

// "cloudrumble.net" is what you type; "https://cloudrumble.net" is what you
// have to type. Anything already naming a scheme is left alone, so the
// http(s)-only check in httpGet still sees a file: URL for what it is.
function normalizeUrl (input) {
  if (!input) return input
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(input) ? input : `https://${input}`
}

const charCount = text => text.replace(/\s+/g, ' ').trim().length

// One pass of the reader over one document. This is the whole of the default
// path, and the rung --deep escalates from, so it reports a thin result rather
// than throwing on it: only the caller knows whether a better attempt is left.
function readDocument (source, url) {
  const dom = new JSDOM(source, url ? { url } : {})
  const totalChars = charCount(dom.window.document.body?.textContent || '')

  const article = new Readability(dom.window.document).parse()
  if (!article || !article.content) {
    return { totalChars, markdown: '', keptChars: 0, reason: 'no article found' }
  }

  const markdown = makeTurndown(dom.window.document.baseURI).turndown(article.content).trim()
  const keptChars = charCount(markdown)
  // Readability will happily return a nav-only page's "Home". Caching a
  // handful of characters is worse than reporting no text, which is the
  // honest answer for a shell page whose content arrives via JavaScript.
  const reason = keptChars < MIN_CHARS ? 'no readable text extracted' : ''
  return { totalChars, markdown, keptChars, reason }
}

// ---------------------------------------------------------------------------
// Deep escalation
//
// Two pages land a reader in the same place: the one where Readability throws,
// and the one where it keeps 154 of 253798 characters and that gets cached as
// a success. Both mean the page did not read.
//
// The ladder answers each with the next tool up, under --deep and nowhere
// else, so the default path and what it costs are untouched. Each rung says so
// in the output, because an escalated extract that looks like an ordinary one
// is the single way this can mislead.
// ---------------------------------------------------------------------------

// crawl4ai renders the page somewhere else and hands back markdown. That makes
// it the cheapest rung here, one second against the five to eight Chrome
// costs, and the only one that fetches from a different address: a site that
// answers this machine with 403 often answers a datacentre with the page.
//
// It is configured by a file this repo does not carry, because the endpoint
// and its token are neither portable nor publishable. No file, no rung, the
// same way a machine with no Chrome skips the next one.
const C4AI_FILE = process.env.DDGX_C4AI_CONFIG || path.join(
  process.env.XDG_CONFIG_HOME || path.join(homedir(), '.config'),
  'ddgx', 'crawl4ai.json'
)
const C4AI_TIMEOUT_MS = parseInt(process.env.DDGX_C4AI_TIMEOUT_MS || '', 10) || 6000
// A service on the far side of a VPN is unreachable for stretches, not for one
// request. Without a note of that, every ctrl-o pays the full timeout on the
// day the tunnel is down, which is already the day the escalation is slowest.
const C4AI_BREAKER = path.join(tmpdir(), 'ddgx-crawl4ai-unreachable')
const C4AI_BREAKER_MS = parseInt(process.env.DDGX_C4AI_BREAKER_MS || '', 10) || 60000

function loadC4ai () {
  if (process.env.DDGX_NO_NETWORK) return null
  try {
    const cfg = JSON.parse(readFileSync(C4AI_FILE, 'utf8'))
    if (typeof cfg.url !== 'string' || !cfg.url) return null
    return {
      url: cfg.url,
      auth: typeof cfg.auth === 'string' ? cfg.auth : '',
      ca: typeof cfg.ca === 'string' ? cfg.ca : ''
    }
  } catch {
    return null
  }
}

function breakerOpen () {
  try {
    return Date.now() - JSON.parse(readFileSync(C4AI_BREAKER, 'utf8')).at < C4AI_BREAKER_MS
  } catch {
    return false
  }
}

// curl rather than fetch, for three reasons that all come from this being a
// preview path: a private CA the process was not started to trust, a connect
// timeout separate from the total one, and a bare binary name a test can stub
// on PATH the way it stubs the other two rungs. The request goes in on stdin
// as a curl config file, so the token never appears in argv, where every other
// process on the machine can read it out of /proc.
async function clusterMarkdown (url) {
  const cfg = loadC4ai()
  if (!cfg || breakerOpen()) return null

  const quote = value => String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')
  const lines = [
    `--url "${quote(cfg.url)}"`,
    '--header "Content-Type: application/json"',
    `--data "${quote(JSON.stringify({ url, f: 'fit' }))}"`,
    '--connect-timeout 2',
    `--max-time ${Math.ceil(C4AI_TIMEOUT_MS / 1000)}`,
    '--silent', '--show-error', '--fail'
  ]
  if (cfg.auth) lines.push(`--header "Authorization: ${quote(cfg.auth)}"`)
  if (cfg.ca) lines.push(`--cacert "${quote(cfg.ca)}"`)

  const res = await run('curl', ['--config', '-'],
    { input: lines.join('\n') + '\n', timeoutMs: C4AI_TIMEOUT_MS + 2000 })
  if (res.missing) return null
  // --fail turns an HTTP error into exit 22, and that is the service answering:
  // it looked at this page and refused it. Only a transport failure means the
  // service is not there, and only that is worth remembering for a minute.
  if (res.code !== 0) {
    if (res.code !== 22) {
      try { writeFileSync(C4AI_BREAKER, JSON.stringify({ at: Date.now() })) } catch {}
    }
    return null
  }

  try {
    const body = JSON.parse(res.stdout)
    let md = body.markdown ?? body.result?.markdown ?? ''
    if (md && typeof md === 'object') md = md.fit_markdown || md.raw_markdown || ''
    return typeof md === 'string' && md.trim() ? md.trim() : null
  } catch {
    return null
  }
}

// Chrome answers to a different name on every distribution, so the first one
// that runs wins. A binary that is present and then fails is the page failing,
// not the binary, so its neighbours are not tried after it.
async function renderDom (url) {
  for (const binary of ['google-chrome', 'chromium', 'chromium-browser']) {
    const res = await run(binary, [
      '--headless=new', '--disable-gpu', '--no-sandbox',
      `--virtual-time-budget=${RENDER_BUDGET_MS}`, '--dump-dom', url
    ], { timeoutMs: RENDER_TIMEOUT_MS })
    if (res.missing) continue
    return res.stdout.trim() ? res.stdout : null
  }
  return null
}

// Readability is an article finder, and some pages are not articles. A docs
// index is a list of links with no prose to score, so the algorithm is right
// to find nothing and still wrong for the reader. w3m holds no opinion about
// articles: it lays the DOM out as text, which is what a person saw.
async function w3mDump (html) {
  const res = await run('w3m', ['-dump', '-T', 'text/html', '-cols', String(W3M_COLS)],
    { input: html, timeoutMs: W3M_TIMEOUT_MS })
  if (res.missing || res.code !== 0) return null
  // Runs of empty lines are w3m's block spacing showing through, not the
  // page's own paragraphs.
  return res.stdout.replace(/[ \t]+$/gm, '').replace(/\n{3,}/g, '\n\n').trim()
}

async function escalate (url, source, first) {
  let best = { read: first, provenance: '' }
  const consider = candidate => {
    if (candidate.read.keptChars > best.read.keptChars) best = candidate
  }

  // Step 2. The cheapest rung and the only one that changes address, so it
  // goes first: it answers the JavaScript page in a second, and it is the only
  // thing here that reaches a page which refused this machine outright.
  const viaCluster = '[deep step 2: crawl4ai fit filter over the cluster renderer]'
  const remote = url ? await clusterMarkdown(url) : null
  if (remote) {
    const kept = charCount(remote)
    // A refused fetch counted nothing, so the page cannot have fewer
    // characters than the ones now in hand. Reporting "kept 6895 of 0" is the
    // stats footer lying about the rung that just rescued the page.
    const read = {
      totalChars: Math.max(first.totalChars, kept), markdown: remote, keptChars: kept, reason: ''
    }
    if (kept >= DEEP_MIN) return { read, provenance: viaCluster }
    consider({ read, provenance: viaCluster })
  }

  // Step 3. "No article found" is usually "no article yet", the body arriving
  // in JavaScript. Give the page a browser and read the DOM it settled on.
  // A missing browser is a rung skipped, not a failure.
  const rendered = url ? await renderDom(url) : null
  let renderedTotal = first.totalChars
  const viaChrome = '[deep step 3: Readability over a headless Chrome render]'
  if (rendered) {
    const read = readDocument(rendered, url)
    renderedTotal = read.totalChars
    if (read.keptChars >= DEEP_MIN) return { read, provenance: viaChrome }
    consider({ read, provenance: viaChrome })
  }

  // Step 4. A real DOM that Readability still scores at nothing means the tool
  // is wrong for this page, not that the text is missing. Same render, no
  // second fetch: rendering twice would double the one expensive part.
  const dumped = await w3mDump(rendered || source)
  if (dumped) {
    consider({
      read: { totalChars: renderedTotal, markdown: dumped, keptChars: charCount(dumped), reason: '' },
      provenance: rendered
        ? '[deep step 4: w3m over that same render, Readability found no article in it]'
        : '[deep step 4: w3m over the served html, no headless browser installed]'
    })
  }
  return best
}

function present (markdown, { maxLines = 0, footer = [] } = {}) {
  let lines = markdown.split('\n')
  const truncated = maxLines > 0 && lines.length > maxLines
  if (truncated) lines = lines.slice(0, maxLines).concat('...')
  if (footer.length) lines.push('', ...footer)
  return lines.join('\n')
}

// The page path, kept whole and separate so the media adapter can fall through
// to it without the two having to read each other's failures.
async function extractPage (url, { html, maxLines, stats, deep }) {
  let source = html
  // A page that refuses this machine outright, 403 to a script or 400 to a
  // fetch with no session, is precisely the page the ladder was built for, and
  // throwing here is what kept --deep from ever reaching a renderer on one.
  // The shallow path still throws: it has no rung to fall to, and the reason
  // it reports is the one the pane prints.
  let refusal = null
  if (source === null) {
    source = url ? await stackExchangeHtml(url).catch(() => null) : null
    if (source === null) {
      try {
        source = await httpGet(url)
      } catch (err) {
        // DDGX_NO_NETWORK is the suite's one lever on the network, and the
        // rungs below reach it by subprocess where the guard cannot see them.
        // Swallowing this particular refusal would hand a test a live Chrome.
        if (!deep || process.env.DDGX_NO_NETWORK) throw err
        refusal = err
        source = ''
      }
    }
  }
  if (!source.trim()) {
    if (!deep) throw new Error('empty document')
    source = ''
  }

  let read = source
    ? readDocument(source, url)
    : { totalChars: 0, markdown: '', keptChars: 0, reason: refusal ? refusal.message : 'empty document' }
  let provenance = ''

  if (deep && (read.reason || read.keptChars < DEEP_MIN)) {
    const better = await escalate(url, source, read)
    provenance = better.provenance
    // Every rung came back thin, so there is nothing worth handing back as a
    // success. Someone who asked for --deep gets the failure, not a nav bar,
    // and keeps the reason the shallow path would have given.
    if (better.read.keptChars < DEEP_MIN) throw new Error(read.reason || 'no readable text extracted')
    read = better.read
  }
  if (read.reason) throw new Error(read.reason)

  const footer = []
  // Make dropped content visible rather than silent: this is how you tell
  // whether the reader threw away half the page.
  if (stats) footer.push(`[kept ${read.keptChars} of ${read.totalChars} characters of page text]`)
  // Same place, same shape, because it answers the neighbouring question: not
  // how much of the page survived, but which tool went and got it.
  if (provenance) footer.push(provenance)
  return present(read.markdown, { maxLines, footer })
}

async function extract (url, { html = null, maxLines = 0, stats = false, deep = false, cache = null } = {}) {
  url = normalizeUrl(url)

  // Decided before anything is fetched: there is no page here to read, and the
  // video's text lives in yt-dlp's json instead. --file means a document is
  // already in hand, so it is that document that gets read.
  let mediaError = null
  if (html === null && url && isMediaUrl(url)) {
    try {
      const { markdown, media } = await mediaMarkdown(url)
      // media is null for a channel, which is a listing rather than something
      // to play. No record means the picker never offers to play it.
      if (media) writeMediaSidecar(cache, url, media)
      // Nothing was dropped, so "kept N of M" would be a tautology. What a
      // reader needs to know here is that this text is the video's, not a page's.
      return present(markdown, {
        maxLines,
        // media is null for a channel, which is still yt-dlp's text and still
        // wants naming, so the kind falls back rather than the line breaking.
        footer: stats ? [`[${charCount(markdown)} characters of ${media?.kind || 'channel'} text via yt-dlp]`] : []
      })
    } catch (err) {
      // A video host serves ordinary pages too. vimeo.com/features is
      // marketing and twitch.tv/directory is a listing, and no path pattern
      // separates those from videos without tracking every site's url scheme
      // forever. So a failed lookup falls through and the url is read as the
      // page it might be, which is what it got before this adapter existed.
      // The same fallback covers yt-dlp being missing, rate limited, or broken
      // by a site change: none of those should take an ordinary page down.
      mediaError = err
    }
  }

  try {
    return await extractPage(url, { html, maxLines, stats, deep })
  } catch (pageError) {
    // Both paths failed, so this is a video whose lookup broke rather than a
    // page. Report the adapter's reason: "no article found" would send the
    // reader hunting for a renderer, which is never what is wrong here.
    throw mediaError || pageError
  }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs (argv) {
  const opts = { maxLines: 0, stats: false, deep: false }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--url') opts.url = argv[++i]
    else if (a === '--file') opts.file = argv[++i]
    else if (a === '--batch') opts.batch = argv[++i]
    else if (a === '--cache') opts.cache = argv[++i]
    else if (a === '--max-lines') opts.maxLines = parseInt(argv[++i], 10)
    else if (a === '--stats') opts.stats = true
    else if (a === '--deep') opts.deep = true
  }
  return opts
}

const cachePath = (dir, url) =>
  path.join(dir, `${createHash('sha1').update(url).digest('hex')}.txt`)

// The picker wants a still frame in its preview pane and a url to play, and
// this process is the only one holding either: recovering them later means a
// second yt-dlp call, which is the two seconds the cache exists to avoid. So
// they land beside the extract, under the same key, as <sha1>.media.
function writeMediaSidecar (dir, url, media) {
  // No cache directory means nobody is going to look for it. Neither the
  // extract nor the exit code changes because of that.
  if (!dir) return
  try {
    mkdirSync(dir, { recursive: true })
    writeFileSync(cachePath(dir, url).replace(/\.txt$/, '.media'), JSON.stringify(media))
  } catch {
    // An unwritable cache costs the preview its thumbnail. It must not cost
    // the caller the text that was successfully extracted.
  }
}

// Warm the cache for every result in one process. Eight separate node starts
// would pay the jsdom import eight times; this pays it once and fetches
// concurrently.
async function runBatch (opts) {
  const results = JSON.parse(readFileSync(opts.batch, 'utf8'))
  mkdirSync(opts.cache, { recursive: true })

  const queue = results.map(r => r.url).filter(Boolean)
    .filter(url => !existsSync(cachePath(opts.cache, url)))

  const CONCURRENCY = parseInt(process.env.DDGX_JOBS || '6', 10) || 6
  let next = 0
  const worker = async () => {
    while (next < queue.length) {
      const url = queue[next++]
      try {
        // --deep travels only when this invocation asked for it. Six headless
        // Chromes at once is not a bill a background prefetch may run up on
        // its own, so the flag has to be typed to reach here.
        const text = await extract(url, { stats: opts.stats, deep: opts.deep, cache: opts.cache })
        writeFileSync(cachePath(opts.cache, url), text)
      } catch {
        // Failures stay uncached so a site that was down gets retried rather
        // than remembered as empty.
      }
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker))
}

async function main () {
  const opts = parseArgs(process.argv.slice(2))

  if (opts.batch) {
    if (!opts.cache) { process.stderr.write('[--batch needs --cache]\n'); return 1 }
    await runBatch(opts)
    return 0
  }

  let html = null
  if (opts.file) html = readFileSync(opts.file, 'utf8')
  else if (!opts.url) { process.stderr.write('[need --url or --file]\n'); return 1 }

  try {
    // Exactly the article, with nothing appended. MarkDownload's own .md files
    // end on the last character too, and a trailing newline here is a
    // presentation choice: __ddgx.sh adds one where it prints.
    process.stdout.write(await extract(opts.url, {
      html, maxLines: opts.maxLines, stats: opts.stats, deep: opts.deep, cache: opts.cache
    }))
    return 0
  } catch (err) {
    process.stderr.write(`[${err.message}]\n`)
    return 1
  }
}

main().then(code => process.exit(code)).catch(err => {
  process.stderr.write(`[${err.message}]\n`)
  process.exit(1)
})
