#!/bin/bash
# The co-op test: starts 2 or 3 copies of the game on this computer (one hosts,
# the others join it), lets each play through the scripted co-op session and
# compares the numbers all copies must agree on.
#
#   tools/cooptest.sh        two players
#   tools/cooptest.sh 3      three players
#   GODOT=godot45 tools/cooptest.sh 3     with another Godot build
#
# Every copy must print COOPTEST PASSED, and the last line must say ALL COPIES AGREE.
G=${GODOT:-godot}
n=${1:-2}
cd "$(dirname "$0")/.."
out=$(mktemp -d)
$G --headless -d -- --coop=host --players=$n --cooptest --seconds=70 > "$out/p0.txt" 2>&1 &
pids=$!
sleep 0.6
for k in $(seq 1 $((n-1))); do
  $G --headless -d -- --coop=join --name=JOIN$k --cooptest --seconds=70 > "$out/p$k.txt" 2>&1 &
  pids="$pids $!"
  sleep 0.5
done
wait $pids
ok=1
for k in $(seq 0 $((n-1))); do
  echo "--- player $k"
  grep -E "FAIL|PASS|ERROR|WARNING|SCRIPT" "$out/p$k.txt" | cut -c1-230
  grep -q "COOPTEST PASSED" "$out/p$k.txt" || ok=0
done
for k in $(seq 1 $((n-1))); do
  if ! diff <(grep "^SAME" "$out/p0.txt") <(grep "^SAME" "$out/p$k.txt") > /dev/null; then
    ok=0
    echo "PLAYER $k DISAGREES WITH THE HOST:"
    diff <(grep "^SAME" "$out/p0.txt") <(grep "^SAME" "$out/p$k.txt")
  fi
done
if [ $ok = 1 ]; then echo "ALL COPIES AGREE - CO-OP TEST PASSED ($n players)"; else echo "CO-OP TEST FAILED (full output in $out)"; exit 1; fi
