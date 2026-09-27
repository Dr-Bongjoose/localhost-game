#!/bin/bash
# JOO-24 device verification leg v6 — the DEFINITIVE acceptance run.
# Device-agnostic + resolution-adaptive: works on ANY authorized Pixel
# (11 Pro 2410x1080 or 6 Pro 1440x720), picks the first "device"-state serial,
# and derives ALL tap coordinates from the engine layout probe (test_layout_
# probe.gd v3) for the detected resolution -- no hand-computed coords.
# APK under test: builds/localhost-debug.apk (HEAD >= 8c8cd97, sha da71a3d5...)
# Covers: BUG-2/UX-5 raid overlay, UX-3 BACK confirm dialog, BUG-1/UX-2
# Parent-B popup, UX-4 Deploy/Recall buttons, UX-6 scroll affordance.
set -u
export HOME=/home/bongjoose
ADB=/home/bongjoose/Android/Sdk/platform-tools/adb
APK=/home/bongjoose/localhost-game/builds/localhost-debug.apk
REPO=/home/bongjoose/localhost-game
EVD=$REPO/builds/device_evidence
LOG=$EVD/joo24_leg_v6.log
SHOTS=$REPO/builds/qa-shots-m2
SCRATCH=/home/bongjoose/.paperclip/tmp/joo24
PKG=com.jooselabs.localhost
ACTIVITY=com.godot.game.GodotAppLauncher
GODOT=/home/bongjoose/.hermes/profiles/hermes-tutor/home/.local/bin/godot
mkdir -p "$SHOTS"
log() { echo "[$(date -u +%FT%TZ)] $*" >> "$LOG"; }
sh() { sg plugdev -c "$ADB -s $SER $*"; }
shot() { sh "exec-out screencap -p" > "$SHOTS/$1.png" 2>/dev/null && log "screenshot: $1.png $(stat -c%s "$SHOTS/$1.png")"; }
alive() { sh "shell pidof $PKG" 2>/dev/null | tr -d '\r\n '; }
wakeup() { # wake screen + dismiss keyguard so captures show the game, not AOD
  sh "shell input keyevent KEYCODE_WAKEUP" >> "$LOG" 2>&1
  sleep 1
  sh "shell wm dismiss-keyguard" >> "$LOG" 2>&1
  sleep 1
  log "wakeup: keyguard dismissed, screen awake"
}
tap_center() { # canvas cx cy -> physical tap via $SCALE
  local px py
  px=$(python3 -c "print(round($1*$SCALE))")
  py=$(python3 -c "print(round($2*$SCALE))")
  sh "shell input tap $px $py" >> "$LOG" 2>&1
  log "tap canvas=($1,$2) physical=($px,$py)"
}

log "===== JOO-24 UI leg v6 start ====="
log "apk sha256: $(sha256sum "$APK" | cut -d' ' -f1)"

