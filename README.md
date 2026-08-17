# TypeSteady

Локальный нативный переключатель English ↔ Russian для Apple Silicon и macOS 15+.

Разработчик: **Aleksei Panin**.

Возможности текущей версии:

- автоматическое исправление последнего слова после пробела или пунктуации;
- ручное исправление последнего слова глобальным хоткеем;
- преобразование выделенного текста через Accessibility без clipboard;
- отдельный локальный детектор фонетического транслита;
- профили для IDE и редакторов кода;
- menu bar, окно настроек, запуск при входе, звук и визуальная обратная связь;
- отсутствие сетевого кода, телеметрии и crash uploader.

## Требования

- Apple Silicon;
- macOS 15 или новее;
- Swift 6 toolchain. Для выпуска через Xcode нужен полный Xcode; локальная сборка работает и с актуальными Command Line Tools.

## Быстрый старт

```bash
./Scripts/verify.sh
open "dist/TypeSteady.app"
```

При первом запуске выдайте приложению разрешения Accessibility и Input Monitoring. Для локально подписанной сборки после пересборки macOS иногда запрашивает их повторно.

Горячие клавиши по умолчанию:

- Control+Option+Space — исправить последнее слово;
- Control+Option+Command+Space — преобразовать выделение.

В настройках также доступны `Option+Space`, `Control+Shift+Space` и `Command+Option+Space`. Комбинация для выделения показывается рядом и автоматически получает дополнительный Command либо Control.

## Сборка

```bash
swift run --disable-sandbox TypeSteady --self-test
./Scripts/build-app.sh
./Scripts/package-dmg.sh
```

`swift test` запускает дополнительный набор Swift Testing-тестов при наличии полного Xcode. Встроенный `--self-test` работает с Command Line Tools и проверяется скриптом `verify.sh` всегда.

Артефакты появляются в `dist/`. Сборка arm64-only и подписывается ad-hoc. Для публичной доставки потребуется Developer ID Application и нотарификация.

После получения сертификата можно задать `DEVELOPER_ID_APPLICATION` и созданный для `notarytool` профиль `NOTARY_KEYCHAIN_PROFILE`, затем запустить `Scripts/sign-and-notarize.sh`.

## Документация

- [Полный индекс документации](Docs/INDEX.md)
- [Руководство пользователя и описание функций](Docs/USER_GUIDE.md)
- [Отличия и преимущества](Docs/DIFFERENTIATORS.md)
- [Безопасность, приватность и разрешения](Docs/PRIVACY.md)
- [Ручная проверка](Docs/MANUAL_TESTS.md)
- [Архитектура](Docs/ARCHITECTURE.md)
- [Стек и руководство разработчика](Docs/DEVELOPMENT.md)
- [Иконка приложения и Apple HIG](Docs/APP_ICON.md)
- [Статус реализации](Docs/IMPLEMENTATION_STATUS.md)
- [Бэклог](Docs/BACKLOG.md)
