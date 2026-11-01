# TODO — уникальные фичи из каждого проекта ([x] — готово в App/, включая то, что уже было в Feather)

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
- [x] 🟢 Hex-редактор файлов внутри IPA (`HexEditorView`)
- [x] 🟢 Редактор plist (`PlistEditorView`) и текстовый редактор (`TextEditorView`) в файловом менеджере
- [x] 🟢 Встроенный менеджер файлов с QuickLook, превью изображений, экспортом (`FilesView`, `FilesViewModel`)
- [x] 🟢 Встроенный WebView-загрузчик IPA со страниц (`WebViewSheet`, `DownloaderView`, `IPADownloadManager`)
- [ ] 🟢 Менеджер распаковки архивов с прогрессом (`ExtractManager`, `ExtractionService`)
- [ ] 🔧 Массовая установка с превью и прогрессом (`BulkInstallPreviewView`, `BulkInstallProgressView`, `BulkSigningView`)
- [x] 🟢 Экран управления dylib приложения (`DylibsView`)
- [x] 🟢 Окно логов с историей (`LogsManager`, `LogsView`)
- [x] 🟢 Выбор акцентного цвета (`AccentColorManager`)
- [ ] 🔧 «Server Pack» — формат раздачи SSL-/сертификатных наборов для OTA-установки (`ServerPackModel`)
- [ ] 🔧 Отдельный «Appstore»-таб, выделенный из общих Sources

### BatSign (8yy)
- [ ] 🔧 Автообновление в фоне: расписание (час…сутки), только Wi-Fi, ночное окно, «пропустить версию», «заморозить обновления», тихая установка через туннель (`AutoUpdateManager`, `BSBackgroundTasks`, `BSContinuedProcessing`) — *частично: фоновая проверка + уведомления (BTBBackgroundRefresh), без тихой установки*
- [ ] 🔧 Live Activity / Dynamic Island с прогрессом, скоростью и ETA (`LiveActivityController`, `BatSignLiveActivity`, `DownloadActivityAttributes`)
- [ ] 🔧 Serial-очередь подписи и «Pending Sign» (`BSPendingSign`, `BSBulkSign`, `AutoSignManager`)
- [ ] 🔧 Self-Heal: обнаружить отозванный сертификат и автоматически переподписать приложения лучшим живым (`CertHealthView`)
- [x] 🟢 Дашборд здоровья сертификатов: кольца срока, статус отзыва, «Renew All»
- [x] 🔧 Install Ledger / Install Watcher: журнал установок и отслеживание, что приложение реально установилось (`BSInstallLedger`, `BSInstallWatcher`)
- [ ] 🔧 Download Rescue — дозагрузка после обрыва (`DownloadRescue`)
- [ ] 🟢 Поиск приложения через App Store lookup (`AppStoreLookup`) и показ значка/скриншотов (`BSArtwork`, `BSShotCache`)
- [x] 🟢 Shortcuts / App Intents для подписи (`SignIntents`)
- [x] 🟢 Экраны Storage, Activity log, Backup/Restore, Discover, Updates, Tweak Vault
- [ ] 🟢 Tweak Vault: сохранённые .deb/.dylib, внедрение в один тап
- [ ] 🟢 Определение устройства через MobileGestalt (`MobileGestalt`)
- [ ] 🟢 «One View Install» — установка и подпись на одном экране (`OneViewInstallView`)
- [x] 🟢 Настраиваемая компрессия при упаковке (`CompressionMode`)

### SignOs (ihateios)
Пересекается с BatSign. Отличается набором:
- [x] 🟢 App Cloner — два аккаунта одного приложения рядом
- [x] 🟢 PPQ protection, патч Liquid Glass, смена внешнего вида, minimum iOS version
- [ ] 🟢 `SearchView` — отдельный глобальный поиск
- [x] 🟢 ElleKit для инъекции твиков в расширения, управление существующими dylib/frameworks

### VexSign (raynmahbub) — самый большой, 554 файла
**Подпись и установка**
- [x] 🔧 Пакетная подпись и очереди установки с настройками для каждого приложения (`BatchSignView`, `BatchJobRunner`, `InstallQueue`)
- [x] 🟢 Именованные профили подписи / пресеты (`NamedSigningProfileStore`, `SigningProfileStore`)
- [x] 🟢 Preflight перед подписью и перед установкой (`PreflightChecks`, `InstallPreflight`, `NestedBundleAudit`, `ProfileCompatibility`)
- [x] 🟢 Редактор entitlements с билдером (`EntitlementBuilder`, `SigningEntitlementsEditorView`) и чтением из Mach-O (`MachOEntitlements`)
- [x] 🔧 Локальный HTTPS для `itms-services` со своим CA/TLS (`LocalCAProfile`, `LocalTLSIdentity`, `OTAExporter`)
- [x] 🔧 Установка через AFC / installd на спаренном устройстве (`DirectInstaller`)
- [ ] 🟢 Проверка сигнатур и целостности скачанного (`SignatureVerifier`, `DownloadIntegrity`, `BundleSignature`)
- [x] 🟢 OCSP-проверка с верификацией респондера (`OCSP`, `OCSPResponderVerification`)
- [x] 🟢 Mach-O thinning — удаление лишних архитектур
- [x] 🟢 Диагностика устройства и экспорт диагностического бандла с редакцией секретов (`DiagnosticBundleExporter`, `LogRedaction`)

