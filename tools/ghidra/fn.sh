#!/usr/bin/env bash
# Looks up the exe's decompiled C (the DumpDecompiled.java dumps: assets/ghidra_v11/iafjets.c = v1.1, the
# reference; assets/ghidra/iafjets.c = v1.0).
#   tools/ghidra/fn.sh [--v10] 5643a0            one function's body (FUN_005643a0; also takes FUN_005643a0)
#   tools/ghidra/fn.sh [--v10] --grep PATTERN     the functions whose body matches PATTERN (awk regex)
set -euo pipefail
cd "$(dirname "$0")/../.."
c=assets/ghidra_v11/iafjets.c
[[ ${1:-} == --v10 ]] && { c=assets/ghidra/iafjets.c; shift; }
if [[ ${1:-} == --grep ]]; then
	awk -v pat="$2" '/^\/\/ ==== /{fn=$3} $0 ~ pat && !(fn in seen) {seen[fn]=1; print fn}' "$c"
	exit
fi
a=${1:?usage: fn.sh [--v10] <address|FUN_name> | --grep PATTERN}
a=${a#FUN_}; a=${a#0x}
a=$(printf "%08x" "0x$a")
awk -v s="// ==== FUN_$a @" 'index($0, s) == 1 {p = 1; print; next} p && /^\/\/ ==== /{exit} p' "$c"
