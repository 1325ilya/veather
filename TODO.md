# TODO — уникальные фичи из каждого проекта (только план, ничего не реализовано)

Метод: сравнивались README и список исходных файлов. Для семейства Feather (Feather → Ksign / BatSign / SignOs / VexSign / ProStore) сравнивался diff по именам файлов относительно Feather. Глубокого чтения кода каждой фичи не было, поэтому перед реализацией нужно открыть соответствующий файл и подтвердить.

Легенда: 🔧 сложно · 🟢 просто · ⚠️ юридический риск или риск нарушить правила Apple (решить отдельно, прежде чем брать)

Примечания:
- **Feather** — база. Форки почти всегда его надмножество, своих уникальных фич у него нет (`certcheck.cpp` и `metadata.cpp` теперь есть и в upstream zsign).
- **SignOs** — почти копия BatSign без части модулей (см. ниже), отдельной уникальности у него мало.
- **TanaraSign** — в репозитории только готовые `.ipa` и README, исходников нет, анализировать код нельзя. Идеи взяты только из README.
- **ProStore / ProSign** — заброшены (README пишет, что установка не работает). Уникальное только в идеях.

---

## Feather-семейство (on-device подписчики)

### Ksign (Nyasami)
- [ ] 🟢 Hex-редактор файлов внутри IPA (`HexEditorView`)
- [ ] 🟢 Редактор plist (`PlistEditorView`) и текстовый редактор (`TextEditorView`) в файловом менеджере
- [ ] 🟢 Встроенный менеджер файлов с QuickLook, превью изображений, экспортом (`FilesView`, `FilesViewModel`)
- [ ] 🟢 Встроенный WebView-загрузчик IPA со страниц (`WebViewSheet`, `DownloaderView`, `IPADownloadManager`)
- [ ] 🟢 Менеджер распаковки архивов с прогрессом (`ExtractManager`, `ExtractionService`)
- [ ] 🔧 Массовая установка с превью и прогрессом (`BulkInstallPreviewView`, `BulkInstallProgressView`, `BulkSigningView`)
- [ ] 🟢 Экран управления dylib приложения (`DylibsView`)
- [ ] 🟢 Окно логов с историей (`LogsManager`, `LogsView`)
- [ ] 🟢 Выбор акцентного цвета (`AccentColorManager`)
- [ ] 🔧 «Server Pack» — формат раздачи SSL-/сертификатных наборов для OTA-установки (`ServerPackModel`)
- [ ] 🔧 Отдельный «Appstore»-таб, выделенный из общих Sources

### BatSign (8yy)
- [ ] 🔧 Автообновление в фоне: расписание (час…сутки), только Wi-Fi, ночное окно, «пропустить версию», «заморозить обновления», тихая установка через туннель (`AutoUpdateManager`, `BSBackgroundTasks`, `BSContinuedProcessing`)
- [ ] 🔧 Live Activity / Dynamic Island с прогрессом, скоростью и ETA (`LiveActivityController`, `BatSignLiveActivity`, `DownloadActivityAttributes`)
- [ ] 🔧 Serial-очередь подписи и «Pending Sign» (`BSPendingSign`, `BSBulkSign`, `AutoSignManager`)
- [ ] 🔧 Self-Heal: обнаружить отозванный сертификат и автоматически переподписать приложения лучшим живым (`CertHealthView`)
- [ ] 🟢 Дашборд здоровья сертификатов: кольца срока, статус отзыва, «Renew All»
- [ ] 🔧 Install Ledger / Install Watcher: журнал установок и отслеживание, что приложение реально установилось (`BSInstallLedger`, `BSInstallWatcher`)
- [ ] 🔧 Download Rescue — дозагрузка после обрыва (`DownloadRescue`)
- [ ] 🟢 Поиск приложения через App Store lookup (`AppStoreLookup`) и показ значка/скриншотов (`BSArtwork`, `BSShotCache`)
- [ ] 🟢 Shortcuts / App Intents для подписи (`SignIntents`)
- [ ] 🟢 Экраны Storage, Activity log, Backup/Restore, Discover, Updates, Tweak Vault
- [ ] 🟢 Tweak Vault: сохранённые .deb/.dylib, внедрение в один тап
- [ ] 🟢 Определение устройства через MobileGestalt (`MobileGestalt`)
- [ ] 🟢 «One View Install» — установка и подпись на одном экране (`OneViewInstallView`)
- [ ] 🟢 Настраиваемая компрессия при упаковке (`CompressionMode`)

