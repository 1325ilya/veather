# Задание для агента на macOS (сборка + симулятор)

Ты работаешь над iOS-приложением Veather — on-device подписчиком IPA на основе Feather (Swift/SwiftUI, GPL-3.0).

Репозиторий: https://github.com/1325ilya/veather
Ветка: `claude/ios-signers-collection` — работай и пушь только в неё.
Язык общения с пользователем: русский.

Сначала прочитай `AGENTS.md` в корне: там контекст, что уже сделано и что осталось (TODO). Код приложения лежит в `App/`, наш код — в `App/Feather/Veather/` (префикс `BTB`).

## Задача 1 — собрать и починить сборку

1. `git clone https://github.com/1325ilya/veather -b claude/ios-signers-collection`
   Без `--recurse-submodules`: сабмодули в `repos/` — чужие проекты для анализа, для сборки они не нужны.
2. `cd App && make`
   Makefile собирает твики (`make -C Tweaks`), потом выполняет xcodebuild с `CODE_SIGNING_ALLOWED=NO` и кладёт неподписанный IPA в `App/packages/Veather.ipa`.
   Для быстрых итераций можно сразу:
   `xcodebuild -project Feather.xcodeproj -scheme Feather -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
3. Исправь все ошибки компиляции. Большая часть нового кода ещё ни разу не компилировалась: он написан на Linux, а проверяется только через CI. Чини минимально и не меняй смысл фич.
   Известная ловушка: `Text(.localized("…", arguments: x))` не компилируется. Нужно `Text(verbatim: String.localized("…", arguments: x))`.

## Задача 2 — прогнать в симуляторе iOS 27.0

- Собери под симулятор и запусти. Пройди по экранам: Sources (все пункты сверху, включая App Store, Browser, Search All Sources, Source Health), Library, Settings (Storage, Logs, Activity, Backup, Certificate Health, Background Checks, Tweak Vault, Task Center, Repository Builder, IPSW, Device Info, Check for Updates), экран подписи (Presets, Preflight, Clones, Built-in Tweaks, Bundle Cleanup, Tweaks → .cyan).
- Чини падения и явные баги интерфейса. Если сборка под симулятор не проходит из-за бинарной зависимости без simulator-слайса (например, IDevice.xcframework), не борись с этим. Проверь сборку под generic iOS и напиши об этом в отчёте.
- Сама подпись и установка в симуляторе не работают, это нормально. Проверяй UI и логику.

## Правила

- НЕ коммить `Feather.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: стоковый вариант ломал граф пакетов Xcode. Он в `.gitignore`.
- Новые `.swift`-файлы в `App/Feather/` подхватываются автоматически (file-system synchronized groups). pbxproj без необходимости не трогай.
- Сертификаты и профили не нужны: собираем без подписи. Не проси их и не сохраняй.
- Не добавляй функции обхода отзыва сертификатов, подбора паролей p12, каталогов чужих или enterprise-сертификатов, обхода покупок и подписок, пиратских репозиториев. Это осознанное решение.
- Коммить небольшими осмысленными коммитами и пушь в `claude/ios-signers-collection`. CI (`.github/workflows/build.yml`) соберёт IPA и обновит релиз `nightly-dev`.
- Новые строки интерфейса добавляй и в `App/Feather/Resources/Localizable.xcstrings` с переводом `ru`.

## Задача 3 (если останется время)

Оставшиеся пункты из `TODO.md`, которые работают на одном iPhone. Например: категории в Discovery, глобальный поиск, политика HTTPS-only для источников, Live Activity прогресса загрузки (потребует отдельного widget-таргета, делай аккуратно). Пункты, которым нужен второй iPhone, ПК или свой сервер, и Apple ID-провижининг пропускай.

## Отчёт

В конце: что починил, что проверил в симуляторе и как, что не удалось и почему, ссылка на зелёный CI-прогон.
