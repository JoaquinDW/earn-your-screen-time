# Límites de la plataforma

Lo que Apple permite y lo que no. Nada de esto se puede esquivar sin APIs privadas (= expulsión
del App Store).

## 1. Cuenta paga obligatoria
Las *Personal Teams* (Apple ID gratis) no soportan la capability **Family Controls** ni
**App Groups**. Sin membresía paga del Apple Developer Program el proyecto no compila para iPhone.

## 2. Dos entitlements distintos
- **Family Controls (Development):** se activa solo desde Xcode con cuenta paga. Alcanza para todo
  el MVP en tu propio iPhone.
- **Family Controls (Distribution):** hay que **pedirlo a Apple por formulario**, por bundle ID y
  **también por cada extensión**, para poder subir a TestFlight o App Store. En 2026 hay cola larga
  (solicitudes de marzo sin respuesta en verano). **Conviene mandarlo apenas exista el bundle ID.**

## 3. El Simulador no sirve
`AuthorizationCenter.requestAuthorization` siempre falla y los shields no existen. Todo el loop se
prueba en hardware real. El proyecto usa `MockScreenTimeService` en el Simulador para que la UI siga
siendo desarrollable.

## 4. No se puede leer el uso exacto de apps
No hay API que devuelva minutos por app. El consumo se **infiere por eventos de umbral**
(ver `ARQUITECTURA.md`). Consecuencia visible: el contador "usado hoy" avanza a saltos, no segundo
a segundo.

## 5. Los eventos de umbral no son perfectos
`eventDidReachThreshold` a veces se demora, se agrupa con otros, o no llega. Hay reportes
consistentes en iOS 17.5–18. Mitigación en este proyecto:
- el manejador es idempotente (`consumido = max(consumido, …)`);
- la app reconcilia el estado cada vez que pasa a primer plano;
- el umbral final coincide exactamente con el saldo, así que un tick perdido no adelanta ni atrasa
  el bloqueo.

**Pendiente de medir en Fase 2 con hardware:** latencia real del evento, tasa de eventos perdidos, y
cuántos eventos tolera una actividad. Los resultados van acá.

## 6. Intervalo mínimo de 15 minutos
`DeviceActivitySchedule` no admite intervalos más cortos. Usamos uno diario, así que no molesta.

## 7. `includesPastActivity` cambió en iOS 17.4
Antes de iOS 17.4 los eventos se comportaban como si fuera `true`; desde 17.4 el default es `false`
y además hay reportes de que con `false` los eventos a veces nunca llegan. Este proyecto lo setea
**explícitamente en `true`**, que además es lo que necesita el diseño de umbrales acumulados.

## 8. Los pasos en background llegan como mucho ~1 vez por hora
HealthKit despierta la app con `HKObserverQuery` + `enableBackgroundDelivery`, pero para step count
el sistema limita las entregas a aproximadamente una por hora.

Traducción honesta al producto:
- si el usuario **abre la app**, el desbloqueo es instantáneo;
- si no la abre, el desbloqueo llega cuando iOS despierte la app (puede tardar hasta ~1 hora).

Mitigación: notificación local al acreditar en background + copy en el shield que invita a abrir la
app. **No hay forma soportada de mejorar esto.**

## 9. El botón del shield no puede abrir tu app
`ShieldActionResponse` solo tiene `none`, `close` y `defer`. No existe "abrir app padre". El shield
solo puede mostrar texto; abrir Earn es una acción manual del usuario.

## 10. Memoria de las extensiones
`DeviceActivityMonitorExtension` corre con un presupuesto de memoria muy chico y el sistema la mata
si se pasa. Prohibido meter ahí SwiftData, red o frameworks pesados.

## 11. Los tokens son opacos
`ApplicationToken` y compañía no exponen bundle ID ni nombre. No se puede mostrar "TikTok" en la UI
salvo con `Label(token)`, que dibuja el sistema. Tampoco se puede subir esa información a un
servidor de forma útil. No intentamos derivar identidades (PRD §27).