### SignOs (ihateios)
Пересекается с BatSign. Отличается набором:
- [ ] 🟢 App Cloner — два аккаунта одного приложения рядом
- [ ] 🟢 PPQ protection, патч Liquid Glass, смена внешнего вида, minimum iOS version
- [ ] 🟢 `SearchView` — отдельный глобальный поиск
- [ ] 🟢 ElleKit для инъекции твиков в расширения, управление существующими dylib/frameworks

### VexSign (raynmahbub) — самый большой, 554 файла
**Подпись и установка**
- [ ] 🔧 Пакетная подпись и очереди установки с настройками для каждого приложения (`BatchSignView`, `BatchJobRunner`, `InstallQueue`)
- [ ] 🟢 Именованные профили подписи / пресеты (`NamedSigningProfileStore`, `SigningProfileStore`)
- [ ] 🟢 Preflight перед подписью и перед установкой (`PreflightChecks`, `InstallPreflight`, `NestedBundleAudit`, `ProfileCompatibility`)
- [ ] 🟢 Редактор entitlements с билдером (`EntitlementBuilder`, `SigningEntitlementsEditorView`) и чтением из Mach-O (`MachOEntitlements`)
- [ ] 🔧 Локальный HTTPS для `itms-services` со своим CA/TLS (`LocalCAProfile`, `LocalTLSIdentity`, `OTAExporter`)
- [ ] 🔧 Установка через AFC / installd на спаренном устройстве (`DirectInstaller`)
- [ ] 🟢 Проверка сигнатур и целостности скачанного (`SignatureVerifier`, `DownloadIntegrity`, `BundleSignature`)
- [ ] 🟢 OCSP-проверка с верификацией респондера (`OCSP`, `OCSPResponderVerification`)
- [ ] 🟢 Mach-O thinning — удаление лишних архитектур
- [ ] 🔧 Облачная подпись как опциональный бэкенд (`CloudSigningClient`, `CloudSigningView`)
- [ ] 🟢 Диагностика устройства и экспорт диагностического бандла с редакцией секретов (`DiagnosticBundleExporter`, `LogRedaction`)

**Редактирование IPA и твики**
- [ ] 🔧 IPA Explorer: просмотр содержимого, правка Info.plist, файлов, изображений, журнал изменений, plist-diff (`IPAExplorerView`, `IPAChangeJournal`, `PlistDiff`)
- [ ] 🟢 Clone Wizard — 1–20 нумерованных клонов, бейдж на иконке
- [ ] 🔧 Менеджер твиков: анализ зависимостей, замена Substrate на ElleKit, репозитории твиков (`TweakAnalyzer`, `TweakExtractor`, `TweakRepository`)
- [ ] 🟢 Файловый менеджер со сжатием, перемещением, QuickLook

**Источники и обновления**
- [ ] 🔧 Offline-каталог источников, условная синхронизация по ETag/Last-Modified, сохранение last-known-good (`RepositorySnapshotCache`, `RepositorySyncEngine`)
- [ ] 🟢 Дашборд здоровья источников, приоритеты источников, дедупликация по bundle ID (`SourceHealthDashboardView`, `SourcePriorityView`)
- [ ] 🟢 Политика URL (HTTPS-only, opt-in для локального HTTP) (`SourceURLPolicy`)
- [ ] 🟢 Правила обновления для каждого приложения: игнор версии, закрепление сертификата, сохранение опций (`PerAppUpdateRules`)
- [ ] 🔧 Repository Builder — создание/редактирование/экспорт своих AltStore-репозиториев (`RepositoryBuilderView`, `RepositoryExporter`, `RepositoryValidator`)
- [ ] 🟢 Discovery: избранное, категории, коллекции, локальный тренд
- [ ] 🟢 Выбор версии приложения из нескольких источников (`AllVersionsView`)
- [ ] 🟢 Самообновление приложения (`SelfUpdateManager`)

