# Earnit

> Moverse primero. Scrollear después.

App iOS nativa: ganás minutos de pantalla caminando y los usás para iniciar sesiones explícitas de
5, 10 o 15 minutos. Las apps elegidas permanecen bloqueadas fuera de una sesión activa.

**Estado: Fase 1 (spike técnico) — código listo, falta probarlo en un iPhone real.**

---

## 1. Qué necesitás antes de correrlo

| Requisito | Por qué |
|---|---|
| **Cuenta paga del Apple Developer Program** (99 USD/año) | Las cuentas gratuitas (*Personal Team*) **no pueden** usar Family Controls ni App Groups. Sin esto no compila para el iPhone. |
| **iPhone físico** | En el Simulador la autorización de Tiempo de uso siempre falla y los bloqueos no existen. |
| Xcode 26 | Ya lo tenés instalado. |
| XcodeGen | `brew install xcodegen` (ya instalado). |

---

## 2. Comandos (desde la carpeta del proyecto)

```bash
make test     # tests de la lógica de negocio — corren en tu Mac, sin iPhone
make build    # compila para el Simulador
make device   # verifica que compile para iPhone
make gen      # regenera el .xcodeproj (correr después de agregar archivos)
make open     # abre el proyecto en Xcode
```

> **Importante:** `EarnYourScreenTime.xcodeproj` es un archivo **generado**. No lo edites a mano:
> la fuente de verdad es `project.yml`. Si agregás archivos nuevos, corré `make gen`.

---

## 3. Configuración manual en Xcode (una sola vez, cuando tengas la cuenta)

1. Abrí Xcode → **Settings → Accounts → +** → agregá tu Apple ID.
2. `make open` para abrir el proyecto.
3. En la barra lateral izquierda, clic en el proyecto azul **EarnYourScreenTime** (arriba de todo).
4. Vas a ver la app y tres extensiones: **DeviceActivityMonitorExtension**,
   **ShieldConfigurationExtension** y **ShieldActionExtension**. Para **cada target**:
   - Pestaña **Signing & Capabilities**.
   - Tildá **Automatically manage signing**.
   - En **Team**, elegí tu cuenta.
    - Verificá que aparezca **Family Controls**. La app, el monitor y la configuración del shield
      también usan **App Groups** (`group.com.balthasardeweert.earnyourscreentime`).
     Si no aparecen: botón **+ Capability** (arriba a la izquierda de esa pestaña) → agregalas.
   - Solo en el target **EarnYourScreenTime**, agregá además **HealthKit** (para leer los pasos).
     La extensión no lo necesita.
5. En tu iPhone: **Ajustes → Privacidad y seguridad → Modo de desarrollador → activar**
   (el teléfono se reinicia).
6. Conectá el iPhone por cable, elegilo en la barra superior de Xcode y apretá **▶︎ (Run)**.
7. La primera vez el iPhone va a decir "Desarrollador no confiable":
   **Ajustes → General → VPN y gestión de dispositivos → tu cuenta → Confiar**.

### Si cambiás el identificador de la app
Mantené alineados `project.yml`, `Shared/AppGroup.swift` y todos los archivos `.entitlements` que
declaran el App Group. Cada extensión requiere además su propio bundle ID y aprobación de Family
Controls para distribución.

---

## 4. Qué probar en el iPhone

1. Abrí la app → **Dar acceso a Tiempo de uso** → aceptá el diálogo del sistema.
   El estado debe pasar a **Aprobado**.
2. **Elegir apps a bloquear** → seleccioná Instagram / TikTok / lo que uses.
   El contador "Seleccionadas" debe subir.
3. Sumá o ganá 10 minutos y verificá que Instagram siga bloqueada.
4. Iniciá una sesión de 5 minutos: Instagram queda accesible y el saldo baja inmediatamente a 5.
5. Al terminar, verificá que el monitor reaplique el shield y llegue la notificación **Time's up**.
6. Iniciá otra sesión con los 5 minutos restantes.

iOS puede no expulsar inmediatamente una app que ya está en foreground. La prueba correcta es que
el shield quede aplicado para la próxima evaluación o entrada, no forzar el cierre.

---

## 5. Estructura

```
Packages/EarnDomain/   Lógica pura y testeable (créditos, billetera, sesiones). Sin APIs de Apple.
Shared/                Código compartido entre la app y las extensiones (App Group, shields, monitoreo).
App/                   La app: servicios, pantallas.
Extensions/            Extensiones que corren con la app cerrada.
docs/                  Arquitectura y límites de la plataforma.
project.yml            Definición del proyecto Xcode (fuente de verdad).
```

