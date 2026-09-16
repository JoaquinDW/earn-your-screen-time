# Arquitectura

## El problema central

Apple **no le da a tu app** el uso exacto de otras apps. No existe una API que devuelva
"TikTok = 4 minutos hoy". `DeviceActivityReport` muestra esos datos dentro de una vista sandboxeada
cuyo contenido no puede salir de la extensión que la dibuja.

Por eso el producto no intenta medir consumo real. Reserva por adelantado una ventana de reloj,
permite terminarla antes de tiempo desde Earn y usa `DeviceActivityMonitorExtension` para volver a
aplicar los shields al finalizar.

## Cómo funciona una sesión de acceso

Las apps elegidas están bloqueadas por defecto. El saldo ganado no quita el shield automáticamente:
el usuario elige de forma explícita una ventana de 1 a 180 minutos.

```
al iniciar       = se reserva toda la duración en la wallet
sesión vigente   = se quitan los shields
al terminar antes = se cobra el reloj transcurrido y se devuelve el resto
al vencer        = se reaplican los shields
```

La reserva es inmediata. Terminar una sesión antes de tiempo liquida los segundos de reloj transcurridos
y devuelve el resto. Cambiar la selección no cancela ni extiende la sesión global. Si el usuario
cambia de app o bloquea el teléfono, el reloj sigue hasta que vuelva a Earn y termine la sesión.
Una sesión puede cruzar medianoche usando hasta 20 minutos del saldo que se
traslada al nuevo día.

`ScreenTimeSessionEngine` concentra las transiciones puras: iniciar una única sesión, terminarla antes,
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

La wallet tiene un cap fijo de 180 minutos. A medianoche se conservan como máximo 20 minutos,
incluida la reserva pendiente de una sesión activa; ganado y consumido del día vuelven a cero. La
parte de la sesión anterior a medianoche se liquida en el día que termina y el resto continúa
reservado en el nuevo día con el mismo UUID y la misma hora de finalización.

Si la app vuelve a primer plano, `RestrictionCoordinator.reconcile` conserva un monitor válido o
lo reconstruye para el tiempo restante. Si el registro falla, la operación falla cerrada: restaura
el saldo anterior, cancela la sesión y mantiene los shields.

## Dónde vive el estado

| Capa | Qué guarda | Quién la usa |
|---|---|---|
| `UserDefaults` del App Group (`SharedStore`) | saldo, regla, día y sesión actual | la app **y** las extensiones |
| `UserDefaults` del App Group (`MonitorScheduler`) | registro del monitor de la sesión | la app y la extensión de monitoreo |
| `FamilyActivitySelection` codificada (`SelectionStore`) | los tokens opacos de las apps elegidas | la app y las extensiones |
| Supabase Postgres | identidad anónima, entitlement, sesiones Study/Pushups y recompensas | Edge Functions con service role |
| SwiftData *(Fase 5)* | ajustes e historial diario | solo la app |

`DeviceActivityMonitorExtension` corre con un presupuesto de memoria muy chico y se muere si se
pasa. Por eso lee y escribe `UserDefaults`, no una base de datos.

### Concurrencia

La app y la extensión casi nunca están vivas a la vez. La reserva del saldo se persiste antes de
quitar shields y antes de iniciar el monitor. Después, el estado de sesión solo avanza de `active`
a `completed`, `paused` (fin anticipado) o `cancelled`; cada callback vuelve a cargar el blob y valida
el UUID antes de escribir. Un lock de archivo dentro del App Group serializa `load-mutate-save` entre
procesos para que un fin anticipado, un callback y una acreditación concurrentes no se sobrescriban.

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

## Study to Earn

La cámara entrega una imagen transitoria a `VisionStudyOCRService`. Vision extrae texto en el
dispositivo; la imagen no se persiste ni se envía. `SupabaseStudyService` autentica una cuenta
anónima y envía solamente el texto OCR a una Edge Function. La función valida longitud, locale,
entitlement, feature flag y capacidad diaria antes de pedir a OpenAI una respuesta estructurada.
El texto OCR se trata siempre como datos no confiables, nunca como instrucciones.

Supabase guarda temporalmente texto OCR, respuesta de referencia y criterios mientras la sesión
está activa. Esos campos se ponen en `NULL` al aprobar, abandonar o expirar. La respuesta escrita
por el usuario se evalúa sin insertarla en Postgres. Cancelar el flujo cancela la petición HTTP y
el fetch a OpenAI; una sesión ya creada se abandona explícitamente.

`grant_study_reward` es la autoridad de recompensas Study: corre como `security definer`, serializa
por usuario/día UTC, vuelve a validar entitlement y cap, y crea como máximo una transacción por
sesión. El cliente no tiene permisos directos sobre tablas ni sobre esta función. El recibo UUID se
aplica a la wallet dentro del lock de `SharedStore`; `SharedState.appliedStudyReceiptIDs` sobrevive
rollovers para que reintentos de red no acrediten dos veces. `RewardTransaction` audita método,
segundos, fecha y sesión externa. El cap local de 180 minutos se valida antes de empezar y de aplicar
el recibo; nunca se acredita una recompensa parcial.

El UUID de Supabase también se entrega a RevenueCat como App User ID. La app comprueba Pro para la
UI y el backend lo vuelve a comprobar mediante estado sincronizado por API/webhook. Ninguna clave
OpenAI, RevenueCat secreta o Supabase service-role entra en el binario iOS.

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

`EarningSource` ya contempla `workout`, `focusSession`, `runningDistance`, etc. `steps` y el flujo
discreto de Pushups están implementados; las demás fuentes siguen fuera de alcance
(`EarningSource.implemented`).

## Pushups to Earn

`VisionPushupDetector` usa la cámara trasera con `AVCaptureVideoDataOutput`, descarta frames tardíos y
analiza como máximo unos 12 frames por segundo con `VNDetectHumanBodyPoseRequest`. Convierte
inmediatamente las observaciones de Vision a `BodyPose`, un tipo pequeño y sin frameworks de Apple,
y las pasa a `PushupRepCounter` en `EarnDomain`. Ningún frame, imagen o landmark se persiste, se sube
o entra en analítica.

`PushupRepCounter` exige confianza suficiente, cuerpo completo, alineación básica de hombro-cadera-
tobillo y el ciclo completo arriba → abajo → arriba. La pérdida prolongada de pose reinicia el ciclo;
la histéresis, duración mínima y debounce evitan contar ruido dos veces. Los umbrales llegan desde
Supabase y quedan limitados por constraints del esquema.

Supabase crea una `exercise_session` antes de contar y `claim_exercise_reward` concede como máximo un
recibo por sesión. El servidor vuelve a comprobar target, entitlement Pro, versión del detector y cap
de 30 minutos por día UTC dentro de una transacción serializada. Para el MVP acepta el resumen local
de repeticiones: App Attest puede reforzar integridad en el futuro, pero no demostraría por sí solo el
movimiento físico.

El saldo gastable sigue siendo la wallet del App Group. Supabase autoriza la recompensa, no decide los
shields ni conoce pasos o consumo local. `PendingExerciseClaimStore` guarda solo el resumen necesario
para reintentar; `completed_at` permite reclamar tras recuperar conexión si el reto terminó dentro de
la ventana original. El recibo se aplica con `ServerRewardEngine` dentro del lock de `SharedStore` y
solo entonces se elimina el pendiente. Un cierre entre cualquiera de esos pasos no pierde ni duplica
minutos.
