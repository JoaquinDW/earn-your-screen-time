# Earn Your Screen Time

> Moverse primero. Scrollear después.

App iOS nativa: ganás minutos de pantalla caminando. Cuando el saldo llega a cero, las apps que
elegiste se bloquean solas.

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
make test     # tests de la lógica de negocio — corren en tu Mac, sin iPhone (38 tests)
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
4. Vas a ver dos *targets* en la lista del medio: **EarnYourScreenTime** y
   **DeviceActivityMonitorExtension**. Para **cada uno**:
   - Pestaña **Signing & Capabilities**.
   - Tildá **Automatically manage signing**.
   - En **Team**, elegí tu cuenta.
   - Verificá que aparezcan las capabilities **Family Controls** y **App Groups**
     (con `group.com.balthasardeweert.earnyourscreentime` tildado).
     Si no aparecen: botón **+ Capability** (arriba a la izquierda de esa pestaña) → agregalas.
5. En tu iPhone: **Ajustes → Privacidad y seguridad → Modo de desarrollador → activar**
   (el teléfono se reinicia).
6. Conectá el iPhone por cable, elegilo en la barra superior de Xcode y apretá **▶︎ (Run)**.
7. La primera vez el iPhone va a decir "Desarrollador no confiable":
   **Ajustes → General → VPN y gestión de dispositivos → tu cuenta → Confiar**.

### Si cambiás el identificador de la app
Está en tres lugares y los tres tienen que coincidir:
`project.yml`, `Shared/AppGroup.swift`, y los dos archivos `.entitlements`.

---

## 4. Qué probar en el iPhone (checklist Fase 1)

1. Abrí la app → **Dar acceso a Tiempo de uso** → aceptá el diálogo del sistema.
   El estado debe pasar a **Aprobado**.
2. **Elegir apps a bloquear** → seleccioná Instagram / TikTok / lo que uses.
   El contador "Seleccionadas" debe subir.
3. Tocá **Bloquear ahora**.
4. Salí de la app y abrí Instagram → **tiene que aparecer una pantalla de bloqueo**.
5. Volvé a la app → **Desbloquear ahora** → Instagram abre normal otra vez.
6. Probá también: **Debug: sumar 5 minutos** → el estado pasa a **DISPONIBLE** y el bloqueo se
   levanta solo; **Debug: reiniciar el día** → vuelve a **BLOQUEADO**.

Si los pasos 4 y 5 funcionan, el riesgo técnico principal del producto está despejado y podemos
seguir con la Fase 2 (medir el consumo real de uso).

---

## 5. Estructura

```
Packages/EarnDomain/   Lógica pura y testeable (créditos, billetera, umbrales). Sin APIs de Apple.
Shared/                Código compartido entre la app y las extensiones (App Group, shields, monitoreo).
App/                   La app: servicios, pantallas.
Extensions/            Extensiones que corren con la app cerrada.
docs/                  Arquitectura y límites de la plataforma.
project.yml            Definición del proyecto Xcode (fuente de verdad).
```

Leé `docs/ARQUITECTURA.md` para entender **por qué** el consumo se mide como se mide, y
`docs/LIMITACIONES.md` para lo que Apple simplemente no permite.

---

## 6. Fases

- [x] **Fase 0** — Andamiaje, dominio y tests.
- [x] **Fase 1** — Autorización → selector de apps → bloquear → desbloquear. *(falta probar en iPhone)*
- [ ] **Fase 2** — DeviceActivity: consumo real de uso y re-bloqueo automático.
- [ ] **Fase 3** — HealthKit: pasos.
- [ ] **Fase 4** — Loop completo integrado.
- [ ] **Fase 5** — SwiftData y reset diario.
- [ ] **Fase 6** — UI de producto (onboarding, dashboard, ajustes).

---

## 7. Desarrollar sin la cuenta Apple (mientras esperás la aprobación)

La app corre en el Simulador con un mock de Screen Time: se ve toda la UI y toda la lógica de
la billetera. Lo único que no funciona ahí es el bloqueo real.

```bash
make build                                  # compila
./scripts/seed-simulator.sh 3842 360 es     # carga un estado de ejemplo y abre la app en español
./scripts/seed-simulator.sh 1000 0 en       # 1.000 pasos, nada consumido, en inglés
```

Verificado: el App Group **sí funciona en el Simulador**, así que el camino
`App Group → JSON → dominio → UI` se prueba entero sin iPhone y sin cuenta paga.
