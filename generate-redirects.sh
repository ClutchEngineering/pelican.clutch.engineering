#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Generate a complete redirect site for pelican.clutch.engineering
# that redirects every URL to sidecar.clutch.engineering
#
# Phase 1: pelican.* → sidecar.*  (testing redirects)
# Phase 2: swap TARGET to pelican, deploy on sidecar repo
#
# This script pulls the live sitemap.xml from production to
# ensure 1:1 coverage of every URL on the site.
# ─────────────────────────────────────────────────────────────

SOURCE="pelican.clutch.engineering"
TARGET="sidecar.clutch.engineering"
OUT="site"

rm -rf "$OUT"
mkdir -p "$OUT"

# ── Download live sitemap from production ────────────────────
echo "Downloading sitemap from https://${TARGET}/sitemap.xml..."
SITEMAP_FILE=$(mktemp)
curl -sS "https://${TARGET}/sitemap.xml" -o "$SITEMAP_FILE"

# Extract all URLs from the sitemap, convert to paths
SITEMAP_PATHS=$(sed -n 's|.*<loc>https://'"${TARGET}"'\([^<]*\)</loc>.*|\1|p' "$SITEMAP_FILE" | sort -u)
SITEMAP_COUNT=$(echo "$SITEMAP_PATHS" | wc -l | tr -d ' ')
echo "Found ${SITEMAP_COUNT} URLs in production sitemap"

# ── Pages known to exist but not in sitemap ──────────────────
# leave-a-review: explicitly excluded from sitemap generation
# feed.atom: generated separately from the sitemap dictionary
EXTRA_PATHS="/leave-a-review/
/feed.atom"

# Combine all paths
ALL_PATHS=$(printf '%s\n%s' "$SITEMAP_PATHS" "$EXTRA_PATHS" | sort -u)
TOTAL_COUNT=$(echo "$ALL_PATHS" | wc -l | tr -d ' ')
echo "Total paths including extras: ${TOTAL_COUNT}"

# ── Helper: create a redirect HTML file ──────────────────────
make_redirect() {
  local url_path="$1"
  local target_url="https://${TARGET}${url_path}"

  # Determine filesystem output path
  if [ "$url_path" = "/" ]; then
    local file="$OUT/index.html"
  elif [[ "$url_path" == *.* ]] && [[ "$url_path" != */ ]]; then
    # Non-directory file (e.g. /feed.atom) — can't create index.html
    # We'll skip these and let 404.html handle them since GitHub Pages
    # can't serve a redirect for a bare file path without the actual file
    mkdir -p "$OUT/$(dirname "$url_path")"
    # Create an HTML file at this exact path — won't work for .atom/.xml
    # but the 404.html catch-all will handle these
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
done <<< "$ALL_PATHS"

echo "Generated ${GENERATED} redirect pages"

# ── Catch-all 404.html ───────────────────────────────────────
# GitHub Pages serves 404.html for any unmatched path.
# This is the safety net for:
#   - Any new pages added after this script last ran
#   - Non-directory files (feed.atom, *.json, etc.)
#   - Query strings and hash fragments
# ──────────────────────────────────────────────────────────────
cat > "$OUT/404.html" <<'CATCHALL_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Redirecting…</title>
<script>
(function() {
  var target = "https://sidecar.clutch.engineering" + window.location.pathname + window.location.search + window.location.hash;
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
<p>Redirecting to <a id="target-link">sidecar.clutch.engineering</a>…</p>
<script>
var a = document.getElementById("target-link");
var url = "https://sidecar.clutch.engineering" + window.location.pathname;
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

# ── Cleanup ───────────────────────────────────────────────────
rm -f "$SITEMAP_FILE"

# ── Summary ───────────────────────────────────────────────────
FINAL_COUNT=$(find "$OUT" -name '*.html' | wc -l | tr -d ' ')
echo ""
echo "Done! ${FINAL_COUNT} HTML files in ${OUT}/"
echo "  - ${GENERATED} pages from sitemap + extras"
echo "  - 1 catch-all 404.html"
echo "  - CNAME → ${SOURCE}"
