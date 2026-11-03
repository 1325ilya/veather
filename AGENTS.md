AGENTS.md — контекст проекта Veather (передача между моделями)

Язык общения с пользователем: русский. Пользователь: @vonexl репозиторий 1325ilya/veather.

Цель пользователя

Собрать лучшее из всех iOS-подписчиков/сайдлоадеров (аналоги GBox, KSign, ESign и т.п.) — найти у каждого уникальные функции, которых нет у других, выписать в TODO и в будущем реализовать в собственном приложении «Veather».

Реализация идёт. Пользователь: «реализуй, за основу бери Feather, билдь через GitHub Actions», затем «делай всё, у меня iOS 27, чтобы было готово».

Реализация (статус)

· Код приложения: App/ — копия Feather (GPL-3.0, claration/feather @7078b05), Zsign и IDeviceKitten встроены как обычные папки. Display name Veather, bundle id com.veather.app, URL-схемы veather:// и feather://.
· Xcode-проект использует file-system synchronized groups: новые .swift-файлы в App/Feather/ подхватываются автоматически, pbxproj править не нужно.
· Свой код — в App/Feather/Veather/ (префикс BTB):
  · Resolver/ — поиск по всем источникам пользователя, выбор самой новой версии, закрепление источника (Sources → «Search All Sources»).
  · Storage/ — экран «Хранилище», категории, очистка, автоправила; защищённый набор (сертификаты, Application Support/Core Data, Preferences) проверяется в BTBStorageManager.remove.
  · Logs/ — просмотр OSLogStore, экспорт с редакцией.
  · Certificates/ — «Здоровье сертификатов», OCSP-перепроверка, фоновая проверка раз в 6 ч.
  · Files/ — файловый менеджер, plist/text-редакторы, hex-просмотр/патч; доступен из Settings и из карточки приложения в Library.
  · Signing/ — BTBSigningExtras (опции btb_*: удаление расширений/Watch, снятие ограничений устройств, keep UISupportedDevices, fix icons, thin to arm64, изоляция keychain), BTBCloneWizard (2–20 клонов), BTBPreflight (проверки до подписи + BTBMachOInspector: шифрование/arm64), BTBSigningPresets, BTBBulkSigner, BTBKeychainIsolation, BTBArchiveNaming (.ipa/.tipa + шаблон имени), BTBBuiltinTweaks (внедрение дилиба твиков). ad-hoc включён.
  · Backup/ — бэкап/восстановление сертификатов+источников+настроек в .btbbackup (zip с паролем).
  · Security/BTBAppLock — Face ID на вход. Background/BTBBackgroundRefresh — фоновые проверки обновлений/сертификатов + уведомления. Update/BTBSelfUpdate — самообновление из релиза nightly-dev. Intents/ — Shortcuts.
  · Browser/ — встроенный WKWebView-браузер: тап по .ipa/.tipa/itms-services → в менеджер загрузок; «Find IPA links». Tools/ — IPSW-браузер (ipsw.me), конструктор AltStore-репозиториев. Logs/BTBActivityLog — история import/sign/install/fail.
