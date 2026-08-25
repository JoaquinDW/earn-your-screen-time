#!/usr/bin/env bash
# Siembra un estado de billetera en el Simulador para poder desarrollar la UI sin
# cuenta Apple y sin caminar.
#
#   ./scripts/seed-simulator.sh [pasos] [segundos_consumidos] [idioma] [onboarding]
#   ./scripts/seed-simulator.sh 3842 360 es          # home, con una semana de historial
#   ./scripts/seed-simulator.sh 3842 360 es 0        # arranca en el onboarding
#
# Ojo: hay que apagar el Simulador antes de escribir, porque cfprefsd cachea las
# preferencias en memoria y pisaría el archivo.
set -euo pipefail

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

STEPS=${1:-3842}
CONSUMED=${2:-360}
LANG_CODE=${3:-es}
ONBOARDED=${4:-1}
BUNDLE_ID=com.balthasardeweert.earnyourscreentime
GROUP_ID=group.$BUNDLE_ID
DEVICE_NAME=${DEVICE_NAME:-iPhone 17 Pro}

SIM=$(xcrun simctl list devices available | grep -m1 "$DEVICE_NAME (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$SIM" ] || { echo "No encontré el simulador '$DEVICE_NAME'"; exit 1; }

xcrun simctl shutdown "$SIM" 2>/dev/null || true
sleep 2

# Según la versión de Xcode las preferencias del App Group aparecen en más de un lugar
# (data/Library/Preferences y el contenedor de la app). Escribimos en todas las copias.
PLISTS=$(find ~/Library/Developer/CoreSimulator/Devices/"$SIM"/data \
  -name "$GROUP_ID.plist" 2>/dev/null)
[ -n "$PLISTS" ] || { echo "Todavía no existe el App Group: corré la app una vez primero."; exit 1; }

python3 - "$STEPS" "$CONSUMED" "$ONBOARDED" "$LANG_CODE" $PLISTS <<'PY'
import json, plistlib, sys, datetime, random
steps, consumed = int(sys.argv[1]), int(sys.argv[2])
onboarded = sys.argv[3] != "0"
language = {"en": "english", "es": "spanish"}.get(sys.argv[4], "system")
paths = sys.argv[5:]
rule = {"source": "steps", "amountRequired": 500, "rewardSeconds": 300}
milestones = steps // rule["amountRequired"]
today = datetime.date.today()

def key(d):
    return {"year": d.year, "month": d.month, "day": d.day}

# Seis días previos con racha, para poder ver "Esta semana" y el contador de racha.
random.seed(steps)
history = []
for back in range(6, 0, -1):
    d = today - datetime.timedelta(days=back)
    day_steps = random.randrange(2500, 9000, 100)
    history.append({
        "day": key(d),
        "activityAmount": day_steps,
        "earnedSeconds": (day_steps // rule["amountRequired"]) * rule["rewardSeconds"],
    })

state = {
    "schemaVersion": 5, "onboardingCompleted": onboarded, "restrictedItemCount": 5,
    "hasEarnedFirstReward": onboarded, "adaptiveIntroSeen": onboarded,
    "shieldsApplied": True, "currentSession": None,
    "onboarding": {
        "desiredOutcomes": ["walkMore", "scrollLess", "feelInControl"],
        "scrolling": "twoToFourHours", "movement": "threeToFiveThousand",
        "recommendedDailyStepGoal": 4000, "baselineDailySteps": 3500,
        "baselineSource": "healthKit", "primaryGoal": "moveMore",
    },
    "journey": ({
        "startDay": key(today), "dailyGoal": 4000, "target": 120000,
        "cumulativeSteps": 0, "earnedSeconds": 0, "activeDays": 0,
        "goalHitDays": 0, "completionAcknowledged": False, "incorporatedDays": [],
    } if onboarded else None),
    "history": {"days": history},
    "ledger": {
        "day": key(today),
        "rule": rule, "activityAmount": steps, "baselineAmount": 0,
        "milestonesRewarded": milestones,
        "wallet": {"earnedSeconds": milestones * rule["rewardSeconds"], "consumedSeconds": consumed},
        "dailyGoal": 4000, "goalBonusSeconds": 600,
        "goalBonusAwarded": steps >= 4000, "transactions": [],
    },
}
for path in paths:
    plistlib.dump({
        "shared.state.v1": json.dumps(state).encode(),
        "app.language.preference.v1": language,
    }, open(path, "wb"))
earned = milestones * rule["rewardSeconds"]
print(f"{steps} pasos → ganado {earned//60} min, reservado {consumed//60} min, disponible {max(0,earned-consumed)//60} min")
print("onboarding: " + ("completado" if onboarded else "sin hacer"))
PY

xcrun simctl boot "$SIM"
sleep 6
xcrun simctl launch "$SIM" "$BUNDLE_ID" -AppleLanguages "($LANG_CODE)" >/dev/null
echo "App lanzada en '$LANG_CODE'."
