#!/usr/bin/env bash
# Print the Google Services Framework (GSF) Android ID needed to register this uncertified device
# for the Play Store. Android must be running (waydroid show-full-ui) with working network.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"
need_root
waydroid status 2>/dev/null | grep -q "Session:.*RUNNING" || die "start Android first (as your desktop user): waydroid show-full-ui"
sh_in() { waydroid shell -- sh -c "$1" 2>/dev/null | tr -d '\r'; }
say "Waiting for Android network + Google check-in (up to 5 min)"
id=
for _ in $(seq 1 60); do
  id=$(sh_in "sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \"select value from main where name = 'android_id';\"")
  [ -n "$id" ] && break
  sleep 5
done
if [ -z "$id" ]; then
  sh_in "dumpsys connectivity | grep -q VALIDATED" && warn "network OK but no check-in yet — try again in a few minutes" ||
    warn "Android has no validated network (see docs/TROUBLESHOOTING.md → Networking)"
  die "no GSF Android ID yet"
fi
cat <<EOF

  ${C_B}GSF Android ID: $id${C_0}

  1. Open https://www.google.com/android/uncertified in any browser, signed in to a Google account.
  2. Paste the ID above and press Register.
  3. Wait (minutes to ~1 hour), restart Android (waydroid session stop; waydroid show-full-ui),
     then sign in to the Play Store.
  The ID stays the same until Waydroid's data is wiped; any Google account can sign in afterwards.
EOF
