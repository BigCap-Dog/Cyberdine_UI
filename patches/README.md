# Backend Patches

Drop `.sh` files here to auto-apply backend patches during setup.

## Rules:
- Files run in alphabetical order (use `01_`, `02_` prefixes)
- Each patch gets `$FT_PACKAGE_DIR` and `$CS_UI_DIR` env vars
- Patches MUST be idempotent (safe to run multiple times)
- Always `grep -q` to check if already applied before modifying

## Example:
```bash
#!/usr/bin/env bash
set -euo pipefail
FILE="$FT_PACKAGE_DIR/rpc/api_server/api_trading.py"
if grep -q "my_endpoint" "$FILE"; then
    echo "Already patched."
else
    sed -i '/some_line/a\
@router.get("/my_endpoint")\
def my_endpoint():\
    return {"ok": True}\
' "$FILE"
fi
```