**Редактирование IPA и твики**
- [ ] 🔧 IPA Explorer: просмотр содержимого, правка Info.plist, файлов, изображений, журнал изменений, plist-diff (`IPAExplorerView`, `IPAChangeJournal`, `PlistDiff`)
- [x] 🟢 Clone Wizard — 1–20 нумерованных клонов, бейдж на иконке
- [ ] 🔧 Менеджер твиков: анализ зависимостей, замена Substrate на ElleKit, репозитории твиков (`TweakAnalyzer`, `TweakExtractor`, `TweakRepository`)
- [x] 🟢 Файловый менеджер со сжатием, перемещением, QuickLook

**Источники и обновления**
- [ ] 🔧 Offline-каталог источников, условная синхронизация по ETag/Last-Modified, сохранение last-known-good (`RepositorySnapshotCache`, `RepositorySyncEngine`)
- [x] 🟢 Дашборд здоровья источников, приоритеты источников, дедупликация по bundle ID (`SourceHealthDashboardView`, `SourcePriorityView`)
- [x] 🟢 Политика URL (HTTPS-only, opt-in для локального HTTP) (`SourceURLPolicy`)
- [x] 🟢 Правила обновления для каждого приложения: игнор версии, закрепление сертификата, сохранение опций (`PerAppUpdateRules`)
- [ ] 🔧 Repository Builder — создание/редактирование/экспорт своих AltStore-репозиториев (`RepositoryBuilderView`, `RepositoryExporter`, `RepositoryValidator`)
- [ ] 🟢 Discovery: избранное, категории, коллекции, локальный тренд
- [x] 🟢 Выбор версии приложения из нескольких источников (`AllVersionsView`)
- [x] 🟢 Самообновление приложения (`SelfUpdateManager`)

**Экосистема и платформы**
- [ ] 🟢 Браузер IPSW (`IPSWBrowser`)
- [x] 🟢 Game Mode, ProMotion, JIT-настройки, симулятор геолокации (`GameMode`, `JITSettingsView`, `LocationSimulatorSettingsView`)
- [x] 🟢 App Lock (Face ID / пароль на приложение) (`AppLockManager`)
- [x] 🟢 Шифрованный бэкап/восстановление (`BackupCrypto`, `BackupManager`)
- [x] 🟢 Очистка временных файлов и истории (`CleanupManager`, `TempStorageSweeper`)
- [ ] 🟢 Task Center — единый экран фоновых задач (`UnifiedTaskCenter`)
- [ ] 🟢 Парсер Telegram-ссылок (`TelegramLinkParser`)
- [ ] ⚠️ Anti-Revoke через DNS-профиль (`AntiRevokeManager`) — профиль не может «разотозвать» сертификат, и это обход проверки Apple
- [ ] ⚠️ Подбор пароля p12 по словарю/PIN (`P12Cracker`) — обычно для чужих сертификатов; допустимо только как «восстановить свой»
- [ ] ⚠️ Каталог бесплатных сертификатов из внешнего API (`NexCerts`, `CommunityCertificatesView`) — утечки/слитые сертификаты, быстро отзываются

### EnSign (cc158999) — исходников нет, только docs
- [x] 🟢 Режимы «Ad-hoc» и «Modify only, don't sign»
- [x] 🟢 Вывод в TIPA (для TrollStore)
- [x] 🟢 Шаблон имени выходного файла + метка времени, APFS-клонирование при упаковке
- [x] 🟢 Keychain Isolation (раздельные access groups у подписанных приложений)
- [x] 🟢 Fix White Icon / Fix Dark Icon (`UIPrerenderedIcon`)
- [x] 🟢 Структурированный лог подписи с таймингами, экспорт одним тапом
- [x] 🟢 Расширенный URL-scheme (`source/`, `install/`, `import-certificate`)
- [ ] 🟢 Локализации: zh-Hans / zh-Hant / en / vi

