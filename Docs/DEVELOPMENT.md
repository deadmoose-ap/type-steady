# Руководство разработчика

## Стек

| Область | Технология |
|---|---|
| Язык и сборка | Swift 6 toolchain, Swift Package Manager |
| Language mode | Swift 5 compatibility mode в текущем package |
| Минимальная ОС | macOS 15.0 |
| Архитектура | arm64 / Apple Silicon |
| UI | SwiftUI `NavigationSplitView` внутри AppKit lifecycle; Liquid Glass на macOS 26+ |
| Menu bar и окна | AppKit, `NSStatusItem`, `NSWindow`, `NSPanel`, `NSHostingController` |
| Наблюдаемое состояние | Combine, `ObservableObject`, `@Published` |
| Глобальный ввод | CoreGraphics `CGEventTap`, `CGEventPost` |
| Раскладки | Carbon TIS, `UCKeyTranslate` |
| Hotkeys | Carbon `RegisterEventHotKey` |
| Выделение и secure fields | ApplicationServices Accessibility API |
| Системный словарь | AppKit `NSSpellChecker` |
| Запуск при входе | ServiceManagement `SMAppService` |
| Диагностика | OSLog Unified Logging |
| Иконка | Apple Icon Composer `.icon`, `actool`, `Assets.car`, системный ICNS fallback |
| Упаковка | shell, `codesign`, `hdiutil`, `notarytool` |

Сторонних Swift packages и runtime SDK нет.

Окно настроек сохраняет deployment target macOS 15. API `glassEffect`, `.glass` и `.glassProminent` должны оставаться внутри `if #available(macOS 26.0, *)`; fallback использует только системные материалы macOS 15. В содержимом настроек не следует создавать декоративное «стекло» из ручных blur/gradient/shadow: стеклянный слой предназначен для навигации и интерактивных controls.

`swift-tools-version` равен 6.0, а targets пока используют `.swiftLanguageMode(.v5)`. Это оставляет доступным современный compiler/tooling, но снижает объём concurrency-миграции вокруг C callbacks и AppKit delegates. Переход на полный Swift 6 strict concurrency должен выполняться отдельным изменением с проверкой event tap ownership.

## Структура проекта

```text
Package.swift
Sources/TypeSteadyApp/
  Accessibility/   AX selected text и secure element
  Core/            модели и автономный self-test
  Correction/      транзакция замены и CGEvent emitter
  Detection/       lexicon, spell checker, scorer, transliteration
  Input/           event tap, coordinator, state machine
  Layout/          TIS snapshots и selection converter
  Resources/       локальные словари
  System/          settings, permissions, hotkeys, login item, policy, logger
  UI/              menu bar, settings, overlay
  AppDelegate.swift
  Main.swift
Tests/              Swift Testing suites
Support/            Info.plist и entitlements
Scripts/            verify, build, DMG, privacy, notarization
Docs/               продуктовая и техническая документация
```

## Основные паттерны

### Coordinator

`InputCoordinator` связывает ввод, раскладки, detection, correction и AX-command, но низкоуровневые детали делегирует сервисам. `CorrectionCoordinator` инкапсулирует порядок транзакции.

### Конечный автомат

`TypingStateMachine` является value type и моделирует слово явными переходами. Это позволяет тестировать пробел, punctuation ambiguity и Backspace без глобального event tap.

### Dependency injection и protocol adapter

`DetectionEngine` получает `LocalLexicon` и `SystemSpellChecking`. В тестах `NSSpellChecker` заменяется `NullSpellChecker`, поэтому решение детерминировано.

### Immutable snapshot

`KeyboardLayoutSnapshot` строится один раз из TIS source и затем передаётся как неизменяемое значение. Горячий путь не вызывает `UCKeyTranslate` для каждого сравнения.

### Policy/guard pipeline

Перед вероятностной оценкой выполняются детерминированные проверки `AppPolicy`: secure context, deny list, app exclusion и структурные токены. Неопределённость разрешается после safety guards.

### Transaction и temporary gate

Коррекция рассматривается как транзакция: preflight → gate → layout switch → delete → replay/inject → drain. Event callback не блокируется ожиданием UI или словаря.

### Marker/echo suppression

Все сгенерированные CGEvents получают marker. Input service отличает их от реального пользователя и предотвращает feedback loop.

### Fail closed

При неизвестной раскладке, смене PID, Secure Input, неотпущенном modifier или неподтверждённом layout switch приложение отказывается менять текст.

### Privacy by construction

`DiagnosticLogger` принимает только enum event и числа. Text-bearing типы не входят в его public API. Clipboard API запрещён source check-ом.

### Observable settings

`AppSettings` централизует ключи `UserDefaults`. `didSet` сохраняет значение и отправляет внутреннее notification. UI не изменяет сервисы напрямую.

## Сборка

### Полная проверка

```bash
./Scripts/verify.sh
```

Скрипт выполняет:

1. полный `swift test`;
2. `swift run TypeSteady --self-test`;
3. privacy source check;
4. release arm64 build;
5. сборку `.app`;
6. ad-hoc подпись с Hardened Runtime;
7. `codesign --verify`;
8. проверку `Assets.car` на адаптивные `IconGroup`-слои;
9. побайтовое сравнение системного ICNS fallback с упакованным `TypeSteady.icns`.

### Только приложение

```bash
./Scripts/build-app.sh
```

Результат: `dist/TypeSteady.app`.

### DMG

```bash
./Scripts/package-dmg.sh
hdiutil verify dist/TypeSteady-0.1.9-arm64.dmg
```

