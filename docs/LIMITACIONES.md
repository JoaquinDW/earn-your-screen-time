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
No hay API que devuelva minutos por app ni avise cuando el usuario sale de ella. Al iniciar una
sesión se reserva la duración elegida y se abre una ventana de reloj. El saldo sigue corriendo aunque
el usuario bloquee el teléfono o cambie de app. Para conservar el resto debe volver a Earn y
terminar la sesión antes de tiempo.

## 5. Los callbacks de Device Activity no son temporizadores exactos
`intervalWillEndWarning` e `intervalDidEnd` los entrega iOS y pueden demorarse. Mitigación:
- la app reconcilia contra `endsAt` cada vez que pasa a primer plano;
- una notificación local avisa un minuto antes y al terminar;
- el callback valida el UUID y es idempotente;
- toda pérdida de estado o fallo de monitor termina con shields aplicados.

**Pendiente de medir en hardware:** latencia real de ambos callbacks y comportamiento con la app y
el teléfono bloqueados.

## 6. Intervalo mínimo de 15 minutos
`DeviceActivitySchedule` no admite intervalos más cortos. Para sesiones menores de 15 minutos usamos
un carrier de 15 minutos y terminamos en `intervalWillEndWarning`; las sesiones de 15 minutos o más
terminan en `intervalDidEnd`.

## 7. Un shield no expulsa de forma garantizada una app abierta
Al vencer la sesión reaplicamos el shield, pero iOS no garantiza cerrar de inmediato una app que ya
está en primer plano. La restricción sí aparece al volver a entrar o cuando el sistema vuelve a
evaluarla. No existe una API pública para forzar el cierre.

## 8. Los pasos en background llegan como mucho ~1 vez por hora
HealthKit despierta la app con `HKObserverQuery` + `enableBackgroundDelivery`, pero para step count
el sistema limita las entregas a aproximadamente una por hora.

Traducción honesta al producto:
- si el usuario **abre la app**, la acreditación de nuevos minutos es instantánea;
- si no la abre, la acreditación llega cuando iOS despierte la app (puede tardar hasta ~1 hora).

Mitigación: notificación local al acreditar en background + copy en el shield que invita a abrir la
app. **No hay forma soportada de mejorar esto.**

## 9. Abrir la app desde el botón del shield depende de la versión
Desde iOS 26.5, `ShieldActionResponse.openParentalControlsApp` permite abrir públicamente la app que
aplicó el shield. En iOS 18–26.4 no existe esa respuesta: el botón cierra la app restringida con
`.close` y el usuario debe abrir Earn manualmente. No usamos URLs ni APIs privadas para esquivarlo.

La configuración del shield solo admite un botón primario y uno secundario; no puede alojar tres
acciones independientes de 5/10/15 minutos. En iOS 26.5+ el botón primario abre Earn directamente en
el selector de duración. Después de iniciar la sesión, iOS tampoco permite relanzar la app restringida
identificada por un token opaco, así que el usuario vuelve a tocarla; desde ese momento todo el grupo
queda disponible durante la misma sesión.

## 10. Memoria de las extensiones
`DeviceActivityMonitorExtension` corre con un presupuesto de memoria muy chico y el sistema la mata
si se pasa. Prohibido meter ahí SwiftData, red o frameworks pesados.

## 11. Los tokens son opacos
`ApplicationToken` y compañía no exponen bundle ID ni nombre. No se puede mostrar "TikTok" en la UI
salvo con `Label(token)`, que dibuja el sistema. Tampoco se puede subir esa información a un
servidor de forma útil. No intentamos derivar identidades (PRD §27).

## 12. HealthKit no dice si te dieron permiso de lectura
Por privacidad, Apple no revela si el usuario concedió lectura de pasos: revelarlo delataría que
esa persona no tiene datos de salud. `authorizationStatus(for:)` solo informa sobre permisos de
**escritura**. La única señal honesta es "preguntamos y una consulta respondió".

Consecuencia: **alguien que denegó el permiso se ve exactamente igual que alguien que no caminó**
(0 pasos). La UI está escrita para que ambos casos se lean con sentido, y el onboarding marca el
paso como completado cuando se mostró el diálogo del sistema, no cuando se concedió — porque eso
último no se puede saber.

## 13. Una Live Activity no es permanente
ActivityKit limita una Live Activity a ocho horas en Dynamic Island. Después puede permanecer hasta
cuatro horas adicionales en Lock Screen. Earn solo restaura una actividad ausente si todavía existe
una sesión explícita de acceso; caminar, tener saldo o abrir la app no crean una actividad persistente.

Los eventos de recompensa se terminan desde la app después de unos segundos. `staleDate` permite que
el widget deje de representar una cuenta atrás vigente, pero no elimina por sí solo la actividad. Si
la app está suspendida justo al vencer una sesión, la actividad puede mostrar temporalmente que el
tiempo terminó y se limpia la próxima vez que Earn se ejecuta.

## 14. Las recompensas exteriores dependen de ejecución de la app
El proyecto aún no registra `HKObserverQuery` ni background delivery, por lo que caminar con Earn
cerrada no acredita ni presenta una recompensa inmediatamente. La sesión activa sí lleva `endsAt`:
el sistema puede dibujar su cuenta atrás y marcar el contenido vencido sin actualizaciones por segundo
ni timers de la app.

## 15. Study to Earn necesita cámara y red
El OCR ocurre en el dispositivo y la foto no se sube, pero generar y evaluar la pregunta requiere
Supabase, OpenAI y una suscripción Pro verificable. Sin cámara, permiso, conexión o configuración
del backend no se puede completar una misión Study. Vision puede fallar con texto manuscrito,
borroso, corto o en un idioma no soportado; la app pide otra captura en vez de inventar contenido.

El backend limita la recompensa a 15 minutos por misión y 30 minutos por día UTC, sin parciales.
La app también rechaza iniciar si no cabe la recompensa completa en el saldo local de 180 minutos.
El Simulador permite compilar y recorrer estados no dependientes de cámara real, pero la captura y
el flujo productivo deben validarse en un iPhone con credenciales Supabase configuradas.

## 16. Pushups to Earn necesita cámara, cuerpo completo y red para cobrar

La detección ocurre en el iPhone y no graba ni sube vídeo, pero Vision necesita ver de perfil hombro,
codo, muñeca, cadera y tobillo con luz suficiente. Ropa, oclusiones, fondos, distancia, movimiento del
móvil y diferencias entre dispositivos afectan la detección. El contador valida un ciclo básico; no
evalúa técnica profesional, seguridad ni riesgo de lesión.

El reto se completa sin red, pero Supabase debe autorizar la recompensa. El resumen del claim se guarda
localmente y se reintenta de forma idempotente. Para el MVP el servidor confía en las repeticiones que
reporta el cliente y se limita a imponer entitlement, configuración, caducidad, cap UTC y no duplicación.
La cámara, la orientación landscape, consumo de batería y falsos positivos deben calibrarse en iPhones
reales; el Simulador solo valida compilación y estados de UI.