Leé `docs/ARQUITECTURA.md` para entender **por qué** las sesiones reservan tiempo por adelantado, y
`docs/LIMITACIONES.md` para lo que Apple simplemente no permite.

### El sistema de diseño (`App/DesignSystem/`)

| Archivo | Qué es |
|---|---|
| `NightTheme.swift` | La paleta cruda de v6: negro casi puro (`#070E0D`), verde bosque y **un solo** acento, cobalto (`#2E5CE6`). El cobalto está ausente cuando no ganaste nada y aparece con el progreso: el color *es* la señal, y su escasez es parte de la identidad. No hay rojo en ningún estado. |
| `Theme.swift` | La capa semántica que leen las pantallas (`ink`, `muted`, `background`, `line`, espaciados). Resuelve sobre `Night`, así que cambiar la paleta es un solo archivo. |
| `Typography.swift` | **Instrument Serif** para títulos y números, **Figtree** para el texto corrido. Las dos vienen en `App/Resources/Fonts` (licencia SIL OFL) y caen al tipo del sistema si fallara el registro. |
| `SceneBackdrop.swift` | El único lugar donde la ilustración se encuentra con la UI. `IllustratedScene` nombra las cinco láminas y guarda lo que el archivo no puede decir: de qué borde recorta y dónde está la persona (`figureBand`). `SceneBackdrop` hace el `aspectFill` y el degradado que funde la lámina en el fondo; `SceneHero` es la banda superior; `.clearOfFigure(in:)` corta una columna de UI donde empieza la figura. |
| `PaperBackground.swift` | El fondo liso con el grano que evita el *banding* en los degradados oscuros. |
| `Controls.swift` | La píldora de acción, las líneas finas que reemplazan a las tarjetas, las filas de opción y `TickMeter`, la regla de guiones que mide el progreso en toda la app. |

El Home no muestra nada que no sea hoy: el recorrido de 30 días y los totales del mes viven en
la pestaña **Progreso**, y elegir 5/10/15 minutos es una hoja que se abre desde la fila
*Ready to spend*.

La app fija la apariencia oscura (`preferredColorScheme(.dark)`): v6 es una sola paleta nocturna,
igual en ambos modos del sistema, porque las láminas están pintadas al anochecer y no existe una
variante clara de ellas.

**Las ilustraciones se usan en tres niveles.** Fuertes en Home, Ganar tiempo, Bloqueado, el arranque
del onboarding y el paywall; secundarias en Progreso y en el cierre de los 30 días; y **ninguna** en
Ajustes, selección de apps, reglas, permisos o suscripción — esas pantallas tienen que sostener la
identidad con tipografía, color y espaciado. El ícono de la app se genera con
`swift scripts/make-app-icon.swift design/earnit-logo.png …` (recorta el margen, rellena las esquinas
y escribe un PNG de 1024×1024 sin canal alfa, que es lo que exige App Store).

---

## 6. Fases

- [x] **Fase 0** — Andamiaje, dominio y tests.
- [x] **Fase 1** — Autorización → selector de apps → bloqueo por defecto. *(falta probar en iPhone)*
- [x] **Fase 2** — Sesiones discretas con reserva inmediata y re-bloqueo por DeviceActivity. *(falta probar en iPhone)*
- [x] **Fase 3** — HealthKit: autorización y lectura de pasos del día. *(falta entrega en background, va en Fase 4)*
- [ ] **Fase 4** — Loop completo integrado.
- [ ] **Fase 5** — SwiftData y reset diario.
- [x] **Fase 6** — UI de producto: onboarding, dashboard, selección de apps y ajustes, en es/en.
- [x] **Fase 7** — Identidad visual ("Move first. Scroll later."): onboarding orientado a resultados
      con plan personalizado, proyección a 30 días, paywall propio, activación y continuidad en Home.

---

## 7. Desarrollar sin la cuenta Apple (mientras esperás la aprobación)

La app corre en el Simulador con un mock de Screen Time: se ve toda la UI y toda la lógica de
la billetera. Lo único que no funciona ahí es el bloqueo real.

```bash
make build                                  # compila
./scripts/seed-simulator.sh 3842 360 es     # home con una semana de historial, en español
./scripts/seed-simulator.sh 3842 900 en     # billetera vacía: arranca en el estado "en pausa"
./scripts/seed-simulator.sh 1000 0 es 0     # arranca en el onboarding, desde la primera pantalla
```

Verificado: el App Group **sí funciona en el Simulador**, así que el camino
`App Group → JSON → dominio → UI` se prueba entero sin iPhone y sin cuenta paga.
