# -*- coding: utf-8 -*-
"""Customer-facing release notes for the editable 1.3.5 App Store version.

1.3.4 (live since 2026-10-27) shipped Friends, squads, the new camera exercises and the
refreshed Home. 1.3.5 adds the guided first reward in onboarding, the simpler paywall with
the trial timeline, and Korean. The rating prompt and hiding Study are not called out.
Push with `python3 aso/push_whatsnew.py --write`, read back with `python3 aso/verify.py`.
"""

_EN = ("A simpler start: during setup you now earn your first real minutes and unlock an app step by step, so you see how Earnit works right away.\n\n"
       "A clearer Pro screen shows each step of your free trial before you choose a plan.\n\n"
       "Earnit is now available in Korean, plus smaller fixes and polish.")
_ES_ES = ("Un comienzo más sencillo: durante la configuración ganas tus primeros minutos reales y desbloqueas una app paso a paso, para ver cómo funciona Earnit desde el primer momento.\n\n"
          "La pantalla de Pro es más clara y muestra cada paso de tu prueba gratuita antes de elegir un plan.\n\n"
          "Earnit ya está disponible en coreano, además de pequeñas mejoras y correcciones.")
_ES_MX = ("Un comienzo más sencillo: durante la configuración ganas tus primeros minutos reales y desbloqueas una app paso a paso, para que veas cómo funciona Earnit desde el primer momento.\n\n"
          "La pantalla de Pro es más clara y muestra cada paso de tu prueba gratis antes de elegir un plan.\n\n"
          "Earnit ya está disponible en coreano, además de pequeñas mejoras y correcciones.")
_FR = ("Un démarrage plus simple : pendant la configuration, vous gagnez vos premières vraies minutes et déverrouillez une app étape par étape, pour comprendre tout de suite comment fonctionne Earnit.\n\n"
       "L’écran Pro, plus clair, présente chaque étape de votre essai gratuit avant que vous choisissiez une formule.\n\n"
       "Earnit est désormais disponible en coréen, avec aussi quelques corrections et améliorations.")