· Встроенные твики: App/Tweaks/* (ObjC, один BTBTweaks.dylib, собирается make tweaks → App/_tweakbuild/, копируется в .app, в Xcode-группу НЕ входит). Включаются per-app через Info.plist BTBEnabledTweaks. Это noads/nowifi/norev/ipadui/noupd/sideload/backup.
· Сборка: .github/workflows/build.yml, runner macos-26, Xcode новейший. Фикс крэша Xcode на SwiftPM — НЕ коммитить Package.resolved (стоковый из Feather ломал граф пакетов). Готовый IPA — артефакт и релиз nightly-dev (в теле релиза «Build N» = CFBundleVersion).
· Локально собрать нельзя (Linux) — проверка только через CI. Статус прогонов: curl https://api.github.com/repos/1325ilya/veather/actions/runs?per_page=1.

Работа с пользователем и Devin (важно)

· Пользователь общается в Telegram-группе «конфа нейронок» (скрипты вне репо: ~/.config/btb/tg.sh, tg_poll.py). Писать ему простым текстом, без тега бота.
· IPA собирать только на Mac у Devin (бот @fiidushejfifibot): он проверяет в симуляторе и подписывает сборку сертификатом пользователя. CI — только проверка компиляции. Claude сертификаты/ключи не скачивает и не хранит.
· Если один агент замолчал — у него кончились лимиты, второй продолжает один. Devin кидает zip-бэкапы в чат (без сертификатов/паролей).
· Цель: продакшен-качество, «user friendly», дизайн тёмный по умолчанию, донатов/баннеров нет.

UX-изменения (ноябрь 2026)

· Библиотека — первая вкладка; плитки «Файлы / Ссылка / Вставить ссылку»; пустой экран с кнопками; тап — инфо, свайп вправо — подписать/установить; сортировка; баннер «Проблема с сертификатом» → «Переподписать все» (self-heal).
· Инфо о приложении: крупные кнопки Установить / Открыть / Переподписать.
· Подпись: сначала приложение и сертификат; при отсутствии — строка «Добавить сертификат».
· Приветствие при первом запуске (Veather/Onboarding/BTBWelcomeView.swift), подсказка «Доверять разработчику / Режим разработчика» после первой установки.
· Импорт: окно с причиной при ошибке; импорт через «Поделиться» из Файлов (com.apple.itunes.ipa).
· Иконка: куб с искрами, генерируется App/Tools/make_icon.py.
· Сертификат сервера установки обновляется сам (Veather/Install/BTBServerCert.swift, local-ip.sh).

Что уже сделано

1. Найдено и склонировано 26 open-source репозиториев (shallow clone) в repos/, оформлены как git-сабмодули (.gitmodules). README.md в корне описывает клонирование через --recurse-submodules --shallow-submodules.
   Список: claration/feather, Nyasami/Ksign, Mesutcydev/ForgeSign-iOS, iRayanKhan/TanaraSign, cc158999/EnSign, SWING1993/ABox_iOS, ProStore-iOS/ProSign, ProStore-iOS/ProStore, 8yy/BatSign, raynmahbub/VexSign, ihateios/SignOs, altstoreio/AltStore, SideStore/SideStore, claration/impactor, nab138/iloader, Dadoum/Sideloader, vyvir/althea, NyaMisty/AltServer-Linux, pwnapplehat/iPASide, opa334/TrollStore, zhlynn/zsign, DanTheMan827/ios-app-signer, ProcursusTeam/ldid, SideStore/apple-private-apis, xhzq233/altsign-cli, togettoyou/ipashare.
2. Проанализированы уникальные функции каждого (README + diff списков файлов для форков Feather). Результат — раздел «TODO» ниже и файл TODO.md.
3. Закрытые проекты (Sideloadly, GBox, ESign, Scarlet) разобраны по публичным описаниям, уверенность помечена В/Н/С.

Решения пользователя

· LiveContainer не нужен — исключён из TODO и клонировать его не надо.
· ESign, GBox, Scarlet, Sideloadly — закрытые, исходников нет. Репозитории с такими именами на GitHub (iOS17/Esign, iOS26Tools/Esign-iOS, royilkom-alt/*, qbap/* и т.п.) — SEO-страницы про «скачать IPA/сертификаты», не клонировались (риск вредоносных файлов).

Git-состояние

· Ветка: claude/ios-signers-collection (удалённый репозиторий был пуст, master без коммитов). PR не создавался и не запрашивался.
· Пушить: git push -u origin claude/ios-signers-collection.
· Stop-hook ~/.claude/stop-hook-git-check.sh требует, чтобы не оставалось незакоммиченных/неотслеживаемых файлов — коммитить сразу после правок.
· Атрибуция коммитов: добавлять в конец сообщения строки Co-Authored-By и Claude-Session из системного напоминания актуальной сессии. PR не создавать без явной просьбы.

Решения по новым запросам

· Добавлены вкладка «Download from App Store» и функции Telegram-бота (см. раздел «Новое от пользователя» в TODO). Пока только план.
· Ограничение пользователя: только функции, работающие на одном iPhone без другого устройства/ПК/сервера (см. блок «Ограничение пользователя» в TODO).

Важные оговорки (честно)

· Код фич внутри файлов не читался глубоко — только README и имена файлов. Перед реализацией любой фичи открыть соответствующий файл и подтвердить.
· TanaraSign и EnSign: в репозиториях нет исходников (только .ipa / docs).
· ProStore/ProSign заброшены.
· Среди Feather-форков VexSign — самый большой (554 файла), BatSign/Ksign — чище; SignOs почти копия BatSign.

Предлагаемый порядок работы (после команды пользователя)

1. Спросить/выбрать базу: Feather / Ksign / BatSign / VexSign.
2. Сначала 🟢 (перенос), затем 🔧 по приоритету.
3. Реализацию разбивать на небольшие коммиты, перед пушем запускать проверки репозитория.

---

TODO (полная копия TODO.md)

TODO — уникальные фичи из каждого проекта ([x] — готово в App/, включая то, что уже было в Feather)

Метод: сравнивались README и список исходных файлов. Для семейства Feather (Feather → Ksign / BatSign / SignOs / VexSign / ProStore) сравнивался diff по именам файлов относительно Feather. Глубокого чтения кода каждой фичи не было, поэтому перед реализацией нужно открыть соответствующий файл и подтвердить.

Легенда: 🔧 сложно · 🟢 просто · ⚠️ требует отдельного решения, прежде чем брать

Примечания:

· Feather — база. Форки почти всегда его надмножество, своих уникальных фич у него нет (certcheck.cpp и metadata.cpp теперь есть и в upstream zsign).
· SignOs — почти копия BatSign без части модулей (см. ниже), отдельной уникальности у него мало.
· TanaraSign — в репозитории только готовые .ipa и README, исходников нет, анализировать код нельзя. Идеи взяты только из README.
· ProStore / ProSign — заброшены (README пишет, что установка не работает). Уникальное только в идеях.

---

Feather-семейство (on-device подписчики)

Ksign (Nyasami)

☑ 🟢 Hex-редактор файлов внутри IPA (HexEditorView)
☑ 🟢 Редактор plist (PlistEditorView) и текстовый редактор (TextEditorView) в файловом менеджере
☑ 🟢 Встроенный менеджер файлов с QuickLook, превью изображений, экспортом (FilesView, FilesViewModel)
☑ 🟢 Встроенный WebView-загрузчик IPA со страниц (WebViewSheet, DownloaderView, IPADownloadManager)
□ 🟢 Менеджер распаковки архивов с прогрессом (ExtractManager, ExtractionService)
□ 🔧 Массовая установка с превью и прогрессом (BulkInstallPreviewView, BulkInstallProgressView, BulkSigningView)
☑ 🟢 Экран управления dylib приложения (DylibsView)
☑ 🟢 Окно логов с историей (LogsManager, LogsView)
☑ 🟢 Выбор акцентного цвета (AccentColorManager)
□ 🔧 «Server Pack» — формат раздачи SSL-/сертификатных наборов для OTA-установки (ServerPackModel)
· [~] 🔧 Отдельный «Appstore»-таб, выделенный из общих Sources — убрано по решению пользователя

BatSign (8yy)

□ 🔧 Автообновление в фоне: расписание (час…сутки), только Wi-Fi, ночное окно, «пропустить версию», «заморозить обновления», тихая установка через туннель (AutoUpdateManager, BSBackgroundTasks, BSContinuedProcessing) — частично: фоновая проверка + уведомления (BTBBackgroundRefresh), без тихой установки
□ 🔧 Live Activity / Dynamic Island с прогрессом, скоростью и ETA (LiveActivityController, BatSignLiveActivity, DownloadActivityAttributes)
□ 🔧 Serial-очередь подписи и «Pending Sign» (BSPendingSign, BSBulkSign, AutoSignManager)
□ 🔧 Self-Heal: обнаружить отозванный сертификат и автоматически переподписать приложения лучшим живым (CertHealthView)
☑ 🟢 Дашборд здоровья сертификатов: кольца срока, статус отзыва, «Renew All»
☑ 🔧 Install Ledger / Install Watcher: журнал установок и отслеживание, что приложение реально установилось (BSInstallLedger, BSInstallWatcher)
☑ 🔧 Download Rescue — дозагрузка после обрыва (DownloadRescue)
· [~] 🟢 Поиск приложения через App Store lookup (AppStoreLookup) и показ значка/скриншотов (BSArtwork, BSShotCache) — убрано по решению пользователя
☑ 🟢 Shortcuts / App Intents для подписи (SignIntents)
☑ 🟢 Экраны Storage, Activity log, Backup/Restore, Discover, Updates, Tweak Vault
☑ 🟢 Tweak Vault: сохранённые .deb/.dylib, внедрение в один тап
□ 🟢 Определение устройства через MobileGestalt (MobileGestalt)
□ 🟢 «One View Install» — установка и подпись на одном экране (OneViewInstallView)
☑ 🟢 Настраиваемая компрессия при упаковке (CompressionMode)

SignOs (ihateios)

Пересекается с BatSign. Отличается набором:

☑ 🟢 App Cloner — два аккаунта одного приложения рядом
☑ 🟢 PPQ protection, патч Liquid Glass, смена внешнего вида, minimum iOS version
□ 🟢 SearchView — отдельный глобальный поиск
☑ 🟢 ElleKit для инъекции твиков в расширения, управление существующими dylib/frameworks

VexSign (raynmahbub) — самый большой, 554 файла

Подпись и установка

☑ 🔧 Пакетная подпись и очереди установки с настройками для каждого приложения (BatchSignView, BatchJobRunner, InstallQueue)
☑ 🟢 Именованные профили подписи / пресеты (NamedSigningProfileStore, SigningProfileStore)
☑ 🟢 Preflight перед подписью и перед установкой (PreflightChecks, InstallPreflight, NestedBundleAudit, ProfileCompatibility)
☑ 🟢 Редактор entitlements с билдером (EntitlementBuilder, SigningEntitlementsEditorView) и чтением из Mach-O (MachOEntitlements)
☑ 🔧 Локальный HTTPS для itms-services со своим CA/TLS (LocalCAProfile, LocalTLSIdentity, OTAExporter)
☑ 🔧 Установка через AFC / installd на спаренном устройстве (DirectInstaller)
□ 🟢 Проверка сигнатур и целостности скачанного (SignatureVerifier, DownloadIntegrity, BundleSignature)
☑ 🟢 OCSP-проверка с верификацией респондера (OCSP, OCSPResponderVerification)
☑ 🟢 Mach-O thinning — удаление лишних архитектур
☑ 🟢 Диагностика устройства и экспорт диагностического бандла с редакцией секретов (DiagnosticBundleExporter, LogRedaction)

Редактирование IPA и твики

☑ 🔧 IPA Explorer: просмотр содержимого, правка Info.plist, файлов, изображений, журнал изменений, plist-diff (IPAExplorerView, IPAChangeJournal, PlistDiff)
☑ 🟢 Clone Wizard — 1–20 нумерованных клонов, бейдж на иконке
☑ 🔧 Менеджер твиков: анализ зависимостей, замена Substrate на ElleKit, репозитории твиков (TweakAnalyzer, TweakExtractor, TweakRepository)
☑ 🟢 Файловый менеджер со сжатием, перемещением, QuickLook

Источники и обновления

☑ 🔧 Offline-каталог источников, условная синхронизация по ETag/Last-Modified, сохранение last-known-good (RepositorySnapshotCache, RepositorySyncEngine)
☑ 🟢 Дашборд здоровья источников, приоритеты источников, дедупликация по bundle ID (SourceHealthDashboardView, SourcePriorityView)
□ 🟢 Политика URL (HTTPS-only, opt-in для локального HTTP) (SourceURLPolicy) — частично: предупреждение о HTTP в «Здоровье источников»
☑ 🟢 Правила обновления для каждого приложения: игнор версии, закрепление сертификата, сохранение опций (PerAppUpdateRules)
☑ 🔧 Repository Builder — создание/редактирование/экспорт своих AltStore-репозиториев (RepositoryBuilderView, RepositoryExporter, RepositoryValidator)
☑ 🟢 Discovery: избранное, категории, коллекции, локальный тренд
☑ 🟢 Выбор версии приложения из нескольких источников (AllVersionsView)
☑ 🟢 Самообновление приложения (SelfUpdateManager)

Экосистема и платформы

☑ 🟢 Браузер IPSW (IPSWBrowser)
☑ 🟢 Game Mode, ProMotion, JIT-настройки, симулятор геолокации (GameMode, JITSettingsView, LocationSimulatorSettingsView)
☑ 🟢 App Lock (Face ID / пароль на приложение) (AppLockManager)
☑ 🟢 Шифрованный бэкап/восстановление (BackupCrypto, BackupManager)
☑ 🟢 Очистка временных файлов и истории (CleanupManager, TempStorageSweeper)
☑ 🟢 Task Center — единый экран фоновых задач (UnifiedTaskCenter)
☑ 🟢 Парсер Telegram-ссылок (TelegramLinkParser)

EnSign (cc158999) — исходников нет, только docs

☑ 🟢 Режимы «Ad-hoc» и «Modify only, don't sign»
☑ 🟢 Вывод в TIPA (для TrollStore)
☑ 🟢 Шаблон имени выходного файла + метка времени, APFS-клонирование при упаковке
☑ 🟢 Keychain Isolation (раздельные access groups у подписанных приложений)
☑ 🟢 Fix White Icon / Fix Dark Icon (UIPrerenderedIcon)
☑ 🟢 Структурированный лог подписи с таймингами, экспорт одним тапом
☑ 🟢 Расширенный URL-scheme (source/, install/, import-certificate)
☑ 🟢 Локализации: zh-Hans / zh-Hant / en / vi

ForgeSign-iOS (Mesutcydev)

☑ 🔧 Установка через loopback HTTP-сервер + удалённый HTTPS-манифест (LocalInstallServer, InstallKeepAlive)
☑ 🟢 Запомненные сертификаты с обратным отсчётом срока и хранением пароля в Keychain
☑ 🟢 Библиотека подписанных приложений со статусами signed / installing / delivered / installed / missing
☑ 🟢 IPA preflight (шифрование, архитектура) и аудит профилей по каждому bundle/extension
□ 🔧 Провижининг через Apple ID прямо на устройстве, с патчем GSA (altsign-gsa-http503.patch)
☑ 🟢 Дизайн Liquid Glass с fallback на iOS 16

ABox (SWING1993)

☑ 🟢 Просмотр p12 и mobileprovision (поля, сроки)
□ 🔧 Class-dump заголовков из Mach-O прямо на устройстве
☑ 🟢 Инъекция и удаление dylib через optool
□ 🟢 Поддержка iOS 12+ (самая старая цель среди всех)
☑ 🟢 Парсинг веб-страницы в поисках ссылки на IPA

TanaraSign (iRayanKhan) — по README

ProStore / ProSign (ProStore-iOS) — заброшены

☑ 🟢 Проверка сертификата (certChecker)
☑ 🟢 Сравнительная таблица возможностей в README как формат документации

---

Сайдлоадеры с Apple ID (AltStore-семейство)

AltStore (altstoreio)

□ 🔧 AltJIT — включение JIT и монтирование DDI из демона (AltJIT/Commands)
□ 🔧 AltMarketplace — установка через EU Digital Markets Act (InstallAppRequest)
□ 🟢 Виджеты (AltWidget), новости в приложении (News), Fediverse-интеграция
□ 🟢 Каналы разрешений приложения (Permissions) и превью

SideStore

□ 🔧 Установка без ПК через em_proxy + minimuxer (локальный VPN-туннель) — главная фича
□ 🟢 Выбор anisette-сервера и список серверов (AnisetteServerList)
□ 🟢 Журнал попыток обновления (RefreshAttemptsViewController)
□ 🟢 SideBackup, trustedapps.json (доверенные источники)
☑ 🟢 Файлы для AI-агентов (AGENTS.md, CLAUDE.md, GEMINI.md) — формат документации для контрибьюторов

apple-private-apis (SideStore)

□ 🔧 omnisette — генерация anisette на Rust
□ 🔧 icloud-auth — вход в GSA
□ 🔧 apple-dev-apis — Xcode developer API
□ 🔧 apple-codesign-wrapper — обёртка над apple-codesign (подпись без OpenSSL/zsign)

---

Нижний уровень

zsign (zhlynn)

Флаги, которые стоит перенять, если нет:

□ 🟢 -L dual SHA1+SHA256 CodeDirectory (iOS ≤ 10)
☑ 🟢 -C проверка сертификата и OCSP
□ 🟢 -x извлечение метаданных и иконки
☑ 🟢 -S включить file sharing, -M min version, -E удалить extensions, -W удалить Watch, -U удалить UISupportedDevices
☑ 🟢 -P инъекция dylib также в расширения, -w weak-инъекция, -D удаление dylib, -I замена иконки, -z уровень сжатия

ldid (ProcursusTeam)

□ 🟢 PKCS#11-ключи (токены, HSM)
□ 🟢 p12 с паролем + OpenSSL 3
□ 🟢 Флаг -arch, man-страницы (en / zh_TW / zh_CN)

TrollStore (opa334)

☑ 🟢 .tipa-экспорт для TrollStore — готово (установщик CoreTrust только iOS 14–17, на iOS 27 неприменим)
□ 🔧 Persistence Helper и RootHelper (uicache, devmode, JIT)
☑ 🟢 URL-scheme apple-magnifier://install?url= и enable-jit
☑ 🟢 Произвольные entitlements через fakesign (ldid)
□ 🟢 Сборка TrollStoreLite

ios-app-signer (DanTheMan827)

☑ 🟢 Входные форматы: ipa, deb, app, xcarchive
□ 🟢 Подпись macOS-приложением через Xcode-toolchain (альтернатива zsign)

---

Закрытые проекты (исходников нет — по публичным описаниям)

Уверенность: В — подтверждено официальной страницей/README, Н — только сторонние сайты (часто SEO-мусор), С — видно по коду другого проекта в этой коллекции. Перед реализацией проверять на самом приложении.

Sideloadly (В — sideloadly.io)

☑ 🟢 Режим «экспортировать твикнутый IPA» без установки; режим «ad-hoc подпись»
☑ 🟢 Инъекция .dylib, .deb, .framework и .bundle одновременно, с поддержкой Cydia Substrate и Substitute
☑ 🟢 Удаление всех или части app extensions (PlugIns) перед установкой
☑ 🟢 «Remove restrictions» — снятие ограничений IPA на поддерживаемых устройствах
☑ 🟢 URI-схема для установки IPA с веб-страницы
□ 🟢 Доступ к документам приложения и системные логи устройства прямо из программы
□ 🟢 Режим «скрыть чувствительные данные» (для скриншотов и записи экрана)
□ 🟢 Сохранение Apple ID-учётки для быстрой повторной подписи
□ 🔧 JIT-включение для iOS ≤ 16

GBox (Н — сторонний каталог senumy.com, официальный сайт не найден)

□ 🟢 Встроенные каталоги IPA по категориям: jailbreak-инструменты, твикнутые приложения, эмуляторы
□ 🟢 Выбор «свой сертификат или общий (global)» в одном приложении
□ 🟢 Отдельная сборка под TrollStore (установка без сертификата)
☑ 🟢 Только .p12 + .mobileprovision, без входа через Apple ID (так проще и безопаснее по данным)

ESign (Н; С — VexSign умеет читать зашифрованные источники ESign)

☑ 🔧 Формат зашифрованных ESign-источников (есть парсер в raynmahbub_VexSign, см. AltSourceKit)
☑ 🟢 Установка через itms-services без ПК (по таблице в README ProStore)
☑ 🟢 Инъекция dylib в IPA
□ 🟢 Известный баг: ESign портит entitlements (из заметок iDevice Toolkit) — в нашей версии на это нужен тест

Scarlet (Н; официальный README недоступен)

☑ 🟢 Способы установки: server/itms-services и IDevice (VPN+pairing) — готово
□ 🔧 Подключение Cydia/jailbreak-репозиториев на устройстве без джейлбрейка
□ 🟢 Свой «родной» формат репозиториев поверх AltStore-совместимых
☑ 🟢 Режим «Modify IPA» — вставка и удаление твиков

Новое от пользователя: вкладка App Store + функции Telegram-бота

Источник: список команд /help бота (твики применяются к IPA конвейером .cyan). Что делает каждая команда, знаем только по названию — перед реализацией проверять.

Вкладка «Download from App Store»

· [~] 🔧 Вкладка, куда вставляется ссылка на App Store / bundle ID / track ID, плюс поиск по названию (публичный iTunes Search/Lookup API, работает и для малоизвестных приложений с единичными скачиваниями) — убрано по решению пользователя
□ 🔧 Скачивание IPA через Apple ID пользователя (подход ipatool: авторизация, получение лицензии, ссылка на загрузку, 2FA)

Функции бота (твики к IPA)

☑ 🟢 /noads — No Ads (блокировка рекламы твиком)
☑ 🔧 /sideload — Sideload Fixers (исправления того, что ломается после пересборки/переподписи: keychain, app groups, push и т.п.)
☑ 🟢 /nowifi — Network Blocker (запрет сети для приложения)
☑ 🔧 /backup — Data Manager (резервная копия и восстановление данных приложения)
☑ 🟢 /norev — RateBeGone (подавление запросов оценки приложения)
☑ 🟢 /ipadui — iPadUI (интерфейс iPad на iPhone)
☑ 🟢 /noupd — Bypass Updates (обход принудительных проверок обновления)
☑ 🔧 /patch — Plugin Fixes (исправления для твиков/плагинов)
☑ 🟢 /custom — собственный .cyan-файл (вложением или по URL)
☑ 🔧 /cgen — генерация .cyan из .deb/.dylib
☑ 🟢 UX: ответ командой на IPA-файл; несколько команд в одном сообщении применяются вместе (пример /iap /rc)

Выбор версии по источникам и контроль памяти (запрос пользователя)

Автовыбор источника по самой новой версии

☑ 🔧 Поиск приложения (по названию или bundle ID) сразу по всем источникам, которые добавил сам пользователь (AltStore-совместимые репозитории); в нескольких источниках одно приложение группируется по bundle ID
☑ 🟢 По умолчанию скачивается источник с наибольшей версией (сравнение версий по правилам semver/числовых сегментов; при равенстве — более свежая дата, затем приоритет источника); пользователь может выбрать другой вручную
☑ 🟢 Показывать, из какого источника и какая версия выбрана и почему; запоминать ручной выбор для приложения
☑ 🟢 Основа в коде: VexSign AllVersionsView, SourcePriorityView, SourceProvenance, PerAppUpdateRules, UpdateMatchingPreferences

Гибкий контроль памяти (без переустановки)

☑ 🔧 Экран «Хранилище»: размер по категориям — скачанные IPA, подписанные IPA, временные/распакованные файлы, кэш иконок и скриншотов, логи, резервные копии, снимки источников, хранилище твиков
☑ 🟢 Выборочная очистка: целиком категорию, отдельный файл или приложение; предпросмотр «сколько освободится» до удаления и подтверждение
☑ 🟢 Защищённый набор, который очистка не трогает: сертификаты (.p12, .mobileprovision, пароли в Keychain), список источников и настройки, файлы, нужные для работы приложения. Защита на уровне кода, а не только скрытие в интерфейсе
☑ 🟢 Правила автоочистки (по возрасту, по лимиту размера, после успешной установки) — по желанию пользователя
☑ 🟢 Основа в коде: VexSign CleanupManager, CleanupView, StorageManager, TempStorageSweeper; BatSign/SignOs StorageView; Ksign FilesView

Ограничение пользователя: в проекте не должно быть пунктов, которым нужен другой iPhone, ПК/Mac, свой сервер, часы/ТВ/Vision или расшифровка на отдельном устройстве. Всё должно работать на одном iPhone пользователя. Удалены: расшифровка App Store-приложений (нужен джейлбрейк-телефон/сервер), облачная подпись, серверное автообновление EnSign, Companion/Watch/TV/Vision, Web Manager для ПК, Premium-бэкенд, AltDaemon и AltPlugin, разделы AltServer-Linux, althea, «Десктоп и CLI» (Impactor, iloader, Sideloader, iPASide, altsign-cli, ipashare). Вкладка App Store осталась только как поиск и скачивание зашифрованного IPA без расшифровки — подумать, нужна ли она вообще.

Что делать дальше (предлагаю порядок)

