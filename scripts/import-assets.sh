#!/bin/bash
# Copies the textures and sounds the app uses into App/Resources.
# Modern assets come from the lolPing reference checkout, classic ones from reference/classic-12.21.
# Sounds are converted to AAC .m4a, all 44.1 kHz stereo so one AVAudioEngine format plays them all.
set -euo pipefail
cd "$(dirname "$0")/.."
LOLPING="${LOLPING:-$HOME/sandbox/lolping-fork/assets}"
CLASSIC=reference/classic-12.21/world
# The assets are already committed; this is only needed to re-import. Check before deleting anything.
if [ ! -d "$LOLPING" ]; then
  echo "lolPing assets not found at $LOLPING" >&2
  echo "Clone https://github.com/darrenprx/lolPing and run with LOLPING=<clone>/assets" >&2
  exit 1
fi
TEX=App/Resources/Textures
SND=App/Resources/Sounds
rm -rf "$TEX" "$SND"
mkdir -p "$TEX" "$SND"

TEXTURES=(contextwheel_atlas
  pingwheel_retreatrender push pingwheel_pushrender omw all_in pingwheel_allin_render_01 pingwheel_allin_render_02
  assist_me need_vision enemy_missing enemy_vision pingwheel_enemyvisionrender generic_ping pingwheel_basicpingrender
  pingwheel_baitrender vision_cleared pingwheel_visionclearedrender
  ping-danger ping-danger-base ping-omw_02 ping-omw-base ping-comehere_02 ping-comehere-base
  ping-mia_02 ping-mia-base ping-mia-base-outer sr_pings_blue_02 ping-command-base)
for t in "${TEXTURES[@]}"; do
  if [ -f "$CLASSIC/$t.png" ]; then cp "$CLASSIC/$t.png" "$TEX/"; else cp "$LOLPING/textures/$t.png" "$TEX/"; fi
done

SOUNDS=(SRP_12 SRP_9 OnMyWay SRP_4 ComeHere SRP_7 MIA AreaIsWarded Base SRP_11 SRP_6 GetBack button)
for s in "${SOUNDS[@]}"; do
  afconvert -f m4af -d aac@44100 -c 2 -b 128000 "$LOLPING/sounds/$s.wav" "$SND/$s.m4a"
done
echo "textures: $(ls "$TEX" | wc -l | tr -d ' ')  sounds: $(ls "$SND" | wc -l | tr -d ' ')"
du -sh "$TEX" "$SND"
