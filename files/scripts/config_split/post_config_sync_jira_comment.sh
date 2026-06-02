#!/usr/bin/env bash
#
# Post the config-sync report directly to Jira as a comment on the linked
# issue. Mirrors what `post_config_sync_comment.sh` does for GitHub PRs,
# but talks to Jira's REST API directly so prod-side config drift gets
# recorded on the ticket even when:
#   - there is no PR associated with the build (direct merges to main,
#     scheduled runs, manual rebuilds), or
#   - the GitHub → Jira mirror workflow (pr-comments-to-jira.yml) isn't
#     installed / is failing for this repo.
#
# Required env vars:
#   JIRA_BASE_URL   - e.g. https://yourorg.atlassian.net
#   JIRA_USER       - Jira account email used for API auth
#   JIRA_TOKEN      - Jira API token
#   JIRA_TICKET_ID  - Set by setup_vars.sh from the branch name (e.g. WAV-123)
#
# Optional env vars:
#   CONFIG_SYNC_REPORT  - path to the sync report (default /tmp/config-sync-report.md)
#   CIRCLE_PULL_REQUEST - linked at the top of the comment when set
#   CIRCLE_BUILD_URL    - linked at the top of the comment when set
#   TERMINUS_SITE       - shown in the comment header when set
#
# This step is intentionally non-fatal: if the report is missing,
# credentials aren't configured, or the Jira API call fails, we log and
# exit 0 so we never break the deploy over a Jira hiccup.

set -euo pipefail

REPORT_FILE="${CONFIG_SYNC_REPORT:-/tmp/config-sync-report.md}"

# JIRA_TICKET_ID is set by setup_vars.sh. Skip placeholder values and the
# PR-derived fallback ("PR-123") since those aren't real Jira issue keys.
case "${JIRA_TICKET_ID:-}" in
  ""|NO_TICKET|PR-*)
    echo "JIRA_TICKET_ID='${JIRA_TICKET_ID:-}' is not a Jira issue key — skipping Jira comment."
    exit 0
    ;;
esac

if [ ! -s "${REPORT_FILE}" ]; then
  echo "No report file at ${REPORT_FILE} — skipping Jira comment."
  exit 0
fi

# Only post when prod actually contributed changes: either prod-side
# updates/additions, or a conflict (a PR-changed file that also diverged on
# prod). A report that only lists "Updated in this PR" isn't prod drift, so
# we skip it — those changes are already visible in the PR itself.
if ! grep -qE '^\*\*(Updated|Added) from prod|Changed in both this PR and prod' "${REPORT_FILE}"; then
  echo "No prod-side config changes in report — skipping Jira comment."
  exit 0
fi

missing=0
for var in JIRA_BASE_URL JIRA_USER JIRA_TOKEN; do
  if [ -z "${!var:-}" ]; then
    echo "⚠️  ${var} is not set — add it to a CircleCI context to enable direct Jira posting."
    missing=1
  fi
done
if [ "${missing}" -eq 1 ]; then
  exit 0
fi

AUTH="$(printf '%s' "${JIRA_USER}:${JIRA_TOKEN}" | base64 | tr -d '\n')"
URL="${JIRA_BASE_URL%/}/rest/api/3/issue/${JIRA_TICKET_ID}/comment"

PAYLOAD_FILE="$(mktemp)"
trap 'rm -f "${PAYLOAD_FILE}"' EXIT

# Convert the markdown sync report into an ADF (Atlassian Document Format)
# payload. Tailored to the known sync-prod-config.sh report structure so we
# don't pull in a full markdown→ADF dependency. We pass the report path via
# env to a separate python script invocation rather than a heredoc inside
# $(...) — bash mis-parses backticks inside nested heredocs even when the
# delimiter is single-quoted.
REPORT_FILE="${REPORT_FILE}" \
TERMINUS_SITE="${TERMINUS_SITE:-}" \
CIRCLE_PULL_REQUEST="${CIRCLE_PULL_REQUEST:-}" \
CIRCLE_BUILD_URL="${CIRCLE_BUILD_URL:-}" \
PAYLOAD_FILE="${PAYLOAD_FILE}" \
python3 - <<'PY'
import json, os, re

with open(os.environ["REPORT_FILE"]) as f:
    lines = [l.rstrip("\n") for l in f]

