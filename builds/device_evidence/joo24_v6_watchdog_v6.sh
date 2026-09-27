#!/bin/bash
# JOO-24 watchdog v6: waits for ANY authorized Pixel (24h window from now),
# then runs the resolution-adaptive v6 acceptance leg (APK da71a3d5, HEAD 8c8cd97).
# Restarted by run 2615aadb (2026-09-27 heartbeat): previous watchdog env carried
# run b1d29541's credentials, which died with that run (paperclip-api-ops pitfall 12).
# On completion (any outcome) posts the evidence comment on JOO-24 via the
# completion hook -> issue_commented wake -> Game Dev resumes automatically.
export HOME=/home/bongjoose
EVD=/home/bongjoose/localhost-game/builds/device_evidence
LOG=$EVD/joo24_v6_watchdog.log
HOOK=$EVD/joo24_v6_completion_hook.py
LEG=$EVD/joo24_leg_v6.sh
ADB=/home/bongjoose/Android/Sdk/platform-tools/adb

echo "[$(date -u +%FT%TZ)] watchdog v6 start (re-armed by run ${PAPERCLIP_RUN_ID:-unknown} with CURRENT run credentials)" >> "$LOG"

deadline=$((SECONDS + 86400))
while [ $SECONDS -lt $deadline ]; do
  SER=$(sg plugdev -c "$ADB devices" | awk '$2=="device" {print $1; exit}')
  if [ -n "$SER" ]; then break; fi
  if ! sg plugdev -c "$ADB devices" | grep -qE "device|unauthorized"; then
    $ADB kill-server >/dev/null 2>&1
    sg plugdev -c "$ADB start-server" >/dev/null 2>&1
  fi
  sleep 15
done
if [ -z "${SER:-}" ]; then
  echo "[$(date -u +%FT%TZ)] TIMEOUT: no authorized device in 24h" >> "$LOG"
  echo "V6_WATCHDOG_RESULT=timeout" >> "$LOG"
  python3 "$HOOK" timeout 2>>"$LOG" || echo "[$(date -u +%FT%TZ)] hook failed" >> "$LOG"
  exit 0
fi
echo "[$(date -u +%FT%TZ)] authorized device found: $SER" >> "$LOG"
sleep 5
state=$(sg plugdev -c "$ADB devices" | awk -v s=$SER '$1==s {print $2}')
if [ "$state" != "device" ]; then
  echo "[$(date -u +%FT%TZ)] device dropped; grace re-loop 10min" >> "$LOG"
  d2=$((SECONDS + 600))
  while [ $SECONDS -lt $d2 ]; do
    state=$(sg plugdev -c "$ADB devices" | awk -v s=$SER '$1==s {print $2}')
    [ "$state" = "device" ] && break
    sleep 10
  done
fi
if [ "$state" != "device" ]; then
  echo "[$(date -u +%FT%TZ)] device never stabilized; aborting leg" >> "$LOG"
  echo "V6_WATCHDOG_RESULT=unstable_device" >> "$LOG"
  python3 "$HOOK" unstable_device 2>>"$LOG" || echo "[$(date -u +%FT%TZ)] hook failed" >> "$LOG"
  exit 0
fi
echo "[$(date -u +%FT%TZ)] running v6 acceptance leg on $SER" >> "$LOG"
bash "$LEG" "$SER" >> "$LOG" 2>&1
echo "[$(date -u +%FT%TZ)] leg exit=$?" >> "$LOG"
echo "V6_WATCHDOG_RESULT=leg_complete" >> "$LOG"
python3 "$HOOK" leg_complete 2>>"$LOG" || echo "[$(date -u +%FT%TZ)] hook failed" >> "$LOG"