# -*- coding: utf-8 -*-
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
PRIV = "https://www.earnitscreen.com/privacy.html"

M = {}

M["en-US"] = dict(
 name="Earn Screen Time Rewards",
 subtitle="Stop Doomscrolling: Limit Apps",
 keywords="walk,unlock,steps,digital,detox,dopamine,blocker,squats,pushups,workout,self,control,addiction,phone",
 promo="New: try a real push-up set right in onboarding and feel exactly how Earnit unlocks your apps. Camera-counted, video never saved.",
 desc="""Your phone shouldn't be free. Earn it.

Earnit locks the apps that eat your day and keeps them locked until you do something worth doing. Walk. Do push-ups. Do squats. Every effort turns into minutes you can actually spend.

HOW IT WORKS
1. Pick the apps you want blocked. They stay shielded by default.
2. Earn minutes — steps from Apple Health, or push-ups and squats counted on device.
3. Spend them in a deliberate 5, 10 or 15 minute session. When it ends, the shield comes back on its own.

WHY IT WORKS WHEN TIMERS DON'T
A timer asks you to stop. Earnit asks you to trade. There's no "15 more minutes" button, no snooze, no talking yourself past it — the only way through the block is effort you actually did. That small friction is the whole product.

WALK TO UNLOCK
Steps come straight from Apple Health. Set a rate that suits you and every walk quietly refills your balance.

PUSH-UPS TO UNLOCK
Push-ups, squats, lunges or jumping jacks, counted on device by the camera. No wearable needed, no video saved. A set of reps when you want minutes back.

SEE WHAT CHANGES
A 30-day journey, a daily ledger and monthly totals show screen time going down and effort going up — without guilt, streak-shaming or red warning screens.

BUILT PRIVATE
Health and motion data stay on your iPhone. Which apps you blocked is never visible to us — iOS keeps that private even from Earnit.

Move first. Scroll later.""")

M["en-GB"] = dict(
 name="Earn Screen Time Rewards",
 subtitle="Stop Doomscrolling: Limit Apps",
 keywords="walk,unlock,steps,digital,detox,dopamine,blocker,squats,pressups,gym,self,control,addiction,phone",
 promo="New: try a real press-up set right in onboarding and feel exactly how Earnit unlocks your apps. Camera-counted, video never saved.",
 desc=M["en-US"]["desc"].replace("push-ups","press-ups").replace("Push-ups","Press-ups").replace("PUSH-UPS","PRESS-UPS"))

M["es-ES"] = dict(
 name="Ganar tiempo pantalla: Earnit",
 subtitle="Supera la adicción al móvil",
 keywords="bloquear,apps,detox,digital,autocontrol,flexiones,ejercicio,limite,habitos,dejar de scrollear",
 promo="Nuevo: prueba una serie real de flexiones en el propio onboarding y descubre cómo Earnit desbloquea tus apps. La cámara cuenta, el vídeo nunca se guarda.",
 desc="""Tu móvil no debería ser gratis. Gánatelo.

Earnit bloquea las apps que te comen el día y las mantiene bloqueadas hasta que hagas algo que merezca la pena. Camina. Haz flexiones. Haz sentadillas. Cada esfuerzo se convierte en minutos que puedes gastar de verdad.

CÓMO FUNCIONA
1. Elige las apps que quieres bloquear. Quedan bloqueadas por defecto.
2. Gana minutos: pasos desde Apple Health, o flexiones y sentadillas contadas en el propio móvil.
3. Gástalos en una sesión deliberada de 5, 10 o 15 minutos. Al terminar, el bloqueo vuelve solo.

POR QUÉ FUNCIONA CUANDO LOS TEMPORIZADORES NO
Un temporizador te pide que pares. Earnit te pide que cambies algo por algo. No hay botón de "15 minutos más", no hay posponer, no hay forma de convencerte a ti mismo: lo único que abre el bloqueo es esfuerzo que hiciste de verdad. Esa fricción pequeña es todo el producto.

CAMINA PARA DESBLOQUEAR
Los pasos llegan directamente desde Apple Health. Ajusta el ritmo que te venga bien y cada paseo rellena tu saldo sin que tengas que pensarlo.

FLEXIONES PARA DESBLOQUEAR
Flexiones, sentadillas, zancadas o jumping jacks, contados por la cámara en el propio móvil. Sin pulsera ni reloj, sin guardar vídeo. Una serie cuando quieras recuperar minutos.

MIRA LO QUE CAMBIA
Un recorrido de 30 días, un registro diario y totales mensuales enseñan cómo baja el tiempo de pantalla y sube el esfuerzo, sin culpa, sin rachas que avergüencen y sin pantallas rojas de advertencia.

PRIVADO DESDE EL DISEÑO
Los datos de salud y movimiento se quedan en tu iPhone. Qué apps has bloqueado no lo vemos nunca: iOS lo mantiene privado incluso frente a Earnit.

Muévete primero. Scrollea después.""")

M["es-MX"] = dict(
 name="Ganar tiempo pantalla: Earnit",
 subtitle="Bloqueador de apps y detox",
 keywords="adiccion al celular,autocontrol,lagartijas,ejercicio,limite,bloqueo,habitos,dejar de scrollear",
 promo="Nuevo: prueba una serie real de lagartijas en el propio onboarding y descubre cómo Earnit desbloquea tus apps. La cámara cuenta, el video nunca se guarda.",
 desc=M["es-ES"]["desc"].replace("móvil","celular").replace("flexiones","lagartijas").replace("FLEXIONES","LAGARTIJAS").replace("paseo","caminata").replace("pulsera ni reloj","banda ni reloj").replace("vídeo","video").replace("Flexiones","Lagartijas").replace("zancadas","desplantes"))

