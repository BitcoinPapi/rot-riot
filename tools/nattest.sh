#!/bin/bash
# The co-op test over a PRETEND INTERNET: every copy of the game sits in its
# own "home" behind its own router, and a router lets nobody in from outside
# who was not spoken to first - like real home routers. This is how the way
# the game gets through routers (scripts/autoload/net.gd) is tested without
# real routers.
#
# Linux only, as root (it builds network namespaces). Needs iproute2,
# iptables and python3.
#
#   tools/nattest.sh              two players, the normal way: game code, reply code, LET IN
#   tools/nattest.sh 3            three players
#   tools/nattest.sh 2 noletin    nobody types the reply code in: the joiner must NOT get in
#                                 (proves that the pretend routers really keep strangers out)
#   tools/nattest.sh 2 open       the host's router has its door open (as when UPnP works, or a
#                                 port was forwarded by hand): the joiner gets in at the first knock
#   tools/nattest.sh 2 strict     the host's router gives every conversation a new door: the game
#                                 must notice and say so
#   GODOT=godot45 tools/nattest.sh 3
#
# The pretend internet is 203.0.113.0/24: two address finders at .1 and .9,
# the routers at .11, .12, .13. Home number i is 192.168.i.0/24, its computer
# 192.168.i.10.
G=${GODOT:-godot}
n=${1:-2}
mode=${2:-normal}
cd "$(dirname "$0")/.."
out=$(mktemp -d)
pids=""
seconds=95
[ "$mode" = noletin ] && seconds=22
[ "$mode" = strict ] && seconds=22

cleanup() {
  [ -n "$pids" ] && kill $pids 2>/dev/null
  for ns in $(ip netns list 2>/dev/null | awk '{print $1}' | grep '^rr_'); do
    ip netns pids "$ns" 2>/dev/null | xargs -r kill 2>/dev/null
    ip netns del "$ns" 2>/dev/null
  done
}
trap cleanup EXIT
cleanup

# --- the internet: one switch, two address finders ---
ip netns add rr_net
ip -n rr_net link set lo up
ip -n rr_net link add br0 type bridge
ip -n rr_net addr add 203.0.113.1/24 dev br0
ip -n rr_net addr add 203.0.113.9/24 dev br0
ip -n rr_net link set br0 up

# --- the homes: a router with a computer behind it ---
for i in $(seq 1 "$n"); do
  R=rr_router$i
  H=rr_home$i
  ip netns add $R
  ip netns add $H
  ip link add rr_w$i netns $R type veth peer name rr_b$i netns rr_net     # router <-> internet
  ip -n rr_net link set rr_b$i master br0
  ip -n rr_net link set rr_b$i up
  ip -n $R addr add 203.0.113.$((10 + i))/24 dev rr_w$i
  ip -n $R link set rr_w$i up
  ip link add rr_l$i netns $R type veth peer name eth0 netns $H           # router <-> the computer at home
  ip -n $R addr add 192.168.$i.1/24 dev rr_l$i
  ip -n $R link set rr_l$i up
  ip -n $R link set lo up
  ip -n $H addr add 192.168.$i.10/24 dev eth0
  ip -n $H link set eth0 up
  ip -n $H link set lo up
  ip -n $H route add default via 192.168.$i.1
  ip netns exec $R sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
  # What every home router does: everything from inside may go out and gets
  # the router's address; from outside only answers come in.
  ip netns exec $R iptables -P INPUT DROP
  ip netns exec $R iptables -P FORWARD DROP
  ip netns exec $R iptables -A FORWARD -i rr_l$i -o rr_w$i -j ACCEPT
  ip netns exec $R iptables -A FORWARD -i rr_w$i -o rr_l$i -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  if [ "$mode" = strict ] && [ "$i" = 1 ]; then
    ip netns exec $R iptables -t nat -A POSTROUTING -o rr_w$i -j MASQUERADE --random-fully
  else
    ip netns exec $R iptables -t nat -A POSTROUTING -o rr_w$i -j MASQUERADE
  fi
  if [ "$mode" = open ] && [ "$i" = 1 ]; then
    ip netns exec $R iptables -t nat -A PREROUTING -i rr_w$i -p udp --dport 24565 -j DNAT --to-destination 192.168.$i.10:24565
    ip netns exec $R iptables -A FORWARD -i rr_w$i -o rr_l$i -p udp --dport 24565 -j ACCEPT
  fi