### ForgeSign-iOS (Mesutcydev)
- [x] 🔧 Установка через loopback HTTP-сервер + удалённый HTTPS-манифест (`LocalInstallServer`, `InstallKeepAlive`)
- [x] 🟢 Запомненные сертификаты с обратным отсчётом срока и хранением пароля в Keychain
- [ ] 🟢 Библиотека подписанных приложений со статусами signed / installing / delivered / installed / missing
- [x] 🟢 IPA preflight (шифрование, архитектура) и аудит профилей по каждому bundle/extension
- [ ] 🔧 Провижининг через Apple ID прямо на устройстве, с патчем GSA (`altsign-gsa-http503.patch`)
- [x] 🟢 Дизайн Liquid Glass с fallback на iOS 16

### ABox (SWING1993)
- [x] 🟢 Просмотр p12 и mobileprovision (поля, сроки)
- [ ] 🔧 Class-dump заголовков из Mach-O прямо на устройстве
- [x] 🟢 Инъекция и удаление dylib через optool
- [ ] 🟢 Поддержка iOS 12+ (самая старая цель среди всех)
- [x] 🟢 Парсинг веб-страницы в поисках ссылки на IPA

### TanaraSign (iRayanKhan) — по README

### ProStore / ProSign (ProStore-iOS) — заброшены
- [ ] 🟢 Загрузчик «официальных» сертификатов (`OfficialCertsDownloader`) ⚠️ та же оговорка, что у NexCerts
- [x] 🟢 Проверка сертификата (`certChecker`)
- [ ] 🟢 Сравнительная таблица возможностей в README как формат документации

---

## Сайдлоадеры с Apple ID (AltStore-семейство)

### AltStore (altstoreio)
- [ ] 🔧 AltJIT — включение JIT и монтирование DDI из демона (`AltJIT/Commands`)
- [ ] 🔧 AltMarketplace — установка через EU Digital Markets Act (`InstallAppRequest`)
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

---

## Нижний уровень

### zsign (zhlynn)
Флаги, которые стоит перенять, если нет:
- [ ] 🟢 `-L` dual SHA1+SHA256 CodeDirectory (iOS ≤ 10)
- [x] 🟢 `-C` проверка сертификата и OCSP
- [ ] 🟢 `-x` извлечение метаданных и иконки
- [x] 🟢 `-S` включить file sharing, `-M` min version, `-E` удалить extensions, `-W` удалить Watch, `-U` удалить UISupportedDevices
- [x] 🟢 `-P` инъекция dylib также в расширения, `-w` weak-инъекция, `-D` удаление dylib, `-I` замена иконки, `-z` уровень сжатия

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
- [x] 🟢 Режим «экспортировать твикнутый IPA» без установки; режим «ad-hoc подпись»
- [x] 🟢 Инъекция `.dylib`, `.deb`, `.framework` и `.bundle` одновременно, с поддержкой Cydia Substrate и Substitute
- [x] 🟢 Удаление всех или части app extensions (PlugIns) перед установкой
- [x] 🟢 «Remove restrictions» — снятие ограничений IPA на поддерживаемых устройствах
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
- [x] 🟢 Только .p12 + .mobileprovision, без входа через Apple ID (так проще и безопаснее по данным)

### ESign (Н; С — VexSign умеет читать зашифрованные источники ESign)
- [x] 🔧 Формат зашифрованных ESign-источников (есть парсер в `raynmahbub_VexSign`, см. AltSourceKit)
- [x] 🟢 Установка через `itms-services` без ПК (по таблице в README ProStore)
- [x] 🟢 Инъекция dylib в IPA
- [ ] 🟢 Известный баг: ESign портит entitlements (из заметок iDevice Toolkit) — в нашей версии на это нужен тест

### Scarlet (Н; официальный README недоступен)
- [ ] 🔧 Четыре способа установки самого приложения: direct (enterprise), computer, developer, TrollStore ⚠️ enterprise-способ
- [ ] 🔧 Подключение Cydia/jailbreak-репозиториев на устройстве без джейлбрейка
- [ ] 🟢 Свой «родной» формат репозиториев поверх AltStore-совместимых
- [ ] 🟢 Режим «Modify IPA» — вставка и удаление твиков

## Новое от пользователя: вкладка App Store + функции Telegram-бота

Источник: список команд `/help` бота (твики применяются к IPA конвейером `.cyan`). Что делает каждая команда, знаем **только по названию** — перед реализацией проверять.

### Вкладка «Download from App Store»
- [ ] 🔧 Вкладка, куда вставляется ссылка на App Store / bundle ID / track ID, плюс поиск по названию (публичный iTunes Search/Lookup API, работает и для малоизвестных приложений с единичными скачиваниями)
- [ ] 🔧 Скачивание IPA через Apple ID пользователя (подход ipatool: авторизация, получение лицензии, ссылка на загрузку, 2FA)
- [ ] ⚠️ Только для приложений, доступных этому Apple ID (бесплатные или купленные). Скачивание платных приложений без покупки — пиратство, не реализуем

