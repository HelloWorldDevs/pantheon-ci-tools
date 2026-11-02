#!/usr/bin/env node
/**
 * Summarize JUnit failures for a Slack notification (CircleCI).
 *
 * Reads the JUnit XML a test runner wrote, finds every failing/undefined test,
 * and writes a Slack mrkdwn message to $BASH_ENV as SLACK_FAILURE_TEXT (already
 * JSON-string-escaped so it can be dropped into the slack orb's custom block),
 * plus SLACK_FAILURE_COUNT, SLACK_PRIMARY_URL and SLACK_PRIMARY_LABEL for the
 * button. Each failure names the test, the step/assertion that broke and how,
 * and deep-links to the artifact that shows it (FailAid screenshot for Behat,
 * the HTML report for Playwright). No dependencies — node only.
 *
 * Distributed by helloworlddevs/pantheon-ci-tools.
 *
 * Usage:
 *   node summarize-junit-failures.js --kind behat \
 *        --dir tests/behat/results/junit --local-root tests/behat/results \
 *        --artifact-dest artifacts
 *   node summarize-junit-failures.js --kind playwright \
 *        --file test-results/junit.xml --report-artifact playwright-report/index.html
 *
 * Options:
 *   --kind behat|playwright   Message wording + per-kind parsing. Required.
 *   --dir <path>              Directory searched recursively for *.xml.
 *   --file <path>             A single JUnit file. (--dir or --file required)
 *   --local-root <path>       Local directory that store_artifacts uploaded…
 *   --artifact-dest <name>    …under this destination. Paths found in failure
 *                             messages below --local-root become artifact links.
 *   --report-artifact <path>  Artifact path of an HTML report to link (Playwright).
 *   --title <text>            Headline override.
 *   --max <n>                 Max failures to list (default 8).
 *   --out <path>              Where to append exports (default $BASH_ENV, else stdout).
 *   --post                    Post the message to Slack directly (chat.postMessage)
 *                             using $SLACK_ACCESS_TOKEN — the same bot token the
 *                             CircleCI slack orb uses — when there is something to
 *                             say: any failure OR any undefined/pending step. Lets
 *                             the job run this with `when: always` as a digest
 *                             without spamming on clean passes.
 *   --always                  With --post: post even when everything passed.
 *   --channel <id>            Slack channel for --post (default $SLACK_DEFAULT_CHANNEL).
 *   --job-status pass|fail    Lets the digest title say "failed" when the job
 *                             failed outside of a test (no JUnit failure).
 */
'use strict';
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// args
// ---------------------------------------------------------------------------
const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) {
    const k = a.slice(2);
    const next = process.argv[i + 1];
    if (next !== undefined && !next.startsWith('--')) { args[k] = next; i++; } else { args[k] = 'true'; }
  }
}
const KIND = args.kind;
if (!KIND || !['behat', 'playwright'].includes(KIND)) { console.error('--kind behat|playwright is required'); process.exit(2); }
if (!args.dir && !args.file) { console.error('--dir or --file is required'); process.exit(2); }
const MAX = parseInt(args.max || '8', 10);

// ---------------------------------------------------------------------------
// CircleCI context → URLs
// ---------------------------------------------------------------------------
const env = process.env;
const org = env.CIRCLE_PROJECT_USERNAME || '';
const repo = env.CIRCLE_PROJECT_REPONAME || '';
const vcs = /bitbucket/i.test(env.CIRCLE_REPOSITORY_URL || '') ? 'bitbucket' : 'github';
const jobBase = (org && repo && env.CIRCLE_PIPELINE_NUMBER && env.CIRCLE_WORKFLOW_ID && env.CIRCLE_BUILD_NUM)
  ? `https://app.circleci.com/pipelines/${vcs}/${org}/${repo}/${env.CIRCLE_PIPELINE_NUMBER}/workflows/${env.CIRCLE_WORKFLOW_ID}/jobs/${env.CIRCLE_BUILD_NUM}`
  : (env.CIRCLE_BUILD_URL || '');
