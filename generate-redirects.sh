#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Generate a redirect site from a frozen snapshot of URLs.
#
# urls.txt contains a permanent snapshot of every URL path
# from sidecar.clutch.engineering as of 2026-03-15. This file
# is committed to the repo and should NOT be regenerated from
# live data — it is the canonical redirect map.
#
# SOURCE: the domain this site is served on
# TARGET: the domain all URLs redirect to
# ─────────────────────────────────────────────────────────────

SOURCE="pelican.clutch.engineering"
TARGET="sidecar.clutch.engineering"
OUT="site"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
URLS_FILE="$SCRIPT_DIR/urls.txt"

if [ ! -f "$URLS_FILE" ]; then
  echo "Error: urls.txt not found. This file is a frozen snapshot and must be committed to the repo."
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

URL_COUNT=$(wc -l < "$URLS_FILE" | tr -d ' ')
echo "Loading ${URL_COUNT} URLs from frozen snapshot (urls.txt)"

# ── Helper: create a redirect HTML file ──────────────────────
make_redirect() {
  local url_path="$1"
  local target_url="https://${TARGET}${url_path}"

  # Determine filesystem output path
  if [ "$url_path" = "/" ]; then
    local file="$OUT/index.html"
  elif [[ "$url_path" == *.* ]] && [[ "$url_path" != */ ]]; then
    # Non-directory file (e.g. /feed.atom) — skip, 404.html handles these
    return
  else
    local dir="$OUT${url_path}"
    mkdir -p "$dir"
    local file="${dir}index.html"
  fi

  cat > "$file" <<REDIRECT_HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Redirecting…</title>
<link rel="canonical" href="${target_url}">
<meta http-equiv="refresh" content="0;url=${target_url}">
<script>window.location.replace("${target_url}");</script>
</head>
<body>
<p>This page has moved to <a href="${target_url}">${target_url}</a>.</p>
</body>
</html>
REDIRECT_HTML
}

# ── Generate redirect pages ──────────────────────────────────
echo "Generating redirect pages..."
GENERATED=0

while IFS= read -r path; do
  [ -z "$path" ] && continue
  make_redirect "$path"
  GENERATED=$((GENERATED + 1))
done < "$URLS_FILE"

echo "Generated ${GENERATED} redirect pages"

# ── Catch-all 404.html ───────────────────────────────────────
# GitHub Pages serves 404.html for any unmatched path.
# Safety net for non-directory files, query strings, and any
# paths not in the frozen snapshot.
# ──────────────────────────────────────────────────────────────
cat > "$OUT/404.html" <<CATCHALL_HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Redirecting…</title>
<script>
(function() {
  var target = "https://${TARGET}" + window.location.pathname + window.location.search + window.location.hash;
  var link = document.createElement("link");
  link.rel = "canonical";
  link.href = target;
  document.head.appendChild(link);
  var meta = document.createElement("meta");
  meta.httpEquiv = "refresh";
  meta.content = "0;url=" + target;
  document.head.appendChild(meta);
  window.location.replace(target);
})();
</script>
</head>
<body>
<p>Redirecting to <a id="target-link">${TARGET}</a>…</p>
<script>
var a = document.getElementById("target-link");
var url = "https://${TARGET}" + window.location.pathname;
a.href = url;
a.textContent = url;
</script>
</body>
</html>
CATCHALL_HTML

echo "Generated 404.html (catch-all)"

# ── CNAME ─────────────────────────────────────────────────────
echo "$SOURCE" > "$OUT/CNAME"

# ── .nojekyll ─────────────────────────────────────────────────
touch "$OUT/.nojekyll"

# ── Summary ───────────────────────────────────────────────────
FINAL_COUNT=$(find "$OUT" -name '*.html' | wc -l | tr -d ' ')
echo ""
echo "Done! ${FINAL_COUNT} HTML files in ${OUT}/"
echo "  - ${GENERATED} pages from frozen snapshot"
echo "  - 1 catch-all 404.html"
echo "  - CNAME → ${SOURCE}"