**Экосистема и платформы**
- [ ] 🔧 Приложения для Apple Watch / Apple TV / Vision Pro + виджеты и complications (`VexSignWatchApp`, `VexSignTVApp`, `VexSignVisionApp`, виджеты)
- [ ] 🔧 Companion-мост между устройствами (`CompanionBridge`, `CompanionClient`)
- [ ] 🔧 Web Manager: HTTP- и WebDAV-сервер на устройстве, чтобы управлять файлами с ПК (`WebManagerServer`, `+WebDAV`)
- [ ] 🟢 Браузер IPSW (`IPSWBrowser`)
- [ ] 🟢 Game Mode, ProMotion, JIT-настройки, симулятор геолокации (`GameMode`, `JITSettingsView`, `LocationSimulatorSettingsView`)
- [ ] 🟢 App Lock (Face ID / пароль на приложение) (`AppLockManager`)
- [ ] 🟢 Шифрованный бэкап/восстановление (`BackupCrypto`, `BackupManager`)
- [ ] 🟢 Очистка временных файлов и истории (`CleanupManager`, `TempStorageSweeper`)
- [ ] 🟢 Task Center — единый экран фоновых задач (`UnifiedTaskCenter`)
- [ ] 🟢 Парсер Telegram-ссылок (`TelegramLinkParser`)
- [ ] ⚠️ Anti-Revoke через DNS-профиль (`AntiRevokeManager`) — профиль не может «разотозвать» сертификат, и это обход проверки Apple
- [ ] ⚠️ Подбор пароля p12 по словарю/PIN (`P12Cracker`) — обычно для чужих сертификатов; допустимо только как «восстановить свой»
- [ ] ⚠️ Каталог бесплатных сертификатов из внешнего API (`NexCerts`, `CommunityCertificatesView`) — утечки/слитые сертификаты, быстро отзываются
- [ ] ⚠️ «Premium»-активация через backend (`PremiumManager`)

### EnSign (cc158999) — исходников нет, только docs
- [ ] 🔧 Серверное «обновление в один тап» с автоподбором исходного сертификата (нужен свой бэкенд)
- [ ] 🟢 Режимы «Ad-hoc» и «Modify only, don't sign»
- [ ] 🟢 Вывод в TIPA (для TrollStore)
- [ ] 🟢 Шаблон имени выходного файла + метка времени, APFS-клонирование при упаковке
- [ ] 🟢 Keychain Isolation (раздельные access groups у подписанных приложений)
- [ ] 🟢 Fix White Icon / Fix Dark Icon (`UIPrerenderedIcon`)
- [ ] 🟢 Структурированный лог подписи с таймингами, экспорт одним тапом
- [ ] 🟢 Расширенный URL-scheme (`source/`, `install/`, `import-certificate`)
- [ ] 🟢 Локализации: zh-Hans / zh-Hant / en / vi

### ForgeSign-iOS (Mesutcydev)
- [ ] 🔧 Установка через loopback HTTP-сервер + удалённый HTTPS-манифест (`LocalInstallServer`, `InstallKeepAlive`)
- [ ] 🟢 Запомненные сертификаты с обратным отсчётом срока и хранением пароля в Keychain
- [ ] 🟢 Библиотека подписанных приложений со статусами signed / installing / delivered / installed / missing
- [ ] 🟢 IPA preflight (шифрование, архитектура) и аудит профилей по каждому bundle/extension
- [ ] 🔧 Провижининг через Apple ID прямо на устройстве, с патчем GSA (`altsign-gsa-http503.patch`)
- [ ] 🟢 Дизайн Liquid Glass с fallback на iOS 16

### ABox (SWING1993)
- [ ] 🟢 Просмотр p12 и mobileprovision (поля, сроки)
- [ ] 🔧 Class-dump заголовков из Mach-O прямо на устройстве
- [ ] 🟢 Инъекция и удаление dylib через optool
- [ ] 🟢 Поддержка iOS 12+ (самая старая цель среди всех)
- [ ] 🟢 Парсинг веб-страницы в поисках ссылки на IPA

### TanaraSign (iRayanKhan) — по README
- [ ] 🔧 Клиенты для watchOS, tvOS, visionOS, macOS: поиск приложений на часах/ТВ и отправка на iPhone
- [ ] 🟢 Установка на Apple Vision Pro

### ProStore / ProSign (ProStore-iOS) — заброшены
- [ ] 🟢 Загрузчик «официальных» сертификатов (`OfficialCertsDownloader`) ⚠️ та же оговорка, что у NexCerts
- [ ] 🟢 Проверка сертификата (`certChecker`)
- [ ] 🟢 Сравнительная таблица возможностей в README как формат документации

---

## Сайдлоадеры с Apple ID (AltStore-семейство)

### AltStore (altstoreio)
- [ ] 🔧 AltJIT — включение JIT и монтирование DDI из демона (`AltJIT/Commands`)
- [ ] 🔧 AltDaemon / AltXPC — привилегированный демон для jailbroken-устройств
- [ ] 🔧 AltMarketplace — установка через EU Digital Markets Act (`InstallAppRequest`)
- [ ] 🔧 AltPlugin — плагин для Apple Mail, отдающий anisette (`ALTPluginService`)
- [ ] 🟢 Виджеты (`AltWidget`), новости в приложении (`News`), Fediverse-интеграция
- [ ] 🟢 Каналы разрешений приложения (`Permissions`) и превью