const testsUrl = jobBase ? `${jobBase}/tests` : '';
const artifactsUrl = jobBase ? `${jobBase}/artifacts` : '';
const nodeIndex = env.CIRCLE_NODE_INDEX || '0';
const nodeTotal = parseInt(env.CIRCLE_NODE_TOTAL || '1', 10);
function artifactUrl(relPath) {
  if (!env.CIRCLE_WORKFLOW_JOB_ID) return '';
  const clean = String(relPath).replace(/^\/+/, '').split('/').map(encodeURIComponent).join('/');
  return `https://output.circle-artifacts.com/output/job/${env.CIRCLE_WORKFLOW_JOB_ID}/artifacts/${nodeIndex}/${clean}`;
}
function localToArtifact(localPath) {
  if (!args['local-root'] || !args['artifact-dest'] || !localPath) return '';
  const dest = args['artifact-dest'].replace(/\/+$/, '');
  const rootNorm = args['local-root'].replace(/^\.\//, '').replace(/\/+$/, '');
  // Match on the path TAIL, not on resolved absolute paths: the tool writes
  // screenshots via whatever directory behat.yml names (often the legacy
  // /var/www/project symlink) while the job runs in ~/project, so the two
  // absolute forms differ even though they are the same directory.
  const marker = `/${rootNorm}/`;
  const idx = String(localPath).indexOf(marker);
  if (idx >= 0) return artifactUrl(`${dest}/${String(localPath).slice(idx + marker.length)}`);
  const root = path.resolve(args['local-root']);
  const abs = path.resolve(localPath);
  if (abs.startsWith(root + path.sep)) return artifactUrl(`${dest}/${path.relative(root, abs).split(path.sep).join('/')}`);
  return '';
}

// ---------------------------------------------------------------------------
// tiny JUnit reader (regex-based; JUnit from Behat/Playwright is flat & simple)
// ---------------------------------------------------------------------------
function decode(s) {
  return String(s || '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(parseInt(n, 10)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}
function attrs(tag) {
  const out = {};
  const re = /([\w:-]+)\s*=\s*"([^"]*)"|([\w:-]+)\s*=\s*'([^']*)'/g;
  let m;
  while ((m = re.exec(tag))) out[m[1] || m[3]] = decode(m[2] !== undefined ? m[2] : m[4]);
  return out;
}
function cdataOrText(s) {
  const m = /<!\[CDATA\[([\s\S]*?)\]\]>/.exec(s);
  return decode(m ? m[1] : s.replace(/<[^>]+>/g, ''));
}
function listXml(p) {
  const st = fs.statSync(p);
  if (st.isFile()) return [p];
  const out = [];
  for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    const full = path.join(p, e.name);
    if (e.isDirectory()) out.push(...listXml(full));
    else if (e.isFile() && e.name.endsWith('.xml')) out.push(full);
  }
  return out;
}
function parse(xml) {
  const cases = [];
  // Walk testsuite blocks so each testcase knows its suite (= Behat feature title / Playwright file).
  const suiteRe = /<testsuite\b([^>]*)>([\s\S]*?)<\/testsuite>/g;
  let sm;
  while ((sm = suiteRe.exec(xml))) {
    const suite = attrs(sm[1]);
    const body = sm[2];
    const caseRe = /<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g;
    let cm;
    while ((cm = caseRe.exec(body))) {
      const tc = attrs(cm[1]);
      const inner = cm[3] || '';
      const fm = /<(failure|error)\b([^>]*?)(\/>|>([\s\S]*?)<\/\1>)/.exec(inner);
      if (!fm) continue;
      const fattrs = attrs(fm[2]);
      const so = /<system-out>([\s\S]*?)<\/system-out>/.exec(inner);
      cases.push({
        suite, tc,
        kind: fm[1],
        type: fattrs.type || '',
        message: fattrs.message || '',
        body: fm[4] ? cdataOrText(fm[4]) : '',
        systemOut: so ? cdataOrText(so[1]) : '',
      });
    }
  }
  return cases;
}

const files = (args.dir ? (fs.existsSync(args.dir) ? listXml(args.dir) : []) : [])
  .concat(args.file && fs.existsSync(args.file) ? [args.file] : []);
let all = [];
for (const f of files) {
  try { all = all.concat(parse(fs.readFileSync(f, 'utf8'))); } catch (e) { console.error(`skip ${f}: ${e.message}`); }
}

