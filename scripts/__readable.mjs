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
//   __readable.mjs --batch results.json --cache ~/.cache/ddgx
//
// Exits 1 when a page cannot be fetched or holds no article, so callers can
// avoid caching a failure.

import { createRequire } from 'node:module'
import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { homedir } from 'node:os'
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

// ---------------------------------------------------------------------------
// Fetching
// ---------------------------------------------------------------------------

async function httpGet (url, { json = false } = {}) {
  const scheme = new URL(url).protocol
  // Previews are driven by search results; a file: or gopher: URL there must
  // not make us read the local disk.
  if (scheme !== 'http:' && scheme !== 'https:') throw new Error(`unsupported scheme: ${scheme}`)

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
  if (ctype && !/html|xml|text\/plain/i.test(ctype)) {
    throw new Error(`not a web page: ${ctype.split(';')[0].trim()}`)
  }
  return res.text()
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

async function extract (url, { html = null, maxLines = 0, stats = false } = {}) {
  let source = html
  if (source === null) {
    source = url ? await stackExchangeHtml(url).catch(() => null) : null
    if (source === null) source = await httpGet(url)
  }
  if (!source.trim()) throw new Error('empty document')

  const dom = new JSDOM(source, url ? { url } : {})
  const totalChars = (dom.window.document.body?.textContent || '').replace(/\s+/g, ' ').trim().length

  const article = new Readability(dom.window.document).parse()
  if (!article || !article.content) throw new Error('no article found')

  const markdown = makeTurndown(dom.window.document.baseURI).turndown(article.content).trim()
  if (!markdown) throw new Error('no readable text extracted')

  const keptChars = markdown.replace(/\s+/g, ' ').trim().length
  // Readability will happily return a nav-only page's "Home". Caching a
  // handful of characters is worse than reporting no text, which is the
  // honest answer for a shell page whose content arrives via JavaScript.
  if (keptChars < MIN_CHARS) throw new Error('no readable text extracted')

  let lines = markdown.split('\n')
  const truncated = maxLines > 0 && lines.length > maxLines
  if (truncated) lines = lines.slice(0, maxLines).concat('...')

  if (stats) {
    // Make dropped content visible rather than silent: this is how you tell
    // whether the reader threw away half the page.
    lines.push('', `[kept ${keptChars} of ${totalChars} characters of page text]`)
  }
  return lines.join('\n')
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs (argv) {
  const opts = { maxLines: 0, stats: false }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--url') opts.url = argv[++i]
    else if (a === '--file') opts.file = argv[++i]
    else if (a === '--batch') opts.batch = argv[++i]
    else if (a === '--cache') opts.cache = argv[++i]
    else if (a === '--max-lines') opts.maxLines = parseInt(argv[++i], 10)
    else if (a === '--stats') opts.stats = true
  }
  return opts
}

const cachePath = (dir, url) =>
  path.join(dir, `${createHash('sha1').update(url).digest('hex')}.txt`)

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
        const text = await extract(url, { stats: opts.stats })
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
      html, maxLines: opts.maxLines, stats: opts.stats
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