### Функции бота (твики к IPA)
- [ ] 🟢 `/noads` — No Ads (блокировка рекламы твиком)
- [ ] 🔧 `/sideload` — Sideload Fixers (исправления того, что ломается после пересборки/переподписи: keychain, app groups, push и т.п.)
- [ ] 🟢 `/nowifi` — Network Blocker (запрет сети для приложения)
- [ ] 🔧 `/backup` — Data Manager (резервная копия и восстановление данных приложения)
- [ ] 🟢 `/norev` — RateBeGone (подавление запросов оценки приложения)
- [ ] 🟢 `/ipadui` — iPadUI (интерфейс iPad на iPhone)
- [ ] 🟢 `/noupd` — Bypass Updates (обход принудительных проверок обновления)
- [ ] 🔧 `/patch` — Plugin Fixes (исправления для твиков/плагинов)
- [ ] 🟢 `/custom` — собственный `.cyan`-файл (вложением или по URL)
- [ ] 🔧 `/cgen` — генерация `.cyan` из `.deb`/`.dylib`
- [ ] 🟢 UX: ответ командой на IPA-файл; несколько команд в одном сообщении применяются вместе (пример `/iap /rc`)
- [ ] ⚠️ `/iap` — Satella и `/rc` — Auto RevenueCat: по назначению обходят внутренние покупки и подписки (RevenueCat — сервис проверки подписок). Это обход оплаты. **Не реализуем**; оставлены в списке только чтобы не потерять контекст

## Выбор версии по источникам и контроль памяти (запрос пользователя)

### Автовыбор источника по самой новой версии
- [x] 🔧 Поиск приложения (по названию или bundle ID) сразу по **всем источникам, которые добавил сам пользователь** (AltStore-совместимые репозитории); в нескольких источниках одно приложение группируется по bundle ID
- [x] 🟢 По умолчанию скачивается источник с **наибольшей версией** (сравнение версий по правилам semver/числовых сегментов; при равенстве — более свежая дата, затем приоритет источника); пользователь может выбрать другой вручную
- [x] 🟢 Показывать, из какого источника и какая версия выбрана и почему; запоминать ручной выбор для приложения
- [x] 🟢 Основа в коде: VexSign `AllVersionsView`, `SourcePriorityView`, `SourceProvenance`, `PerAppUpdateRules`, `UpdateMatchingPreferences`
- [ ] ⚠️ **Решение пользователя/ограничение:** встроенного списка репозиториев «со всеми расшифрованными приложениями» нет и не будет. Модель отказалась искать и подключать массовые подборки расшифрованных копий чужих приложений (нелегальное распространение). Источники добавляет только сам пользователь

### Гибкий контроль памяти (без переустановки)
- [x] 🔧 Экран «Хранилище»: размер по категориям — скачанные IPA, подписанные IPA, временные/распакованные файлы, кэш иконок и скриншотов, логи, резервные копии, снимки источников, хранилище твиков
- [x] 🟢 Выборочная очистка: целиком категорию, отдельный файл или приложение; предпросмотр «сколько освободится» до удаления и подтверждение
- [x] 🟢 **Защищённый набор, который очистка не трогает:** сертификаты (.p12, .mobileprovision, пароли в Keychain), список источников и настройки, файлы, нужные для работы приложения. Защита на уровне кода, а не только скрытие в интерфейсе
- [x] 🟢 Правила автоочистки (по возрасту, по лимиту размера, после успешной установки) — по желанию пользователя
- [x] 🟢 Основа в коде: VexSign `CleanupManager`, `CleanupView`, `StorageManager`, `TempStorageSweeper`; BatSign/SignOs `StorageView`; Ksign `FilesView`


> **Ограничение пользователя:** в проекте не должно быть пунктов, которым нужен другой iPhone, ПК/Mac, свой сервер, часы/ТВ/Vision или расшифровка на отдельном устройстве. Всё должно работать на одном iPhone пользователя. Удалены: расшифровка App Store-приложений (нужен джейлбрейк-телефон/сервер), облачная подпись, серверное автообновление EnSign, Companion/Watch/TV/Vision, Web Manager для ПК, Premium-бэкенд, AltDaemon и AltPlugin, разделы AltServer-Linux, althea, «Десктоп и CLI» (Impactor, iloader, Sideloader, iPASide, altsign-cli, ipashare). Вкладка App Store осталась только как поиск и скачивание зашифрованного IPA без расшифровки — подумать, нужна ли она вообще.

## Что делать дальше (предлагаю порядок)
1. Выбрать базу: сейчас по охвату сильнее всего VexSign, по чистоте кода — Feather / Ksign / BatSign.
2. Отдельно решить по пунктам с ⚠️: включать ли их вообще.
3. Начать с 🟢-пунктов в Feather-семействе (в основном перенос), затем 🔧 по приоритету.