// ---------------------------------------------------------------------------
// shape per kind
// ---------------------------------------------------------------------------
function firstLine(s) { return String(s || '').split('\n').map(x => x.trim()).filter(Boolean)[0] || ''; }
function esc(s) { return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\$/g, '＄'); }
function clip(s, n) { s = String(s || ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }
function link(url, label) { return url ? `<${url}|${esc(label)}>` : esc(label); }

const failures = [];   // real failures
const undefinedSteps = []; // behat undefined/pending
for (const c of all) {
  if (KIND === 'behat') {
    const isUndef = c.kind === 'error' && /undefined|pending/i.test(c.type);
    const [stepLine, ...rest] = c.message.split('\n');
    // Behat's message = "<Keyword> <step text>: <exception first line>" + FailAid facts.
    const colon = stepLine.indexOf(': ');
    const step = colon > 0 ? stepLine.slice(0, colon) : stepLine;
    const why = colon > 0 ? stepLine.slice(colon + 2).replace(/\s*\([A-Za-z\\]+Exception\)\s*$/, '') : '';
    const facts = {};
    for (const l of rest) { const m = /^\[([A-Z ]+)\]\s*(.*)$/.exec(l.trim()); if (m) facts[m[1]] = m[2]; }
    const featureFile = (c.tc.file || c.suite.file || facts.FEATURE || '').replace(/^.*?(tests\/behat\/)/, '$1');
    // Behat may already suffix the file with the scenario line (file:NN); only
    // add the failing step's line when it hasn't.
    const hasLine = /:\d+$/.test(featureFile);
    const where = featureFile ? `${featureFile}${!hasLine && c.tc.line ? ':' + c.tc.line : ''}` : (c.tc.line ? `line ${c.tc.line}` : '');
    const item = {
      name: c.tc.name || '(unnamed scenario)',
      feature: c.suite.name || c.tc.classname || '',
      where, step, why,
      pageUrl: facts.URL || '', status: facts.STATUS || '',
      screenshot: facts.SCREENSHOT ? localToArtifact(facts.SCREENSHOT) : '',
    };
    (isUndef ? undefinedSteps : failures).push(item);
  } else {
    // Playwright: name = "describe › title", message = "file:line:col title", body = full error text.
    const name = (c.tc.name || '').split(' › ').pop();
    const loc = /^(\S+:\d+:\d+)/.exec(c.message || '');
    const errLine = (c.body.split('\n').map(x => x.trim()).find(x => /^Error:|^expect\(|^Timeout|^TimeoutError|^Test timeout/.test(x)) || firstLine(c.body) || c.message);
    failures.push({
      name, feature: c.suite.name || c.tc.classname || '',
      where: loc ? loc[1] : '', step: '', why: errLine,
    });
  }
}

const count = failures.length;
const undefCount = undefinedSteps.length;
const shard = nodeTotal > 1 ? ` · shard ${parseInt(nodeIndex, 10) + 1}/${nodeTotal}` : '';
const jobFailed = (args['job-status'] || '').toLowerCase() === 'fail';
const suiteLabel = KIND === 'behat' ? 'Behat' : 'Visual regression';
let state;            // failed | undefined-only | job-failed-no-junit | passed
if (count > 0) state = 'failed';
else if (undefCount > 0) state = 'undefined-only';
else if (jobFailed || !args['job-status']) state = 'job-failed-no-junit';
else state = 'passed';
const icon = { failed: '🔴', 'undefined-only': '🟡', 'job-failed-no-junit': '🔴', passed: '🟢' }[state];
const defaultTitle = {
  failed: `${suiteLabel} tests failed`,
  'undefined-only': `${suiteLabel} passed, but ${undefCount} scenario${undefCount === 1 ? ' has' : 's have'} undefined steps`,
  'job-failed-no-junit': `${suiteLabel} job failed`,
  passed: `${suiteLabel} passed`,
}[state];
const title = args.title || defaultTitle;
const lines = [];
lines.push(`${icon} *${esc(title)}:* ${esc(repo)} (${esc(env.CIRCLE_BRANCH || '')})${shard}`);
lines.push('');
if (state === 'job-failed-no-junit') {
  lines.push('_The job failed but no failing test was recorded in JUnit — the failure is in a setup/teardown step, not a test. Open the job steps._');
} else if (state === 'passed') {
  lines.push('_All scenarios passed and every step is defined._');
} else {
  if (count > 0) lines.push(`*${count} ${KIND === 'behat' ? 'scenario' : 'test'}${count === 1 ? '' : 's'} failed:*`);
  failures.slice(0, MAX).forEach(f => {
    const head = `• *${esc(clip(f.name, 120))}*` + (f.feature ? ` — _${esc(clip(f.feature, 80))}_` : '') + (f.where ? ` \`${esc(f.where)}\`` : '');
    lines.push(head);
    if (f.step || f.why) lines.push(`    ✗ ${esc(clip([f.step, f.why].filter(Boolean).join(' → '), 300))}`);
    const extras = [];
    if (f.screenshot) extras.push(link(f.screenshot, 'screenshot'));
    if (f.pageUrl) extras.push(`page: ${esc(clip(f.pageUrl, 120))}${f.status ? ` (HTTP ${esc(f.status)})` : ''}`);
    if (extras.length) lines.push(`    ${extras.join(' · ')}`);
  });
  if (count > MAX) lines.push(`    _…and ${count - MAX} more — see the Tests tab._`);
  if (undefCount > 0) {
    if (count > 0) lines.push('');
    lines.push(`*${undefCount} scenario${undefCount === 1 ? '' : 's'} with undefined/pending steps* — these need step definitions (the runner does not count them as failures):`);
    undefinedSteps.slice(0, MAX).forEach(u => {
      lines.push(`• *${esc(clip(u.name, 100))}*${u.feature ? ` — _${esc(clip(u.feature, 60))}_` : ''}${u.where ? ` \`${esc(u.where)}\`` : ''}`);
      if (u.step) lines.push(`    ? ${esc(clip(u.step, 160))}`);
    });
    if (undefCount > MAX) lines.push(`    _…and ${undefCount - MAX} more — see the Tests tab._`);
  }
}
lines.push('');
const footer = [];
if (testsUrl) footer.push(link(testsUrl, 'Tests tab'));
if (args['report-artifact']) { const u = artifactUrl(args['report-artifact']); if (u) footer.push(link(u, KIND === 'playwright' ? 'HTML diff report' : 'report')); }
if (artifactsUrl) footer.push(link(artifactsUrl, 'Artifacts'));
if (jobBase) footer.push(link(jobBase, 'Job'));
if (footer.length) lines.push(footer.join(' · '));

let text = lines.join('\n');
if (text.length > 2900) text = text.slice(0, 2880) + '\n_…truncated_';

// Primary button: Tests tab for Behat; HTML report for Playwright (falls back to tests tab / job).
let primaryUrl = testsUrl || jobBase || env.CIRCLE_BUILD_URL || '';
let primaryLabel = 'View failed tests';
if (KIND === 'playwright' && args['report-artifact'] && artifactUrl(args['report-artifact'])) {
  primaryUrl = artifactUrl(args['report-artifact']); primaryLabel = 'Open diff report';
}
if (state === 'job-failed-no-junit' && jobBase) { primaryUrl = jobBase; primaryLabel = 'Open job'; }
if (state === 'undefined-only') primaryLabel = 'View undefined steps';
if (state === 'passed') primaryLabel = 'View tests';

// ---------------------------------------------------------------------------
// emit: JSON-string-escaped for the slack orb template; single-quoted for bash.
// ---------------------------------------------------------------------------
const jsonEscaped = JSON.stringify(text).slice(1, -1);
const sq = s => `'${String(s).replace(/'/g, `'\\''`)}'`;
const exportsOut = [
  `export SLACK_FAILURE_TEXT=${sq(jsonEscaped)}`,
  `export SLACK_FAILURE_COUNT=${sq(count)}`,
  `export SLACK_UNDEFINED_COUNT=${sq(undefCount)}`,
  `export SLACK_PRIMARY_URL=${sq(primaryUrl)}`,
  `export SLACK_PRIMARY_LABEL=${sq(primaryLabel)}`,
  '',
].join('\n');
const shouldNotify = count > 0 || undefCount > 0 || state === 'job-failed-no-junit' || args.always === 'true';
const out = args.out || env.BASH_ENV;
const exportsAll = exportsOut + `export SLACK_SHOULD_NOTIFY=${sq(shouldNotify ? 'true' : 'false')}\n`;
if (out) fs.appendFileSync(out, exportsAll); else process.stdout.write(exportsAll);
console.log(`Summarized ${count} failure(s), ${undefCount} undefined from ${files.length} JUnit file(s); state=${state}; notify=${shouldNotify}.`);
console.log(text);

// ---------------------------------------------------------------------------
// --post: send it ourselves via chat.postMessage. The slack orb can only fire
// on pass/fail, not on "there is something worth saying", which is what a
// digest needs. Same bot token (SLACK_ACCESS_TOKEN) and channel as the orb.
// ---------------------------------------------------------------------------
async function post() {
  if (args.post !== 'true') return;
  if (!shouldNotify) { console.log('Nothing to report — not posting to Slack.'); return; }
  const token = env.SLACK_ACCESS_TOKEN;
  const channel = args.channel || env.SLACK_DEFAULT_CHANNEL;
  if (!token) { console.error('::warning:: SLACK_ACCESS_TOKEN not set — skipping Slack post.'); return; }
  if (!channel) { console.error('::warning:: no --channel / SLACK_DEFAULT_CHANNEL — skipping Slack post.'); return; }
  const blocks = [{ type: 'section', text: { type: 'mrkdwn', text } }];
  if (primaryUrl) blocks.push({ type: 'actions', elements: [{ type: 'button', text: { type: 'plain_text', text: primaryLabel, emoji: true }, url: primaryUrl }] });
  const payload = { channel, text: `${title}: ${repo} (${env.CIRCLE_BRANCH || ''})`, blocks, unfurl_links: false, unfurl_media: false };
  const api = (env.SLACK_API_URL || 'https://slack.com/api').replace(/\/+$/, '');
  const res = await fetch(`${api}/chat.postMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8', Authorization: `Bearer ${token}` },
    body: JSON.stringify(payload),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ok === false) {
    console.error(`::warning:: Slack post failed: HTTP ${res.status} ${data.error || ''}`);
    return;  // never fail the job over a notification
  }
  console.log(`Posted to Slack channel ${channel} (ts ${data.ts || '?'}).`);
}
post().catch(e => console.error(`::warning:: Slack post error: ${e.message}`));
