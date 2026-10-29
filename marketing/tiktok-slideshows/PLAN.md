# Slideshows de TikTok para Earnit: plan

Basado en el artículo de @ChadAppDev ("How to scale your app to $1M w/ TikTok Slideshows"), adaptado al momento actual de Earnit.

## El orden, en una línea

Primero vos mirás TikTok y elegís qué formato copiar. Después Codex arma la máquina que fabrica slideshows. Después posteás orgánico unas semanas. Recién al final, y solo si la app retiene, pagás distribución.

## Paso 1: investigar formatos (vos, 1 hora, Codex no lo puede hacer)

Codex no puede navegar TikTok, así que este paso es manual. Es lo que el artículo llama "find a winning format".

1. En TikTok, buscá: `screen time`, `phone addiction`, `doomscrolling`, `how I stopped scrolling`, `dopamine detox`, `reduce screen time`. Y en español: `tiempo de pantalla`, `adicción al celular`, `dejar de scrollear`.
2. Filtrá por **fotos** (los slideshows aparecen como carrusel de fotos).
3. Guardá los que tienen **muchas vistas comparado con los seguidores de la cuenta**. Ejemplo: 2.000 seguidores y 400K vistas. Esos son los que "viajan" fuera de su audiencia.
4. Lo que buscás es **repetición**: la misma estructura funcionando en 4 o 5 cuentas distintas.
5. Para los 3 mejores, anotá slide por slide: qué promete el hook (slide 1), qué hacen los del medio, en qué slide aparece la app, qué pide el último.
6. Pasá esas notas (o capturas) a `marketing/tiktok-slideshows/research/` en el repo, o pegámelas acá y las convierto en formatos.

Si no querés hacer este paso todavía, Codex puede arrancar con los 5 formatos de abajo, que son hipótesis míos de lo que suele funcionar en el nicho. Pero la versión basada en lo que viste vos va a ser mejor.

## Paso 2: el generador (Codex)

Una herramienta dentro del repo que recibe **formato + tema** y escupe un slideshow listo para subir: 6 PNGs verticales 1080×1920 + el texto del post + hashtags. Usa los screenshots reales de la app para el slide del producto y la misma identidad visual (marfil, navy, cobalto). El prompt para Codex está en [codex-prompt.md](codex-prompt.md).

## Paso 3: postear orgánico (vos, 2 a 4 semanas)

- 1 cuenta de TikTok sin cara, en inglés (mercado US). Si querés, una segunda en español.
- 1 o 2 slideshows por día. En el día 1, no te preocupes por la calidad. Lo que importa es el volumen y ver qué hook pega.
- Anotá en una planilla: formato, hook, vistas a las 48 h, guardados, clicks al perfil. A las 2 semanas, duplicá los 2 formatos que mejor funcionan y descartá el resto.
- Esto también sirve para el ASO: los hooks que funcionen son candidatos para subtítulos y screenshots del App Store.

## Paso 4: pagar distribución (después, no ahora)

La parte de Content Rewards (pagarle a creadores por CPM) tiene sentido cuando la app retiene. Con la retención D7 de 0/23 que vimos en la auditoría, más tráfico hoy se pierde igual. En paralelo con los pasos 1 a 3, la prioridad del producto sigue siendo activación: que la gente bloquee apps y gane su primer tiempo el día 1.

## Los 5 formatos de arranque (hipótesis)

Reglas para todos: nada de testimonios inventados, ni "mi screen time bajó de 7 h a 2 h" si no es tuyo y real. Cualquier estadística tiene que tener fuente, o no va. Se puede escribir en segunda persona ("tu") o como el fundador que construyó la app (eso sí es real).

### F1. "Cosas que de verdad me hicieron dejar de scrollear" (lista)
Slide 1, hook: *5 things that actually stopped my doomscrolling (not "just delete the app")*. Slides 2 a 4: tips genuinos y sin producto, por ejemplo celular en escala de grises, cargarlo fuera del cuarto, sacar las notificaciones. Slide 5: Earnit, "my apps stay locked until I walk or do push-ups". Slide 6: el mejor tip guardado para el final y "save this".
Por qué puede andar: da valor primero, el producto aparece como un tip más y la gente lo guarda.

### F2. "POV: tu celular te hace hacer flexiones antes de abrir TikTok"
Slide 1: POV + imagen de alguien con el celular. Slide 2: captura del shield ("Apps locked until you earn time"). Slide 3: la cámara contando 7/10 flexiones. Slide 4: "+10 min". Slide 5: sesión de 10 min corriendo. Slide 6: "and then it locks again".
Por qué puede andar: es raro, divertido y muestra el producto entero.

### F3. "Por qué los límites de tiempo de pantalla no funcionan"
Slide 1: *Screen Time limits don't work. Here's why.* Slides 2 y 3: "Ignore limit for 15 min" (todos lo apretaron). Slide 4: el problema es decidir en el momento de tentación. Slide 5: la alternativa, ganar el tiempo antes. Slide 6: Earnit.
Por qué puede andar: es contrario a lo que todos esperan y le habla a un dolor que el usuario ya conoce.

### F4. "Hice X durante 7 días" (solo si lo hacés de verdad)
Usá Earnit una semana con números reales tuyos: pasos, flexiones y minutos ganados. Un slide por día o resumen.
Por qué puede andar: es el formato que más convierte, pero solo funciona si los datos son reales.

### F5. "Tu noche vs. tu noche con Earnit" (antes / después)
Slide 1: *Your evening at 11pm vs. your evening when Instagram is locked*. Slides alternados de antes y después, con escenas cotidianas. El último: el screenshot de "Your day" con los minutos recuperados.
Por qué puede andar: es aspiracional y se entiende sin leer mucho.