### SideStore
- [ ] 🔧 Установка без ПК через em_proxy + minimuxer (локальный VPN-туннель) — главная фича
- [ ] 🟢 Выбор anisette-сервера и список серверов (`AnisetteServerList`)
- [ ] 🟢 Журнал попыток обновления (`RefreshAttemptsViewController`)
- [ ] 🟢 SideBackup, trustedapps.json (доверенные источники)
- [ ] 🟢 Файлы для AI-агентов (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`) — формат документации для контрибьюторов

### apple-private-apis (SideStore)
- [ ] 🔧 `omnisette` — генерация anisette на Rust
- [ ] 🔧 `icloud-auth` — вход в GSA
- [ ] 🔧 `apple-dev-apis` — Xcode developer API
- [ ] 🔧 `apple-codesign-wrapper` — обёртка над `apple-codesign` (подпись без OpenSSL/zsign)

### AltServer-Linux (NyaMisty)
- [ ] 🔧 Wi-Fi refresh через netmuxd
- [ ] 🔧 Собственный anisette-сервер (`ALTSERVER_ANISETTE_SERVER`), офлайн-генерация
- [ ] 🟢 Режим демона + CLI-установка одной командой, статический бинарь

### althea (vyvir)
- [ ] 🟢 GUI-обёртка (GTK/Python) над AltServer-Linux с иконкой в трее, хранение пароля в системном keyring
- [ ] 🟢 Поддержка x86_64 / aarch64 / armv7

---

## Десктоп и CLI-инструменты

### Impactor / PlumeImpactor (claration)
- [ ] 🔧 Rust-крейты: `plume_core` (auth, developer API v1 и qh, app groups, capabilities), `plume_store`, `plume_utils`, `plume_gestalt`
- [ ] 🟢 Нормализатор CgBI PNG (`cgbi.rs`) — иконки из iOS-сборок
- [ ] 🟢 Опции подписи: iPad fullscreen, ProMotion, Game Mode, Liquid Glass, ElleKit, удаление URL schemes, single profile
- [ ] 🟢 Разные режимы установки и `refresh` как отдельная операция
- [ ] 🟢 CLI `plumesign` рядом с GUI и 10 локалей (ar, de, en, es, fi, fr, it, ja, pl, ru)
- [ ] 🟢 Nix flake

### iloader (nab138)
- [ ] 🔧 Установка SideStore и автоматический импорт pairing-файла
- [ ] 🟢 Управление pairing-файлами для StikDebug, SideStore, Protokolle
- [ ] 🟢 Просмотр и отзыв dev-сертификатов и App ID
- [ ] 🟢 «Умные» подсказки по распространённым ошибкам
- [ ] 🟢 Tauri-приложение с защищённым хранилищем (`secure_storage.rs`)

### Sideloader (Dadoum)
- [ ] 🔧 Команда `trollsign` (метод TrollStore 2, CVE-2023-41991) ⚠️ работает только на уязвимых версиях iOS
- [ ] 🟢 Подкоманды `app-id`, `cert`, `device`, `team`, `tool`
- [ ] 🟢 Фронтенды GTK, Qt, SwiftUI, dlangui поверх общего ядра
- [ ] 🟢 Свой keyring на libsecret

### iPASide (pwnapplehat)
- [ ] 🟢 Установка Dopamine с проверкой совместимости чипа и iOS ⚠️
- [ ] 🟢 Выбор USB или Wi-Fi, фоновое автообновление (7-дневный re-sign) без запущенного приложения
- [ ] 🟢 Страница диагностики; список сертификатов Apple ID с пометкой, каким инструментом создан
- [ ] 🟢 Flutter UI + Python-движок, Windows-инсталлятор без прав администратора, светлая тема

### altsign-cli (xhzq233)
- [ ] 🟢 Одна сессия с кешем; пароль и 2FA только через stdin
- [ ] 🟢 Принимает `.app` без упаковки, а не только IPA
- [ ] 🟢 Встроенная диагностика и remote anisette
- [ ] 🟢 `SKILL.md` — описание инструмента для AI-агентов

### ipashare (togettoyou)
- [ ] 🔧 Серверная раздача: загрузка IPA, Ad Hoc-подпись, QR-код/ссылка
- [ ] 🔧 Автоматическая регистрация UDID устройств через App Store Connect API (ключ .p8)
- [ ] 🟢 Docker-деплой, Swagger-документация, веб-админка

---

## Нижний уровень

### zsign (zhlynn)
Флаги, которые стоит перенять, если нет:
- [ ] 🟢 `-L` dual SHA1+SHA256 CodeDirectory (iOS ≤ 10)
- [ ] 🟢 `-C` проверка сертификата и OCSP
- [ ] 🟢 `-x` извлечение метаданных и иконки
- [ ] 🟢 `-S` включить file sharing, `-M` min version, `-E` удалить extensions, `-W` удалить Watch, `-U` удалить UISupportedDevices
- [ ] 🟢 `-P` инъекция dylib также в расширения, `-w` weak-инъекция, `-D` удаление dylib, `-I` замена иконки, `-z` уровень сжатия

### ldid (ProcursusTeam)
- [ ] 🟢 PKCS#11-ключи (токены, HSM)
- [ ] 🟢 p12 с паролем + OpenSSL 3
- [ ] 🟢 Флаг `-arch`, man-страницы (en / zh_TW / zh_CN)

### TrollStore (opa334)
- [ ] 🔧 Постоянная установка через баг CoreTrust, `.tipa` ⚠️ только iOS 14.0–17.0
- [ ] 🔧 Persistence Helper и RootHelper (uicache, devmode, JIT)
- [ ] 🟢 URL-scheme `apple-magnifier://install?url=` и `enable-jit`
- [ ] 🟢 Произвольные entitlements через fakesign (ldid)
- [ ] 🟢 Сборка TrollStoreLite

### ios-app-signer (DanTheMan827)
- [ ] 🟢 Входные форматы: ipa, deb, app, xcarchive
- [ ] 🟢 Подпись macOS-приложением через Xcode-toolchain (альтернатива zsign)

---

## Закрытые проекты (исходников нет — по публичным описаниям)

Уверенность: **В** — подтверждено официальной страницей/README, **Н** — только сторонние сайты (часто SEO-мусор), **С** — видно по коду другого проекта в этой коллекции. Перед реализацией проверять на самом приложении.

### Sideloadly (В — sideloadly.io)
- [ ] 🟢 Режим «экспортировать твикнутый IPA» без установки; режим «ad-hoc подпись»
- [ ] 🟢 Инъекция `.dylib`, `.deb`, `.framework` и `.bundle` одновременно, с поддержкой Cydia Substrate и Substitute
- [ ] 🟢 Удаление всех или части app extensions (PlugIns) перед установкой
- [ ] 🟢 «Remove restrictions» — снятие ограничений IPA на поддерживаемых устройствах
- [ ] 🟢 URI-схема для установки IPA с веб-страницы
- [ ] 🟢 Доступ к документам приложения и системные логи устройства прямо из программы
- [ ] 🟢 Режим «скрыть чувствительные данные» (для скриншотов и записи экрана)
- [ ] 🟢 Сохранение Apple ID-учётки для быстрой повторной подписи
- [ ] 🔧 JIT-включение для iOS ≤ 16

### GBox (Н — сторонний каталог senumy.com, официальный сайт не найден)
- [ ] 🟢 Встроенные каталоги IPA по категориям: jailbreak-инструменты, твикнутые приложения, эмуляторы
- [ ] 🟢 Выбор «свой сертификат или общий (global)» в одном приложении
- [ ] ⚠️ Вариант с «бесплатным enterprise-сертификатом» в комплекте — общий сертификат, быстро отзывается
- [ ] 🟢 Отдельная сборка под TrollStore (установка без сертификата)
- [ ] 🟢 Только .p12 + .mobileprovision, без входа через Apple ID (так проще и безопаснее по данным)

### ESign (Н; С — VexSign умеет читать зашифрованные источники ESign)
- [ ] 🔧 Формат зашифрованных ESign-источников (есть парсер в `raynmahbub_VexSign`, см. AltSourceKit)
- [ ] 🟢 Установка через `itms-services` без ПК (по таблице в README ProStore)
- [ ] 🟢 Инъекция dylib в IPA
- [ ] 🟢 Известный баг: ESign портит entitlements (из заметок iDevice Toolkit) — в нашей версии на это нужен тест

### Scarlet (Н; официальный README недоступен)
- [ ] 🔧 Четыре способа установки самого приложения: direct (enterprise), computer, developer, TrollStore ⚠️ enterprise-способ
- [ ] 🔧 Подключение Cydia/jailbreak-репозиториев на устройстве без джейлбрейка
- [ ] 🟢 Свой «родной» формат репозиториев поверх AltStore-совместимых
- [ ] 🟢 Режим «Modify IPA» — вставка и удаление твиков

## Что делать дальше (предлагаю порядок)
1. Выбрать базу: сейчас по охвату сильнее всего VexSign, по чистоте кода — Feather / Ksign / BatSign.
2. Отдельно решить по пунктам с ⚠️: включать ли их вообще.
3. Начать с 🟢-пунктов в Feather-семействе (в основном перенос), затем 🔧 по приоритету.
