#!/bin/sh
# Unit tests for the extract path of herdr-codex-session-title.py
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
py="$here/../scripts/herdr-codex-session-title.py"
fixture="$here/fixtures/session_index.jsonl"
fail=0

check() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    fail=1
  fi
}

check "simple title" "初始标题" \
  "$(python3 "$py" extract "$fixture" aaaa1111-0000-0000-0000-000000000001)"

check "renamed session keeps the LAST thread_name" "提取内容(改名后)" \
  "$(python3 "$py" extract "$fixture" bbbb2222-0000-0000-0000-000000000002)"

check "whitespace-only thread_name is ignored" "" \
  "$(python3 "$py" extract "$fixture" cccc3333-0000-0000-0000-000000000003 || true)"

check "control chars become spaces, runs collapsed" "带 控制 字符 的标题" \
  "$(python3 "$py" extract "$fixture" dddd4444-0000-0000-0000-000000000004)"

if python3 "$py" extract "$fixture" no-such-id >/dev/null 2>&1; then
  echo "FAIL: unknown session id should exit non-zero"
  fail=1
else
  echo "ok: unknown session id exits non-zero"
fi

if python3 "$py" extract /nonexistent/session_index.jsonl whatever >/dev/null 2>&1; then
  echo "FAIL: missing index file should exit non-zero"
  fail=1
else
  echo "ok: missing index file exits non-zero"
fi

exit $fail