M["de-DE"] = dict(
 name="Bildschirmzeit: Earnit",
 subtitle="App Sperre & Digital Detox",
 keywords="verdienen,handysucht,selbstkontrolle,kniebeugen,fokus,ablenkung,limit,gewohnheit,weniger scrollen",
 promo="Neu: Probier direkt im Onboarding einen echten Satz Liegestütze und erlebe, wie Earnit deine Apps freischaltet. Kamera zählt, Video wird nie gespeichert.",
 desc="""Dein Handy sollte nicht umsonst sein. Verdien es dir.

Earnit sperrt die Apps, die dir den Tag wegfressen, und hält sie gesperrt, bis du etwas tust, das sich lohnt. Laufen. Liegestütze. Kniebeugen. Jede Anstrengung wird zu Minuten, die du wirklich ausgeben kannst.

SO FUNKTIONIERT ES
1. Wähl die Apps, die gesperrt werden sollen. Sie bleiben standardmäßig blockiert.
2. Verdien Minuten: Schritte aus Apple Health oder Liegestütze und Kniebeugen, die das Gerät selbst zählt.
3. Gib sie in einer bewussten Session von 5, 10 oder 15 Minuten aus. Danach greift die Sperre von allein wieder.

WARUM ES WIRKT, WO TIMER VERSAGEN
Ein Timer bittet dich aufzuhören. Earnit bittet dich zu tauschen. Kein "15 Minuten mehr"-Knopf, kein Schlummern, kein Sich-selbst-Überreden — durch die Sperre kommst du nur mit Anstrengung, die du tatsächlich erbracht hast. Diese kleine Reibung ist das ganze Produkt.

LAUFEN ZUM ENTSPERREN
Schritte kommen direkt aus Apple Health. Stell dir ein Tempo ein, das zu dir passt, und jeder Spaziergang füllt dein Guthaben ganz nebenbei auf.

LIEGESTÜTZE ZUM ENTSPERREN
Direkt auf dem Gerät gezählt, ganz ohne Wearable. Ein Satz, wenn du Minuten zurückwillst.

SIEH, WAS SICH ÄNDERT
Eine 30-Tage-Reise, ein Tagesjournal und Monatssummen zeigen, wie die Bildschirmzeit sinkt und der Aufwand steigt — ohne schlechtes Gewissen, ohne Streak-Beschämung, ohne rote Warnbildschirme.

PRIVAT GEBAUT
Gesundheits- und Bewegungsdaten bleiben auf deinem iPhone. Welche Apps du gesperrt hast, sehen wir nie — iOS hält das sogar vor Earnit geheim.

Erst bewegen. Dann scrollen.""")

M["fr-FR"] = dict(
 name="Temps d'écran : Earnit",
 subtitle="Bloquer les applis & détox",
 keywords="gagner,addiction telephone,autodiscipline,concentration,pompes,limite,distraction,habitude",
 promo="Nouveau : essayez une vraie série de pompes dès l'onboarding et découvrez comment Earnit débloque vos applis. La caméra compte, la vidéo n'est jamais gardée.",
 desc="""Votre téléphone ne devrait pas être gratuit. Méritez-le.

Earnit bloque les applis qui dévorent vos journées et les garde bloquées jusqu'à ce que vous fassiez quelque chose qui en vaut la peine. Marcher. Faire des pompes. Des squats. Chaque effort devient des minutes que vous pouvez réellement dépenser.

COMMENT ÇA MARCHE
1. Choisissez les applis à bloquer. Elles restent verrouillées par défaut.
2. Gagnez des minutes : pas issus d'Apple Health ou pompes et squats comptés par le téléphone.
3. Dépensez-les dans une session délibérée de 5, 10 ou 15 minutes. À la fin, le blocage revient tout seul.

POURQUOI ÇA MARCHE LÀ OÙ LES MINUTEURS ÉCHOUENT
Un minuteur vous demande d'arrêter. Earnit vous demande d'échanger. Pas de bouton "encore 15 minutes", pas de report, aucun moyen de vous convaincre : la seule clé du blocage, c'est l'effort réellement fourni. Cette petite friction, c'est tout le produit.

MARCHER POUR DÉBLOQUER
Les pas viennent directement d'Apple Health. Réglez un rythme qui vous convient et chaque promenade recharge votre solde sans y penser.

POMPES POUR DÉBLOQUER
Comptées sur l'appareil, sans montre ni bracelet. Une série quand vous voulez récupérer des minutes.

VOYEZ CE QUI CHANGE
Un parcours de 30 jours, un journal quotidien et des totaux mensuels montrent le temps d'écran qui baisse et l'effort qui monte — sans culpabilité, sans séries humiliantes, sans écrans d'alerte rouges.

CONÇU PRIVÉ
Les données de santé et de mouvement restent sur votre iPhone. Les applis que vous bloquez, nous ne les voyons jamais : iOS les garde privées, même vis-à-vis d'Earnit.

Bougez d'abord. Scrollez ensuite.""")
