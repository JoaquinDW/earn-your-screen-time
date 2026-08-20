#!/usr/bin/env bash
# Siembra un estado de billetera en el Simulador para poder desarrollar la UI sin
# cuenta Apple y sin caminar.
#
#   ./scripts/seed-simulator.sh [pasos] [segundos_consumidos] [idioma]
#   ./scripts/seed-simulator.sh 3842 360 es
#
# Ojo: hay que apagar el Simulador antes de escribir, porque cfprefsd cachea las
# preferencias en memoria y pisaría el archivo.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

STEPS=${1:-3842}
CONSUMED=${2:-360}
LANG_CODE=${3:-es}
BUNDLE_ID=com.balthasardeweert.earnyourscreentime
GROUP_ID=group.$BUNDLE_ID
DEVICE_NAME=${DEVICE_NAME:-iPhone 17 Pro}

SIM=$(xcrun simctl list devices available | grep -m1 "$DEVICE_NAME (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$SIM" ] || { echo "No encontré el simulador '$DEVICE_NAME'"; exit 1; }

xcrun simctl shutdown "$SIM" 2>/dev/null || true
sleep 2

PLIST=$(find ~/Library/Developer/CoreSimulator/Devices/"$SIM"/data/Containers/Shared/AppGroup \
  -name "$GROUP_ID.plist" 2>/dev/null | head -1)
[ -n "$PLIST" ] || { echo "Todavía no existe el App Group: corré la app una vez primero."; exit 1; }

python3 - "$PLIST" "$STEPS" "$CONSUMED" <<'PY'
import json, plistlib, sys, datetime
path, steps, consumed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rule = {"source": "steps", "amountRequired": 1000, "rewardSeconds": 300}
milestones = steps // rule["amountRequired"]
today = datetime.date.today()
state = {
    "schemaVersion": 1, "onboardingCompleted": True, "restrictedItemCount": 5,
    "shieldsApplied": milestones * rule["rewardSeconds"] - consumed <= 0,
    "ledger": {
        "day": {"year": today.year, "month": today.month, "day": today.day},
        "rule": rule, "activityAmount": steps, "baselineAmount": 0,
        "milestonesRewarded": milestones,
        "wallet": {"earnedSeconds": milestones * rule["rewardSeconds"], "consumedSeconds": consumed},
    },
}
plistlib.dump({"shared.state.v1": json.dumps(state).encode()}, open(path, "wb"))
earned = milestones * rule["rewardSeconds"]
print(f"{steps} pasos → ganado {earned//60} min, usado {consumed//60} min, disponible {max(0,earned-consumed)//60} min")
PY

xcrun simctl boot "$SIM"
sleep 6
xcrun simctl launch "$SIM" "$BUNDLE_ID" -AppleLanguages "($LANG_CODE)" >/dev/null
echo "App lanzada en '$LANG_CODE'."
