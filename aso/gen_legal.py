# -*- coding: utf-8 -*-
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
PRIV = "https://www.earnitscreen.com/privacy.html"

BODY = {
"en-US":("Earnit requires a subscription to unlock app blocking and time earning. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in your Apple Account settings.","Terms of Use (EULA)","Privacy Policy"),
"en-GB":("Earnit requires a subscription to unlock app blocking and time earning. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in your Apple Account settings.","Terms of Use (EULA)","Privacy Policy"),
"es-ES":("Earnit requiere una suscripción para desbloquear el bloqueo de apps y la obtención de tiempo. Las suscripciones se renuevan automáticamente salvo que se cancelen al menos 24 horas antes del final del periodo actual. Puedes gestionarla o cancelarla cuando quieras en los ajustes de tu cuenta de Apple.","Términos de uso (EULA)","Política de privacidad"),
"es-MX":("Earnit requiere una suscripción para desbloquear el bloqueo de apps y la obtención de tiempo. Las suscripciones se renuevan automáticamente salvo que se cancelen al menos 24 horas antes del final del periodo actual. Puedes gestionarla o cancelarla cuando quieras en los ajustes de tu cuenta de Apple.","Términos de uso (EULA)","Política de privacidad"),
"de-DE":("Earnit benötigt ein Abo, um App-Sperren und das Verdienen von Zeit freizuschalten. Abos verlängern sich automatisch, sofern sie nicht mindestens 24 Stunden vor Ende des laufenden Zeitraums gekündigt werden. Verwalten oder kündigen kannst du jederzeit in den Einstellungen deines Apple-Accounts.","Nutzungsbedingungen (EULA)","Datenschutzrichtlinie"),
"fr-FR":("Earnit nécessite un abonnement pour débloquer le blocage d'applis et le gain de temps. Les abonnements se renouvellent automatiquement sauf résiliation au moins 24 heures avant la fin de la période en cours. Vous pouvez gérer ou résilier à tout moment dans les réglages de votre compte Apple.","Conditions d'utilisation (EULA)","Politique de confidentialité"),
"it":("Earnit richiede un abbonamento per sbloccare il blocco delle app e il guadagno di tempo. Gli abbonamenti si rinnovano automaticamente salvo disdetta almeno 24 ore prima della fine del periodo in corso. Puoi gestirlo o disdirlo quando vuoi nelle impostazioni del tuo account Apple.","Termini d'uso (EULA)","Informativa sulla privacy"),
"pt-BR":("O Earnit exige uma assinatura para liberar o bloqueio de apps e o ganho de tempo. As assinaturas renovam automaticamente, a menos que sejam canceladas pelo menos 24 horas antes do fim do período atual. Você pode gerenciar ou cancelar quando quiser nos ajustes da sua conta Apple.","Termos de uso (EULA)","Política de privacidade"),
"nl-NL":("Earnit vereist een abonnement om appblokkering en het verdienen van tijd te ontgrendelen. Abonnementen worden automatisch verlengd tenzij ze minstens 24 uur voor het einde van de lopende periode worden opgezegd. Beheren of opzeggen kan altijd via de instellingen van je Apple-account.","Gebruiksvoorwaarden (EULA)","Privacybeleid"),
"pl":("Earnit wymaga subskrypcji, aby odblokować blokowanie aplikacji i zdobywanie czasu. Subskrypcje odnawiają się automatycznie, o ile nie zostaną anulowane co najmniej 24 godziny przed końcem bieżącego okresu. Możesz nią zarządzać lub anulować w dowolnej chwili w ustawieniach konta Apple.","Warunki korzystania (EULA)","Polityka prywatności"),
"tr":("Earnit, uygulama engellemeyi ve zaman kazanmayı açmak için abonelik gerektirir. Abonelikler, mevcut dönemin bitiminden en az 24 saat önce iptal edilmedikçe otomatik olarak yenilenir. Apple hesabı ayarlarından dilediğin zaman yönetebilir veya iptal edebilirsin.","Kullanım Koşulları (EULA)","Gizlilik Politikası"),
"ru":("Earnit требует подписки, чтобы открыть блокировку приложений и заработок времени. Подписка продлевается автоматически, если не отменить её не позднее чем за 24 часа до конца текущего периода. Управлять или отменить можно в любой момент в настройках вашей учётной записи Apple.","Условия использования (EULA)","Политика конфиденциальности"),
"ja":("Earnitのアプリロックと時間の獲得を使うにはサブスクリプションが必要です。現在の期間が終わる24時間前までに解約しない限り、自動的に更新されます。管理や解約はいつでもAppleアカウントの設定から行えます。","利用規約（EULA）","プライバシーポリシー"),
"ko":("Earnit의 앱 차단과 시간 적립을 사용하려면 구독이 필요합니다. 현재 기간이 끝나기 최소 24시간 전에 해지하지 않으면 자동으로 갱신됩니다. Apple 계정 설정에서 언제든지 관리하거나 해지할 수 있습니다.","이용약관(EULA)","개인정보 처리방침"),
"zh-Hans":("使用 Earnit 的应用锁与时间赚取功能需要订阅。除非在当前订阅期结束前至少 24 小时取消，否则将自动续订。你可以随时在 Apple 账户设置中管理或取消。","使用条款（EULA）","隐私政策"),
"ar-SA":("يتطلب Earnit اشتراكاً لتفعيل حظر التطبيقات وكسب الوقت. يتجدد الاشتراك تلقائياً ما لم يتم إلغاؤه قبل 24 ساعة على الأقل من نهاية الفترة الحالية. يمكنك إدارته أو إلغاؤه في أي وقت من إعدادات حساب Apple.","شروط الاستخدام (EULA)","سياسة الخصوصية"),
}

def block(loc):
    body, tou, pp = BODY[loc]
    return "\n\n———\n%s\n\n%s: %s\n%s: %s" % (body, tou, EULA, pp, PRIV)
