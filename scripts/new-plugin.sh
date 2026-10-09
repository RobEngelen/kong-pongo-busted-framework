#!/usr/bin/env bash
#
# Creates a new plugin (code, specs and rockspec), copied from the
# example-header plugin, ready to run with Pongo.
#
#   scripts/new-plugin.sh <name>              add it to this workspace
#   scripts/new-plugin.sh <name> --dir PATH   create a standalone plugin project in PATH
#
# Plugins added to this workspace are ignored by git (see .gitignore), so your
# own code is never committed to this shared repo by accident.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="example-header"

usage() { sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "error: $*" >&2; exit 2; }

NAME=""
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --dir) [ $# -ge 2 ] || die "--dir needs a path"; TARGET="$2"; shift ;;
    -*) die "unknown option $1 (use --help)" ;;
    *) [ -z "$NAME" ] || die "only one plugin name expected"; NAME="$1" ;;
  esac
  shift
done

[ -n "$NAME" ] || { usage; exit 2; }
echo "$NAME" | grep -Eq '^[a-z][a-z0-9-]*[a-z0-9]$' \
  || die "invalid name '$NAME': use lowercase letters, digits and dashes, e.g. custom-my-plugin"

STANDALONE=false
if [ -n "$TARGET" ]; then
  STANDALONE=true
  if [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
    die "$TARGET already exists and is not empty"
  fi
  mkdir -p "$TARGET" || die "could not create $TARGET"
  TARGET="$(cd "$TARGET" && pwd)"
else
  TARGET="$REPO_ROOT"
fi

[ -e "$TARGET/kong/plugins/$NAME" ] && die "plugin '$NAME' already exists in $TARGET"

case "$NAME" in
  custom-*) ;;
  *) echo "tip: a prefix like 'custom-' avoids name clashes with Kong's bundled plugins" ;;
esac

# custom-my-plugin -> CustomMyPlugin (for the handler table name)
CAMEL="$(echo "$NAME" | awk -F- '{ for (i = 1; i <= NF; i++) printf "%s", toupper(substr($i, 1, 1)) substr($i, 2) }')"
ROCKSPEC="kong-plugin-$NAME-0.1.0-1.rockspec"

# --- copy the template plugin ------------------------------------------------
mkdir -p "$TARGET/kong/plugins/$NAME" "$TARGET/spec/$NAME"
cp "$REPO_ROOT/kong/plugins/$TEMPLATE/"*.lua "$TARGET/kong/plugins/$NAME/"
cp "$REPO_ROOT/spec/$TEMPLATE/"*_spec.lua "$TARGET/spec/$NAME/"
cp "$REPO_ROOT/kong-plugin-$TEMPLATE-0.1.0-1.rockspec" "$TARGET/$ROCKSPEC"

for f in "$TARGET/kong/plugins/$NAME/"*.lua "$TARGET/spec/$NAME/"*_spec.lua "$TARGET/$ROCKSPEC"; do
  sed -i.bak \
    -e "s/ExampleHeaderHandler/${CAMEL}Handler/g" \
    -e "s/$TEMPLATE/$NAME/g" \
    -e "s|url = \"git+https://github.com/RobEngelen/kong-pongo-busted-framework.git\",|url = \"git+https://example.com/your-org/$NAME.git\",  -- TODO: your repository|" \
    -e "s|^  summary = .*|  summary = \"TODO: describe what $NAME does.\",|" \
    "$f" && rm -f "$f.bak"
done

# --- standalone project: add the Pongo/busted/luacheck configuration ----------
if [ "$STANDALONE" = true ]; then
  for f in .busted .luacheckrc .luacov .editorconfig .gitattributes; do
    cp "$REPO_ROOT/$f" "$TARGET/$f"
  done
  mkdir -p "$TARGET/.pongo"
  printf -- '--postgres\n' > "$TARGET/.pongo/pongorc"
  cat > "$TARGET/.gitignore" <<'EOF'
servroot*/
luacov.stats.out
luacov.report.out
luacov.report.html
junit*.xml
*.rock
.containerid
.pongo/.bash_history
.pongo/.ash_history
*license*.json
*.lic
EOF
fi

# --- done ---------------------------------------------------------------------
echo "Created plugin '$NAME' in $TARGET:"
echo "  kong/plugins/$NAME/handler.lua   request/response logic"
echo "  kong/plugins/$NAME/schema.lua    configuration"
echo "  spec/$NAME/                      schema, unit and integration tests"
echo "  $ROCKSPEC"
echo
echo "Run its tests:"
if [ "$STANDALONE" = true ]; then
  echo "  cd \"$TARGET\" && pongo run"
  echo "  (or from this repo: scripts/test-plugin.sh \"$TARGET\")"
else
  echo "  pongo run ./spec/$NAME"
fi
