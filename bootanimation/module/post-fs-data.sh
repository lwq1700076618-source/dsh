#!/system/bin/sh
# 开机动画替换：后台重试挂载，绝不阻塞开机
MODDIR=${0%/*}
SRC="$MODDIR/bootanimation.zip"
LOG=/data/local/tmp/bootanim.log
echo "[$(date)] start src=$SRC" >> "$LOG"
[ -f "$SRC" ] || { echo "src missing" >> "$LOG"; exit 0; }

(
  T1=/my_product/media/bootanimation/bootanimation.zip
  T2=/mnt/vendor/my_product/media/bootanimation/bootanimation.zip
  i=0
  ok=no
  while [ $i -lt 60 ]; do
    for T in "$T1" "$T2"; do
      if mount --bind "$SRC" "$T" 2>>"$LOG"; then
        echo "[$(date)] mounted -> $T" >> "$LOG"
        ok=yes
        break
      fi
    done
    [ "$ok" = yes ] && break
    sleep 1
    i=$((i + 1))
  done
  echo "[$(date)] result=$ok tries=$i" >> "$LOG"
  ls -l "$T1" >> "$LOG" 2>&1
) &
exit 0
