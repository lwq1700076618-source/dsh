#!/data/data/com.termux/files/usr/bin/bash
# DSH 手机执行器 v7：签名校验 + 只用 Termux 的 curl（不污染系统二进制）
T="<YOUR_NTFY_TOPIC>"
BASE="https://ntfy.sh"
KEY="<YOUR_HMAC_KEY>"
export PREFIX=/data/data/com.termux/files/usr
LOG="$HOME/dsh-agent.log"
# 注意：这里故意不设置 LD_LIBRARY_PATH —— 否则 screencap 等系统程序会加载
# Termux 的同名库而崩掉。只在调用 Termux 的 curl 时临时加。
curl_t() { env LD_LIBRARY_PATH="$PREFIX/lib" "$PREFIX/bin/curl" "$@"; }

# 单实例锁
LOCK="$HOME/dsh-agent.lock"
if [ -f "$LOCK" ]; then
  OLD=$(cat "$LOCK" 2>/dev/null)
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    echo "[dsh-agent] 已有实例在跑（PID $OLD），本实例退出"
    exit 0
  fi
fi
echo $$ > "$LOCK"

echo "[dsh-agent] $(date '+%F %T') 已启动，等待指令…" | tee -a "$LOG"

getv() { printf '%s' "$MSG" | sed -n "s/.*\"$1\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p"; }