content = []

header = [{"type": "text",
           "text": "Drupal config drift synced from prod",
           "marks": [{"type": "strong"}]}]
site = os.environ.get("TERMINUS_SITE")
if site:
    header.append({"type": "text", "text": " \u2014 " + site + ".live"})
content.append({"type": "paragraph", "content": header})

links = []
pr_url = os.environ.get("CIRCLE_PULL_REQUEST")
if pr_url:
    links.append({"type": "text", "text": "View PR",
                  "marks": [{"type": "link", "attrs": {"href": pr_url}}]})
build_url = os.environ.get("CIRCLE_BUILD_URL")
if build_url:
    if links:
        links.append({"type": "text", "text": " \u00b7 "})
    links.append({"type": "text", "text": "CircleCI build",
                  "marks": [{"type": "link", "attrs": {"href": build_url}}]})
if links:
    content.append({"type": "paragraph", "content": links})

section_re = re.compile(r"^\*\*(?P<title>[^*]+)\*\*\s*$")
bullet_re  = re.compile(r"^-\s+" + chr(96) + r"(?P<file>[^" + chr(96) + r"]+)" + chr(96) + r"\s*$")
italic_re  = re.compile(r"^_(?P<text>.+)_\s*$")
fence = chr(96) * 3

current_list = None
in_code = False
code_lines = []
for line in lines:
    # Fenced code block (``` ... ```): accumulate verbatim into an ADF
    # codeBlock so multi-line shell steps render as one monospace block
    # instead of one paragraph per line. Checked first so blank lines and
    # markdown inside the fence are preserved.
    if line.strip().startswith(fence):
        if not in_code:
            in_code = True
            code_lines = []
        else:
            node = {"type": "codeBlock", "attrs": {"language": "bash"}}
            if code_lines:
                node["content"] = [{"type": "text", "text": "\n".join(code_lines)}]
            content.append(node)
            in_code = False
            current_list = None
        continue
    if in_code:
        code_lines.append(line)
        continue

    if not line.strip():
        current_list = None
        continue
    if line.startswith("###"):
        continue

    sec = section_re.match(line)
    if sec:
        content.append({"type": "paragraph",
                        "content": [{"type": "text", "text": sec.group("title"),
                                     "marks": [{"type": "strong"}]}]})
        current_list = {"type": "bulletList", "content": []}
        content.append(current_list)
        continue

    bul = bullet_re.match(line)
    if bul and current_list is not None:
        current_list["content"].append({
            "type": "listItem",
            "content": [{
                "type": "paragraph",
                "content": [{"type": "text", "text": bul.group("file"),
                             "marks": [{"type": "code"}]}]
            }]
        })
        continue

    ital = italic_re.match(line)
    if ital:
        content.append({"type": "paragraph",
                        "content": [{"type": "text", "text": ital.group("text"),
                                     "marks": [{"type": "em"}]}]})
        current_list = None
        continue

    content.append({"type": "paragraph",
                    "content": [{"type": "text", "text": line}]})
    current_list = None

content = [c for c in content
           if not (c.get("type") == "bulletList" and not c["content"])]

payload = {"body": {"type": "doc", "version": 1, "content": content}}
with open(os.environ["PAYLOAD_FILE"], "w") as f:
    json.dump(payload, f)
PY

echo "Posting config-sync report to Jira ${JIRA_TICKET_ID}..."
# `|| true` so a transport-level curl failure (DNS, connect, TLS) doesn't
# abort the deploy under `set -e`; we still inspect the http code below.
HTTP_CODE="$(curl -sS -o /tmp/jira-comment-response.json -w '%{http_code}' -X POST \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-binary "@${PAYLOAD_FILE}" \
  "${URL}" || true)"

if [ "${HTTP_CODE}" = "201" ] || [ "${HTTP_CODE}" = "200" ]; then
  echo "✅ Posted config-sync report to Jira ${JIRA_TICKET_ID}"
else
  echo "❌ Failed to post Jira comment (HTTP '${HTTP_CODE:-none}')"
  cat /tmp/jira-comment-response.json 2>/dev/null || true
  echo
  # Non-fatal: don't break the build over a Jira API hiccup.
  exit 0
fi