W = {
    "en-US": _EN,
    "en-GB": _EN,
    "en-AU": _EN,
    "en-CA": _EN,
    "es-ES": _ES_ES,
    "es-MX": _ES_MX,
    "de-DE": ("Ein einfacherer Start: Bei der Einrichtung verdienst du jetzt deine ersten echten Minuten und gibst Schritt für Schritt eine App frei – so siehst du sofort, wie Earnit funktioniert.\n\n"
              "Der übersichtlichere Pro-Bildschirm zeigt jeden Schritt deines kostenlosen Probezeitraums, bevor du ein Abo wählst.\n\n"
              "Earnit gibt es jetzt auch auf Koreanisch, dazu kleinere Fehlerbehebungen und Verbesserungen."),
    "fr-FR": _FR,
    "fr-CA": _FR,
    "it": ("Un inizio più semplice: durante la configurazione guadagni i tuoi primi minuti reali e sblocchi un’app passo dopo passo, così capisci subito come funziona Earnit.\n\n"
           "La schermata Pro è più chiara e mostra ogni fase della prova gratuita prima di scegliere un piano.\n\n"
           "Earnit ora è disponibile anche in coreano, con piccole correzioni e miglioramenti."),
    "pt-BR": ("Um começo mais simples: durante a configuração, você ganha seus primeiros minutos de verdade e desbloqueia um app passo a passo, para ver na hora como o Earnit funciona.\n\n"
              "A tela do Pro ficou mais clara e mostra cada etapa do teste grátis antes de você escolher um plano.\n\n"
              "O Earnit agora está disponível em coreano, além de pequenas correções e melhorias."),
    "nl-NL": ("Een eenvoudiger begin: tijdens het instellen verdien je nu je eerste echte minuten en ontgrendel je stap voor stap een app, zodat je meteen ziet hoe Earnit werkt.\n\n"
              "Het overzichtelijkere Pro-scherm toont elke stap van je gratis proefperiode voordat je een abonnement kiest.\n\n"
              "Earnit is nu ook in het Koreaans beschikbaar, plus kleine verbeteringen en oplossingen."),
    "pl": ("Prostszy start: podczas konfiguracji zdobywasz pierwsze prawdziwe minuty i krok po kroku odblokowujesz aplikację, więc od razu widzisz, jak działa Earnit.\n\n"
           "Bardziej przejrzysty ekran Pro pokazuje każdy etap bezpłatnego okresu próbnego, zanim wybierzesz plan.\n\n"
           "Earnit jest teraz dostępny także po koreańsku, a do tego drobne poprawki i usprawnienia."),
    "tr": ("Daha kolay bir başlangıç: Kurulum sırasında artık ilk gerçek dakikalarını kazanıyor ve bir uygulamanın kilidini adım adım açıyorsun; böylece Earnit’in nasıl çalıştığını hemen görüyorsun.\n\n"
           "Daha anlaşılır Pro ekranı, bir plan seçmeden önce ücretsiz denemenin her adımını gösteriyor.\n\n"
           "Earnit artık Korece de kullanılabiliyor; ayrıca küçük düzeltmeler ve iyileştirmeler var."),
    "ru": ("Более простое начало: во время настройки вы зарабатываете первые настоящие минуты и шаг за шагом разблокируете приложение, чтобы сразу понять, как работает Earnit.\n\n"
           "Обновлённый экран Pro понятнее показывает каждый этап бесплатного пробного периода до выбора плана.\n\n"
           "Earnit теперь доступен на корейском языке, а также мелкие исправления и улучшения."),
    "ja": ("はじめての設定がよりシンプルに：設定中に最初の分数を実際に獲得し、アプリのロック解除をステップごとに体験できるので、Earnitの使い方がすぐにわかります。\n\n"
           "Proの画面がわかりやすくなり、プランを選ぶ前に無料トライアルの流れを確認できます。\n\n"
           "Earnitが韓国語に対応しました。そのほか細かな修正と改善を行いました。"),
    "ko": ("더 쉬워진 시작: 설정 중에 첫 번째 시간을 직접 얻고 앱 잠금 해제를 단계별로 해 보며 Earnit의 사용법을 바로 알 수 있습니다.\n\n"
           "더 명확해진 Pro 화면에서 요금제를 고르기 전에 무료 체험의 각 단계를 확인할 수 있습니다.\n\n"
           "이제 Earnit을 한국어로 사용할 수 있습니다. 그 밖에 작은 수정과 개선이 포함되어 있습니다."),
    "zh-Hans": ("更简单的上手体验：设置过程中，你会赚到第一批真正的分钟数，并一步步解锁一个 App，马上了解 Earnit 的用法。\n\n"
                "更清晰的 Pro 页面会在你选择方案前展示免费试用的每个阶段。\n\n"
                "Earnit 现已支持韩语，并包含一些小修复和改进。"),
    "zh-Hant": ("更簡單的上手體驗：設定過程中，你會賺到第一批真正的分鐘數，並一步步解鎖一個 App，馬上了解 Earnit 的用法。\n\n"
                "更清楚的 Pro 畫面會在你選擇方案前顯示免費試用的每個階段。\n\n"
                "Earnit 現已支援韓文，並包含一些小修正和改進。"),
    "ar-SA": ("بداية أبسط: أثناء الإعداد تكسب الآن أولى دقائقك الحقيقية وتفتح تطبيقًا خطوة بخطوة، لترى فورًا كيف يعمل Earnit.\n\n"
              "شاشة Pro أصبحت أوضح، وتعرض كل مرحلة من الفترة التجريبية المجانية قبل أن تختار خطة.\n\n"
              "أصبح Earnit متاحًا الآن باللغة الكورية، إلى جانب إصلاحات وتحسينات صغيرة."),
}