while true; do
  curl_t -s --no-buffer "$BASE/$T-cmd/json" 2>/dev/null | while IFS= read -r line; do
    case "$line" in *'"event":"message"'*) ;; *) continue;; esac
    RAW=$(printf '%s' "$line" | sed -n 's/.*"message":"\(.*\)"}$/\1/p')
    MSG=$(printf '%s' "$RAW" | sed 's/\\"/"/g')
    P=$(getv p)
    SIG=$(getv sig)
    [ -n "$P" ] && [ -n "$SIG" ] || continue
    EXPECT=$(printf '%s' "$P$KEY" | sha256sum | cut -d' ' -f1)
    if [ "$SIG" != "$EXPECT" ]; then
      echo "[dsh-agent] $(date '+%T') 签名不匹配，丢弃" >> "$LOG"
      continue
    fi
    MSG=$(printf '%s' "$P" | base64 -d 2>/dev/null)
    ID=$(getv id)
    TOOL=$(getv tool)
    TS=$(getv ts)
    NOW=$(date +%s)
    if [ -n "$TS" ] && [ $((NOW - TS)) -gt 300 ]; then
      curl_t -s -m 10 -d "$ID|EXPIRED" "$BASE/$T-res" >/dev/null 2>&1
      continue
    fi
    OUT=""
    case "$TOOL" in
      alarm)
        H=$(getv hour); M=$(getv minute); L=$(getv label)
        timeout 8 am start -a android.intent.action.SET_ALARM \
          --ei android.intent.extra.alarm.HOUR "$H" \
          --ei android.intent.extra.alarm.MINUTES "$M" \
          --es android.intent.extra.alarm.MESSAGE "${L:-闹钟}" \
          --ez android.intent.extra.alarm.SKIP_UI true </dev/null >/dev/null 2>&1 \
          && OUT="OK 已设闹钟 $H:$M ${L}" || OUT="FAIL alarm";;
      nav)
        Q=$(getv q); QE=$(getv q_enc)
        [ -n "$QE" ] || QE="$Q"
        if timeout 8 am start -a android.intent.action.VIEW \
             -d "baidumap://map/direction?destination=$QE&mode=driving&src=andr.dsh.agent" \
             </dev/null >/dev/null 2>&1
        then OUT="OK 百度地图导航：$Q"
        elif timeout 8 am start -a android.intent.action.VIEW -d "geo:0,0?q=$Q" </dev/null >/dev/null 2>&1
        then OUT="OK 已打开导航（系统选择）：$Q"
        else OUT="FAIL nav"; fi;;
      open)
        P2=$(getv pkg)
        C=$(cmd package resolve-activity --brief "$P2" 2>/dev/null | tail -n 1)
        if [ -n "$C" ] && timeout 8 am start -n "$C" </dev/null >/dev/null 2>&1
        then OUT="OK 已打开 $P2"
        elif timeout 8 monkey -p "$P2" -c android.intent.category.LAUNCHER 1 </dev/null >/dev/null 2>&1
        then OUT="OK 已打开 $P2 (monkey)"
        else OUT="FAIL open $P2"; fi;;
      tap)
        X=$(getv x); Y=$(getv y)
        timeout 8 input tap "$X" "$Y" </dev/null >/dev/null 2>&1 && OUT="OK 点击 $X,$Y" || OUT="FAIL tap";;
      text)
        S=$(getv s)
        timeout 8 input text "$S" </dev/null >/dev/null 2>&1 && OUT="OK 已输入" || OUT="FAIL text";;
      key)
        K=$(getv k)
        timeout 8 input keyevent "$K" </dev/null >/dev/null 2>&1 && OUT="OK 按键 $K" || OUT="FAIL key";;
      shot)
        F="$HOME/dsh-shot.png"
        rm -f "$F"
        # 必须用干净环境：Termux 的环境会让 system 的 screencap 链接到错误的库
        timeout 10 env -i /system/bin/screencap -p "$F" </dev/null >/dev/null 2>&1
        if [ -s "$F" ]; then          curl_t -s -T "$F" -H "Filename: dsh-shot.png" -H "Message: $ID|shot" "$BASE/$T-res" >/dev/null 2>&1
          OUT="OK 截图已回传"
        else OUT="FAIL shot"; fi;;
      shell)
        C=$(getv cmd); OUT=$(timeout 15 sh -c "$C" 2>&1 </dev/null | head -c 1500);;
      shell_b64)
        C=$(getv cmd_b64); C=$(printf '%s' "$C" | base64 -d 2>/dev/null); OUT=$(timeout 15 sh -c "$C" 2>&1 </dev/null | head -c 1500);;
      root)
        C=$(getv cmd)
        if [ "$(id -u)" = "0" ]; then OUT=$(timeout 15 sh -c "$C" 2>&1 </dev/null | head -c 1500); else OUT=$(timeout 15 su -c "$C" 2>&1 </dev/null | head -c 1500); fi;;
      root_b64)
        C=$(getv cmd_b64); C=$(printf '%s' "$C" | base64 -d 2>/dev/null)
        if [ "$(id -u)" = "0" ]; then OUT=$(timeout 15 sh -c "$C" 2>&1 </dev/null | head -c 1500); else OUT=$(timeout 15 su -c "$C" 2>&1 </dev/null | head -c 1500); fi;;
      ui_dump)
        U=/data/local/tmp/dsh-ui.xml
        rm -f "$U"
        timeout 20 su -Z u:r:shell:s0 2000 -c "/system/bin/uiautomator dump --compressed $U" >/dev/null 2>&1
        if [ -s "$U" ]; then
          curl_t -s -T "$U" -H "Filename: ui.xml" -H "Message: $ID|ui" "$BASE/$T-res" >/dev/null 2>&1
          OUT="OK 界面已回传"
        else OUT="FAIL ui_dump"; fi;;
      ping)
        OUT="pong $(date +%H:%M:%S)";;
      notify)
        OUT=$(/system/bin/dumpsys notification --noredact 2>/dev/null | grep -E 'android\.title=|android\.text=' | sed 's/^ *//' | head -40 | tr '\n' ';');;
      bright)
        V=$(getv v)
        if [ -n "$V" ]; then
          /system/bin/settings put system screen_brightness "$V" >/dev/null 2>&1 && OUT="OK 亮度已设为 $V" || OUT="FAIL bright"
        else OUT="当前亮度=$(/system/bin/settings get system screen_brightness 2>/dev/null)"; fi;;
      wifi)
        S=$(getv state); [ "$S" = "off" ] && S=disable || S=enable
        /system/bin/svc wifi "$S" 2>/dev/null && OUT="OK wifi $S" || OUT="FAIL wifi";;
      bt)
        S=$(getv state); [ "$S" = "off" ] && S=disable || S=enable
        /system/bin/svc bluetooth "$S" 2>/dev/null && OUT="OK bt $S" || OUT="FAIL bt";;
      dnd)
        S=$(getv state); [ "$S" = "off" ] && V=0 || V=1
        /system/bin/settings put global zen_mode "$V" >/dev/null 2>&1 && OUT="OK 勿扰=$V" || OUT="FAIL dnd";;
      airplane)
        S=$(getv state); [ "$S" = "off" ] && V=0 || V=1
        /system/bin/settings put global airplane_mode_on "$V" >/dev/null 2>&1
        /system/bin/am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null 2>&1
        OUT="OK 飞行模式=$V";;
      swipe)
        X1=$(getv x1); Y1=$(getv y1); X2=$(getv x2); Y2=$(getv y2); D=$(getv ms)
        OUT="FAIL swipe"
        for _try in 1 2; do
          if timeout 8 input swipe "$X1" "$Y1" "$X2" "$Y2" "${D:-300}" </dev/null >/dev/null 2>&1; then
            OUT="OK swipe $X1,$Y1 -> $X2,$Y2"; break
          fi
          sleep 0.4
        done;;
      back)
        timeout 5 input keyevent 4 </dev/null >/dev/null 2>&1 && OUT="OK back" || OUT="FAIL back";;
      home)
        timeout 5 input keyevent 3 </dev/null >/dev/null 2>&1 && OUT="OK home" || OUT="FAIL home";;
      recents)
        timeout 5 input keyevent 187 </dev/null >/dev/null 2>&1 && OUT="OK recents" || OUT="FAIL recents";;
      camera)
        timeout 8 am start -a android.media.action.STILL_IMAGE_CAMERA </dev/null >/dev/null 2>&1 && OUT="OK 已打开相机" || OUT="FAIL camera";;
      call)
        N=$(getv number)
        timeout 8 am start -a android.intent.action.CALL -d "tel:$N" </dev/null >/dev/null 2>&1 && OUT="OK 拨号 $N" || OUT="FAIL call";;
      *)
        OUT="UNKNOWN tool: $TOOL";;
    esac
    curl_t -s -m 10 -d "$ID|$OUT" "$BASE/$T-res" >/dev/null 2>&1
    echo "[dsh-agent] $(date '+%T') $TOOL -> ${OUT:0:60}" >> "$LOG"
  done
  sleep 2
done
