# Arquitectura

## El problema central

Apple **no le da a tu app** el uso exacto de otras apps. No existe una API que devuelva
"TikTok = 4 minutos hoy". `DeviceActivityReport` muestra esos datos dentro de una vista sandboxeada
cuyo contenido no puede salir de la extensión que la dibuja.

Por eso el producto no intenta medir consumo real. Reserva por adelantado una ventana de reloj y
usa `DeviceActivityMonitorExtension` únicamente para volver a aplicar los shields al finalizar.

## Cómo funciona una sesión de acceso

Las apps elegidas están bloqueadas por defecto. El saldo ganado no quita el shield automáticamente:
el usuario compra de forma explícita una ventana de 5, 10 o 15 minutos.

```
al iniciar       = se reserva toda la duración en la billetera
sesión vigente   = se quitan los shields
al vencer        = se reaplican los shields
```

La reserva es inmediata y no se reembolsa si cambia la selección, se resetea el día o cruza la
medianoche. Así la contabilidad no depende de poder leer cuánto tiempo pasó realmente dentro de
otra app, dato que Apple no expone.

`ScreenTimeSessionEngine` concentra las transiciones puras: iniciar una única sesión, completarla,
cancelarla y recuperar una sesión vencida. `ScreenTimeSession` persiste UUID, inicio, fin, duración,
estado y segundos reservados. Los callbacks incluyen el UUID en el nombre de la actividad para que
un callback atrasado nunca pueda completar una sesión más nueva.

### Carrier de Device Activity

Apple exige que `DeviceActivitySchedule` dure al menos 15 minutos. `MonitorScheduler` registra una
actividad no repetitiva `accessSession_<UUID>` con un carrier de 15 minutos:

- 5 minutos: `intervalWillEndWarning`, diez minutos antes del final del carrier;
- 10 minutos: `intervalWillEndWarning`, cinco minutos antes del final;
- 15 minutos: `intervalDidEnd`.

Si la app vuelve a primer plano, `RestrictionCoordinator.reconcile` conserva un monitor válido o
lo reconstruye para el tiempo restante. Si el registro falla, la operación falla cerrada: restaura
el saldo anterior, cancela la sesión y mantiene los shields.

## Dónde vive el estado

| Capa | Qué guarda | Quién la usa |
|---|---|---|
| `UserDefaults` del App Group (`SharedStore`) | saldo, regla, día y sesión actual | la app **y** las extensiones |
| `UserDefaults` del App Group (`MonitorScheduler`) | registro del monitor de la sesión | la app y la extensión de monitoreo |
| `FamilyActivitySelection` codificada (`SelectionStore`) | los tokens opacos de las apps elegidas | la app y las extensiones |
| SwiftData *(Fase 5)* | ajustes e historial diario | solo la app |

`DeviceActivityMonitorExtension` corre con un presupuesto de memoria muy chico y se muere si se
pasa. Por eso lee y escribe `UserDefaults`, no una base de datos.

### Concurrencia

La app y la extensión casi nunca están vivas a la vez. La reserva del saldo se persiste antes de
quitar shields y antes de iniciar el monitor. Después, el estado de sesión solo avanza de `active`
a `completed` o `cancelled`; cada callback vuelve a cargar el blob y valida el UUID antes de escribir.

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
