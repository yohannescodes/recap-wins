#!/bin/bash
# Generate changelog HTML for a release using recap-wins itself

set -e

# Get version from command line or use current tag
VERSION="${1:-$(git describe --tags --abbrev=0)}"
PREVIOUS="${2:-$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "HEAD")}"

echo "Generating changelog for $VERSION (from $PREVIOUS)"

# Ensure docs/changelogs directory exists
mkdir -p docs/changelogs

# Build recap-wins if needed
if [ ! -f .build/release/rw ]; then
    echo "Building recap-wins..."
    swift build -c release
fi

# Generate the changelog HTML
echo "Generating changelog HTML..."

# Get the change report
REPORT=$(.build/release/rw vitals --json --base "${PREVIOUS}" --head "${VERSION}")

# Extract key metrics
COMMITS=$(echo "$REPORT" | jq -r '.commits | length')
FILES=$(echo "$REPORT" | jq -r '.files | length')
ADDITIONS=$(echo "$REPORT" | jq -r '.vitals.insertions')
DELETIONS=$(echo "$REPORT" | jq -r '.vitals.deletions')

# Create a simple changelog HTML
cat > "docs/changelogs/${VERSION}.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Release ${VERSION}</title>
    <style>
        body {
            font-family: system-ui, -apple-system, sans-serif;
            max-width: 800px;
            margin: 40px auto;
            padding: 20px;
            line-height: 1.6;
        }
        h1 { font-size: 28px; margin-bottom: 8px; }
        .meta { color: #666; font-size: 14px; margin-bottom: 24px; }
        .stats {
            display: flex;
            gap: 24px;
            margin: 20px 0;
            padding: 16px;
            background: #f6f8fa;
            border-radius: 6px;
        }
        .stat { text-align: center; }
        .stat-value { font-size: 24px; font-weight: bold; color: #0969da; }
        .stat-label { font-size: 12px; color: #666; text-transform: uppercase; }
        .section { margin: 32px 0; }
        h2 { font-size: 20px; margin-bottom: 12px; }
        ul { padding-left: 24px; }
        li { margin: 8px 0; }
    </style>
</head>
<body>
    <h1>Release ${VERSION}</h1>
    <div class="meta">Changes from ${PREVIOUS} to ${VERSION}</div>

    <div class="stats">
        <div class="stat">
            <div class="stat-value">${COMMITS}</div>
            <div class="stat-label">Commits</div>
        </div>
        <div class="stat">
            <div class="stat-value">${FILES}</div>
            <div class="stat-label">Files Changed</div>
        </div>
        <div class="stat">
            <div class="stat-value">+${ADDITIONS}</div>
            <div class="stat-label">Additions</div>
        </div>
        <div class="stat">
            <div class="stat-value">-${DELETIONS}</div>
            <div class="stat-label">Deletions</div>
        </div>
    </div>

    <div class="section">
        <h2>What's New</h2>
        <p>See <a href="https://github.com/yohannescodes/recap-wins/blob/main/CHANGELOG.md#${VERSION//\.}">CHANGELOG.md</a> for detailed release notes.</p>
    </div>

    <div class="section">
        <p><a href="https://github.com/yohannescodes/recap-wins/releases/tag/${VERSION}">View release on GitHub →</a></p>
    </div>
</body>
</html>
EOF

echo "✅ Generated docs/changelogs/${VERSION}.html"
echo ""
echo "Next steps:"
echo "1. Review the generated changelog"
echo "2. Commit: git add docs/changelogs/${VERSION}.html && git commit -m 'docs: add ${VERSION} changelog'"
echo "3. Push to your PR branch"