done

ip netns exec rr_net python3 tools/nattest_stun.py 203.0.113.1 203.0.113.9 > "$out/finders.txt" 2>&1 &
pids="$pids $!"
sleep 0.5
finders=203.0.113.1:3478,203.0.113.9:3478

# --- the players ---
: > "$out/letin.txt"
ip netns exec rr_home1 $G --headless -d -- --coop=host --players=$n --cooptest --seconds=$seconds \
    --stun=$finders --letin-file="$out/letin.txt" > "$out/p0.txt" 2>&1 &
games=$!
code=""
for try in $(seq 1 60); do
  code=$(grep -m1 '^CODE ' "$out/p0.txt" 2>/dev/null | awk '{print $2}')
  [ -n "$code" ] && break
  sleep 0.25
done
echo "the host's game code: ${code:-NONE}"
for k in $(seq 1 $((n - 1))); do
  ip netns exec rr_home$((k + 1)) $G --headless -d -- --coop=join:$code --name=JOIN$k --cooptest --seconds=$seconds \
      --stun=$finders > "$out/p$k.txt" 2>&1 &
  games="$games $!"
  sleep 0.5
done
pids="$pids $games"

# The players pass the reply codes on: whatever a joiner's screen shows, the
# host types in (unless this run is about nobody doing that).
(
  while sleep 0.3; do
    for k in $(seq 1 $((n - 1))); do
      reply=$(grep -m1 '^REPLY ' "$out/p$k.txt" 2>/dev/null | awk '{print $2}')
      if [ -n "$reply" ] && [ "$mode" != noletin ] && ! grep -q "$reply" "$out/letin.txt"; then
        echo "$reply" >> "$out/letin.txt"
      fi
    done
  done
) &
pids="$pids $!"
wait $games

ok=1
for k in $(seq 0 $((n - 1))); do
  echo "--- player $k"
  grep -E "^CODE|^REPLY|^LET IN|^STRICT|FAIL|PASS|ERROR|WARNING|SCRIPT" "$out/p$k.txt" | cut -c1-230
done
case "$mode" in
  noletin)
    grep -q '^REPLY ' "$out/p1.txt" || { ok=0; echo "the joiner never got a reply code"; }
    grep -q 'COOPTEST start' "$out"/p*.txt && { ok=0; echo "a joiner got in although nobody let them in"; }
    [ $ok = 1 ] && echo "AS IT SHOULD BE: the router kept the joiner out until the host lets them in"
    ;;
  strict)
    grep -q '^STRICT' "$out/p0.txt" || { ok=0; echo "the game did not notice the strict router"; }
    [ $ok = 1 ] && echo "AS IT SHOULD BE: the game noticed the strict router"
    ;;
  *)
    for k in $(seq 0 $((n - 1))); do
      grep -q "COOPTEST PASSED" "$out/p$k.txt" || ok=0
    done
    for k in $(seq 1 $((n - 1))); do
      if ! diff <(grep "^SAME" "$out/p0.txt") <(grep "^SAME" "$out/p$k.txt") > /dev/null; then
        ok=0
        echo "PLAYER $k DISAGREES WITH THE HOST:"
        diff <(grep "^SAME" "$out/p0.txt") <(grep "^SAME" "$out/p$k.txt")
      fi
    done
    if [ "$mode" = open ] && grep -q '^LET IN' "$out/p0.txt"; then ok=0; echo "a reply code was needed although the door was open"; fi
    # While hosting, the game keeps its router's door in use (a small packet to an address finder now and then).
    keeps=$(grep -c '^asked by 203.0.113.11:24565' "$out/finders.txt")
    echo "the host's game used its door $keeps times to keep it open"
    [ "$keeps" -ge 5 ] || { ok=0; echo "...too few: the door would close while waiting for friends"; }
    [ $ok = 1 ] && echo "ALL COPIES AGREE - CO-OP THROUGH ROUTERS PASSED ($n players, $mode)"
    ;;
esac
if [ $ok != 1 ]; then echo "ROUTER TEST FAILED (full output in $out)"; exit 1; fi