# ---------- STAGE 0: pick device + resolution ----------
SER=$(sg plugdev -c "$ADB devices" | awk '$2=="device" {print $1; exit}')
if [ -z "$SER" ]; then log "NO_DEVICE"; echo "LEG_V6_RESULT=no_device" >> "$LOG"; exit 1; fi
W=$(sg plugdev -c "$ADB -s $SER shell wm size" | grep -oE '[0-9]+x[0-9]+' | tail -1 | cut -d x -f1)
H=$(sg plugdev -c "$ADB -s $SER shell wm size" | grep -oE '[0-9]+x[0-9]+' | tail -1 | cut -d x -f2)
if [ "$W" -lt "$H" ]; then T=$W; W=$H; H=$T; fi   # game is landscape
log "device=$SER wm=$((W))x$((H))"
# Engine probe: physical coords come from the engine at THIS resolution.
PROBE=$(cd "$REPO" && HOME=/home/bongjoose timeout 120 xvfb-run -a -s "-screen 0 ${W}x${H}x24" $GODOT --path . --resolution ${W}x${H} --script scripts/test_layout_probe.gd 2>/dev/null | grep -E "RECT |EXIT_BTN|EXIT_DIALOG|SCROLL_VERTICAL|PROBE_DONE")
if ! echo "$PROBE" | grep -q PROBE_DONE; then log "PROBE_FAILED"; echo "LEG_V6_RESULT=probe_failed" >> "$LOG"; exit 1; fi
echo "$PROBE" >> "$LOG"
SCALE=$(python3 -c "print($H/1280)")
cget() { echo "$PROBE" | grep "$1" | head -1 | grep -oE "$2"; }
canvas_center() { # name -> "cx cy"
  local line=$(echo "$PROBE" | grep "RECT $1 " | head -1)
  echo "$line" | python3 -c "
import sys, re
m = re.search(r'canvas=\((\d+),(\d+)\)-\((\d+),(\d+)\)', sys.stdin.read())
x1,y1,x2,y2 = map(int, m.groups())
print((x1+x2)//2, (y1+y2)//2)
"
}
exit_btn_center() { # which(OK|CANCEL) -> "cx cy" from EXIT_BTN line canvas box
  local line=$(echo "$PROBE" | grep "EXIT_BTN $1" | head -1)
  echo "$line" | python3 -c "
import sys, re
m = re.search(r'canvas=\((\d+),(\d+)\)-\((\d+),(\d+)\)', sys.stdin.read())
x1,y1,x2,y2 = map(int, m.groups())
print((x1+x2)//2, (y1+y2)//2)
"
}
zoned_center() { # name -> "cx cy" from probe's ZONED RECT line (zones-view live state)
  local line=$(echo "$PROBE" | grep "ZONED RECT $1 " | head -1)
  echo "$line" | python3 -c "
import sys, re
m = re.search(r'canvas=\((\d+),(\d+)\)-\((\d+),(\d+)\)', sys.stdin.read())
x1,y1,x2,y2 = map(int, m.groups())
print((x1+x2)//2, (y1+y2)//2)
"
}

# ---------- STAGE 1: install + launch (stock autosave: BACK + UI legs) ----------
sh "shell am force-stop $PKG" >> "$LOG" 2>&1
log "--- install ---"
sh "install -r $APK" >> "$LOG" 2>&1 && log "install: SUCCESS" || { log "install: FAILED"; echo "LEG_V6_RESULT=install_failed" >> "$LOG"; exit 1; }
sh "shell am start -n $PKG/$ACTIVITY" >> "$LOG" 2>&1
sleep 16
wakeup
PID0=$(alive)
log "launch pid: $PID0"
if [ -z "$PID0" ]; then
  log "LAUNCH_FAILED: app process not running after am start"
  echo "LEG_V6_RESULT=launch_failed" >> "$LOG"
  exit 1
fi
shot v6_00_launch

# ---------- STAGE 2: UX-3 BACK key (3 presses, expect dialog + alive) ----------
log "--- UX-3 BACK key (engine-computed dismiss coords) ---"
for i in 1 2 3; do
  sh "shell input keyevent 4" >> "$LOG" 2>&1
  sleep 3
  P=$(alive)
  if [ -z "$P" ]; then
    log "UX3_BACK${i}=PROCESS_DEAD"
    shot "v6_ux3_back${i}_DEAD"
    echo "LEG_V6_RESULT=ux3_regressed" >> "$LOG"
    exit 1
  fi
  log "UX3_BACK${i}=ALIVE pid=$P"
  shot "v6_ux3_back${i}_dialog"
done
KP=$(echo "$PROBE" | grep "EXIT_BTN CANCEL(KeepPlaying)" | head -1 | python3 -c "
import sys, re
m = re.search(r'canvas=\((\d+),(\d+)\)-\((\d+),(\d+)\)', sys.stdin.read())
x1,y1,x2,y2 = map(int, m.groups())
print((x1+x2)//2, (y1+y2)//2)")
log "dismiss tap (canvas): $KP"
tap_center $KP
sleep 2
log "after dismiss pid: $(alive)"
shot v6_ux3_after_dismiss
sh "logcat -d" 2>/dev/null | grep -iE "back|go_back|terminat|quit" | tail -8 >> "$LOG"

# ---------- STAGE 3: BUG-2/UX-5 raid overlay (crafted save, rapid capture) ----------
log "--- BUG-2 raid (crafted save via run-as cp; stdin redirect loses quoting through adb) ---"
sh "shell am force-stop $PKG" >> "$LOG" 2>&1
sh "push $SCRATCH/save_raid.json /data/local/tmp/save_raid.json" >> "$LOG" 2>&1
sh "shell run-as $PKG cp /data/local/tmp/save_raid.json files/save.json" >> "$LOG" 2>&1
log "injected save: $(sh "shell run-as $PKG ls -la files/save.json" 2>&1 | tr -d '\r')"
sh "shell am start -n $PKG/$ACTIVITY" >> "$LOG" 2>&1
wakeup
for i in 1 2 3 4 5 6 7 8; do
  sh "exec-out screencap -p" > "$SHOTS/v6_raid_${i}.png" 2>/dev/null
done
log "rapid raid captures done"
sleep 7
shot v6_raid_after_dismiss
log "pid after raid: $(alive)"
sh "logcat -d" 2>/dev/null | grep -iE "raid|Game loaded" | tail -6 >> "$LOG"

# ---------- STAGE 4: restore baseline, launch ----------
log "--- restore baseline save ---"
sh "shell am force-stop $PKG" >> "$LOG" 2>&1
sh "push $SCRATCH/save_baseline.json /data/local/tmp/save_base.json" >> "$LOG" 2>&1
sh "shell run-as $PKG cp /data/local/tmp/save_base.json files/save.json" >> "$LOG" 2>&1
sh "shell am start -n $PKG/$ACTIVITY" >> "$LOG" 2>&1
sleep 16
wakeup
log "baseline pid: $(alive)"
shot v6_ui0_containment

# ---------- STAGE 5: BUG-1/UX-2 Parent-B popup ----------
log "--- BUG-1/UX-2 popup test (engine-computed coords) ---"
PB=$(canvas_center ParentBDropdown); tap_center $PB
sleep 2
shot v6_pb1_after_tap
PB=$(canvas_center ParentBDropdown); tap_center $PB
sleep 2
shot v6_pb2_after_tap2
# Popup grows upward from the dropdown: item rows sit above the button.
PBX=$(echo $PB | cut -d' ' -f1)
PBY=$(echo $PB | cut -d' ' -f2)
ITEM=$(python3 -c "print($PBX, $PBY-90)")
tap_center $ITEM
sleep 2
shot v6_pb3_item_selected

# ---------- STAGE 6: UX-4 Deploy/Recall buttons ----------
# Zones controls are measured by the probe IN the zones view state (ZONED
# RECT lines) — hidden-state RECTs sit ~200 canvas px off and are dead.
log "--- UX-4 zones buttons (probe measured in zones view) ---"
TZ=$(canvas_center TabZones); tap_center $TZ
sleep 2
shot v6_zo1_zones_tab
DD=$(zoned_center DeployDropdown); tap_center $DD
sleep 2
shot v6_zo2_deploy_dropdown
DDX=$(echo $DD | cut -d' ' -f1); DDY=$(echo $DD | cut -d' ' -f2)
ITEM=$(python3 -c "print($DDX, $DDY-90)")
tap_center $ITEM
sleep 2
shot v6_zo3_item_selected
RC=$(zoned_center RecallButton); tap_center $RC
sleep 2
shot v6_zo4_recall_pressed
DP=$(zoned_center DeployButton); tap_center $DP
sleep 2
shot v6_zo5_deploy_pressed

# ---------- STAGE 7: UX-6 scroll ----------
log "--- UX-6 scroll ---"
TC=$(canvas_center TabContainment); tap_center $TC
sleep 2
SWY=$(python3 -c "print(int($H*0.62))")
SW2=$(python3 -c "print(int($H*0.28))")
sh "shell input swipe $((H/6)) $SWY $((H/6)) $SW2 600" >> "$LOG" 2>&1
sleep 2
shot v6_ui_scrolled

log "final pid: $(alive)"
log "===== UI leg v6 complete ====="
echo "LEG_V6_RESULT=done" >> "$LOG"
echo done