В некоторых sandboxed automation environments `hdiutil` требует запуск вне sandbox, поскольку создаёт виртуальное устройство.

### Toolchain environment

`Scripts/toolchain-env.sh`:

- использует SDK выбранного полного Xcode, если он установлен;
- для standalone Command Line Tools с несовместимым default SDK выбирает доступный macOS 15.4 SDK;
- направляет module cache в `.build`.

## Тестирование

### Встроенный self-test

```bash
swift run --disable-sandbox TypeSteady --self-test
```

Он не требует TCC и проверяет:

- transliteration и запрет mixed token;
- загрузку bundle lexicon;
- пресеты hotkeys и совместимость raw values;
- modifier-only Option и отмену при chord/key input;
- подавление повторных event-tap disable callbacks;
- безопасную нарезку UTF-16;
- границы state machine и Backspace reopen;
- punctuation ambiguity;
- динамическое преобразование через layout maps;
- layout detection и сохранение известного слова;
- IDE policy.

### Swift Testing

Каталог `Tests/TypeSteadyAppTests` содержит более гранулярные тесты. Они запускаются командой:

```bash
swift test --disable-sandbox
```

Standalone Command Line Tools некоторых версий не включают модуль `Testing`; тогда требуется полный Xcode. `verify.sh` поэтому опирается на встроенный self-test.

### Ручная матрица

TCC и межпроцессное поведение нельзя достоверно проверить unit-тестом. См. `MANUAL_TESTS.md`.

## Privacy gate

```bash
./Scripts/check-privacy.sh
```

Добавление сетевого SDK, updater, clipboard API или text-bearing logger должно намеренно изменить этот gate и пройти отдельное privacy review. Не следует просто добавлять новое API в исключения regex.

## Добавление локального слова

Статические списки находятся в:

- `en_common.txt`;
- `en_extended.txt`;
- `ru_common.txt`;
- `ru_extended.txt`.

Формат: UTF-8, одно нормализованное слово на строку, `#` начинает комментарий. Common даёт больший score, extended предназначен для имён, сленга, сокращений и product terms.

При добавлении стороннего корпуса необходимо:

1. проверить лицензию и возможность redistribution;
2. сохранить attribution/notice;
3. нормализовать Unicode;
4. удалить чувствительные или случайно попавшие данные;
5. измерить false-positive rate на negative corpus;
6. проверить размер и время запуска.

## Добавление hotkey preset

1. Добавить `HotkeyChoice` с явным новым raw value.
2. Не менять raw values существующих cases: они уже находятся в `UserDefaults`.
3. Определить `title`, `carbonModifiers`, `eventFlags`; Carbon и event-tap представления должны описывать одну комбинацию.
4. Добавить self-test и Swift Testing case.
5. Проверить конфликт с системными shortcuts.

## Добавление языка

Текущая UI-модель EN/RU требует расширения `LanguageCode`, но input/correction остаются общими.

Последовательность:

1. определить script coverage;
2. добавить local lexicon и n-gram data;
3. научить `LayoutCatalog` выбирать source языка;
4. заменить фиксированные два Picker на language-pair configuration;
5. добавить detector corpus;
6. при необходимости добавить transliterator;
7. проверить punctuation ambiguity конкретной пары.

## Concurrency и event tap правила

- Callback не должен обращаться к SwiftUI, NSSpellChecker, AX или TIS.
- В callback нельзя ждать main queue, писать файл или выполнять scoring.
- В callback запрещено повторно включать отключённый event tap. Решение о recovery принимает `AppDelegate` после проверки TCC, с задержкой и rate limit.
- `.tapDisabledByUserInput` останавливает монитор до явной пользовательской проверки; автоматический recovery разрешён только для timeout.
- Shared gate state защищается `NSLock`.
- TIS/AX/AppKit остаются на `MainActor`.
- Новое synthetic event обязательно получает marker.
- Gate должен закрываться только после атомарного опустошения очереди.
- Любая операция перед удалением текста должна иметь preflight.

## Версионирование и bundle identity

Версия сейчас указана в `Support/Info.plist`, имени DMG и документации. При релизе нужно синхронно обновить:

- `CFBundleShortVersionString`;
- `CFBundleVersion`;
- `DMG_PATH` в scripts;
- статус документации.

Для сборки иконки требуется установленный Xcode с Icon Composer. `build-app.sh` вызывает `actool` напрямую, поэтому отдельный `.xcodeproj` для SwiftPM-приложения не нужен.

Bundle identifier `local.typesteady.app` должен оставаться стабильным, иначе TCC будет воспринимать приложение как новое.

## Подпись и нотарификация

Локальная сборка:

```bash
codesign --force --options runtime --timestamp=none --sign - ...
```

После получения Developer ID:

1. создать notarytool keychain profile;
2. задать `DEVELOPER_ID_APPLICATION`;
3. задать `NOTARY_KEYCHAIN_PROFILE`;
4. запустить `Scripts/sign-and-notarize.sh`;
5. проверить `stapler` и `spctl` на чистой системе.

Скрипт подписывает `.app`, создаёт DMG без повторной ad-hoc сборки, подписывает DMG, отправляет его на notarization и выполняет stapling.

## Release checklist

1. Рабочее дерево чистое.
2. `verify.sh` завершён успешно.
3. Swift Testing пройден в полном Xcode.
4. Ручная матрица выполнена минимум на macOS 15 и актуальной macOS.
5. Проверены M1 и актуальное поколение Apple Silicon.
6. `hdiutil verify` успешен.
7. Privacy/network наблюдение выполнено.
8. Version fields синхронизированы.
9. Подпись и notarization проверены, если это публичный релиз.
