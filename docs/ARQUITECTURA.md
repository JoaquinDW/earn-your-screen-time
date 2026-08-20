# Arquitectura

## El problema central

Apple **no le da a tu app** el uso exacto de otras apps. No existe una API que devuelva
"TikTok = 4 minutos hoy". `DeviceActivityReport` muestra esos datos dentro de una vista sandboxeada
cuyo contenido no puede salir de la extensión que la dibuja.

Lo único que Apple sí ofrece: **avisarte cuando el uso acumulado de un conjunto de apps cruza un
umbral que vos definiste** (`DeviceActivityEvent` + `DeviceActivityMonitorExtension`).

Todo el diseño sale de ahí.

## Cómo medimos el consumo

Un solo `DeviceActivitySchedule` diario (00:00 → 23:59, `repeats: true`) y eventos cuyo umbral es
**uso acumulado desde la medianoche**, todos con `includesPastActivity: true`.

```
umbral del último evento  =  minutos TOTALES ganados hoy
se aplica el shield        cuando  uso acumulado hoy ≥ total ganado hoy
saldo disponible           =  ganado hoy − uso acumulado hoy
```

### Por qué acumulado desde medianoche y no "desde que ganó los minutos"

Cada vez que el usuario gana créditos hay que **reiniciar el monitoreo** para registrar el umbral
nuevo. Reiniciar borra los contadores relativos. Si los umbrales fueran "10 minutos desde ahora",
cada reinicio regalaría minutos.

Con umbrales acumulados desde la medianoche, más `includesPastActivity: true`, reiniciar es
inofensivo: el sistema vuelve a contar desde el mismo origen y los umbrales siguen significando lo
mismo. Los eventos ya cruzados se re-disparan, y como el manejador hace
`consumido = max(consumido, minuto × 60)`, re-procesarlos no cambia nada.

Esto es lo que hace `MonitorPlan.thresholds(totalEarnedSeconds:)`, y está cubierto por tests
(`MonitorPlanTests`): al aumentar el saldo, los umbrales viejos siguen presentes con el mismo valor.

### Ticks intermedios

Además del evento final se registran umbrales intermedios (`tick_1`, `tick_2`, …) para que el saldo
que se ve en pantalla se mantenga más o menos al día. Son cosméticos: el que importa es el último.
El total de eventos se limita a 20 por actividad (`MonitorPlan.defaultMaxEvents`); con saldos
grandes la granularidad se agranda automáticamente.

### Cumple el requisito del PRD

El tiempo se descuenta **solo cuando el usuario usa las apps restringidas**. Si bloquea el teléfono
30 minutos, el uso acumulado no se mueve y el saldo queda intacto. No hay ninguna cuenta regresiva
de reloj.

## Dónde vive el estado

| Capa | Qué guarda | Quién la usa |
|---|---|---|
| `UserDefaults` del App Group (`SharedStore`) | estado vivo: ganado, consumido, regla, día | la app **y** las extensiones |
| `FamilyActivitySelection` codificada (`SelectionStore`) | los tokens opacos de las apps elegidas | la app y las extensiones |
| SwiftData *(Fase 5)* | ajustes e historial diario | solo la app |

`DeviceActivityMonitorExtension` corre con un presupuesto de memoria muy chico y se muere si se
pasa. Por eso lee y escribe `UserDefaults`, no una base de datos.

### Concurrencia

La app y la extensión casi nunca están vivas a la vez. El único campo que escribe la extensión
(`consumedSeconds`) **solo avanza**, así que una escritura perdida se corrige sola en el evento
siguiente en vez de corromper el saldo.

## Capas

```
EarnDomain (paquete Swift)     lógica pura, sin frameworks de Apple, testeable en la Mac
        ↑
Shared/                        App Group, shields, scheduler, RestrictionCoordinator
        ↑                      (compilado dentro de la app Y de las extensiones)
App/ y Extensions/             UI y callbacks del sistema
```

`RestrictionCoordinator` es el **único** lugar que decide BLOQUEADO vs DISPONIBLE. Tanto la app
como la extensión pasan por él, así la regla no puede divergir entre los dos.

`ScreenTimeServing` es un protocolo con implementación real y mock: en el Simulador se usa el mock
(donde Screen Time no existe), en el iPhone la real.

## Reglas de ganancia y cambios de regla

`DailyLedger` guarda `baselineAmount`: el nivel de actividad desde el cual cuenta la regla actual.
Al cambiar la regla, el baseline salta a los pasos actuales y los milestones vuelven a cero, así
que **la actividad ya pagada nunca se vuelve a pagar** (PRD §16). Cubierto por `RuleChangeTests`.

`EarningSource` ya contempla `workout`, `focusSession`, `runningDistance`, etc., pero solo `steps`
está implementado (`EarningSource.implemented`).
