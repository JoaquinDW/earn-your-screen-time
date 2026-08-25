# Arquitectura

## El problema central

Apple **no le da a tu app** el uso exacto de otras apps. No existe una API que devuelva
"TikTok = 4 minutos hoy". `DeviceActivityReport` muestra esos datos dentro de una vista sandboxeada
cuyo contenido no puede salir de la extensión que la dibuja.

Por eso el producto no intenta medir consumo real. Reserva por adelantado una ventana de reloj,
permite pausarla explícitamente desde Earn y usa `DeviceActivityMonitorExtension` para volver a
aplicar los shields al finalizar.

## Cómo funciona una sesión de acceso

Las apps elegidas están bloqueadas por defecto. El saldo ganado no quita el shield automáticamente:
el usuario elige de forma explícita una ventana de 1 a 180 minutos.

```
al iniciar       = se reserva toda la duración en la wallet
sesión vigente   = se quitan los shields
al pausar        = se cobra el reloj transcurrido y se devuelve el resto
al vencer        = se reaplican los shields
```

La reserva es inmediata. Pausar o cambiar la selección liquida los segundos de reloj transcurridos
y devuelve el resto. Si el usuario cambia de app o bloquea el teléfono, el reloj sigue hasta que
vuelva a Earn y pause. Las sesiones no pueden cruzar medianoche.

`ScreenTimeSessionEngine` concentra las transiciones puras: iniciar una única sesión, pausarla,
completarla, cancelarla y recuperar una sesión vencida. `ScreenTimeSession` persiste UUID, inicio,
fin, duración, estado y liquidación. Los callbacks incluyen el UUID en el nombre de la actividad para que
un callback atrasado nunca pueda completar una sesión más nueva.

### Carrier de Device Activity

Apple exige que `DeviceActivitySchedule` dure al menos 15 minutos. `MonitorScheduler` registra una
actividad no repetitiva `accessSession_<UUID>`. Las sesiones cortas usan un carrier de 15 minutos:

- 5 minutos: `intervalWillEndWarning`, diez minutos antes del final del carrier;
- 10 minutos: `intervalWillEndWarning`, cinco minutos antes del final;
- 15 minutos: `intervalDidEnd`.
- más de 15 minutos: `intervalDidEnd` al final de la duración elegida.

La wallet tiene un cap fijo de 180 minutos. A medianoche terminan las sesiones y se conservan como
máximo 20 minutos; ganado y consumido del día vuelven a cero.

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
a `completed`, `paused` o `cancelled`; cada callback vuelve a cargar el blob y valida el UUID antes de escribir.
Un lock de archivo dentro del App Group serializa `load-mutate-save` entre procesos para que una
pausa, un callback y una acreditación concurrentes no se sobrescriban.

## Capas

```
EarnDomain (paquete Swift)     lógica pura, sin frameworks de Apple, testeable en la Mac
        ↑
Shared/                        App Group, shields, scheduler, RestrictionCoordinator
        ↑                      (compilado dentro de la app Y de las extensiones)
App/ y Extensions/             UI y callbacks del sistema
```

`LiveActivitySupport/` es una excepción deliberada al árbol anterior: contiene únicamente el DTO
de ActivityKit y se compila en la app y en `EarnLiveActivityExtension`. No entra en `Shared/` ni en
la extensión de Device Activity. La app convierte `SharedState` ya resuelto en ese DTO; el widget
solo lo representa y nunca calcula crédito, saldo o shields.

`RestrictionCoordinator` es el **único** lugar que decide BLOQUEADO vs DISPONIBLE. Tanto la app
como la extensión pasan por él, así la regla no puede divergir entre los dos.

`ScreenTimeServing` es un protocolo con implementación real y mock: en el Simulador se usa el mock
(donde Screen Time no existe), en el iPhone la real.

`EarnLiveActivityManager` es el único punto que inicia, actualiza y termina la Live Activity. Su
estado normal es inactivo: una acreditación, una meta completada o el vencimiento de una sesión se
muestran durante unos segundos y después terminan. Solo una `ScreenTimeSession` explícita y vigente
mantiene una cuenta atrás; el saldo disponible por sí solo nunca inicia una actividad. Sus fallos son
suplementarios y nunca revierten una sesión ni una acreditación.

## Reglas de ganancia y cambios de regla

`DailyLedger` guarda `baselineAmount`: el nivel de actividad desde el cual cuenta la regla actual.
Al cambiar la regla, el baseline salta a los pasos actuales y los milestones vuelven a cero, así
que **la actividad ya pagada nunca se vuelve a pagar** (PRD §16). Cubierto por `RuleChangeTests`.

`EarningSource` ya contempla `workout`, `focusSession`, `runningDistance`, etc., pero solo `steps`
está implementado (`EarningSource.implemented`).
