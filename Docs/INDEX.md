# Документация TypeSteady

Разработчик: **Aleksei Panin** — [GitHub](https://github.com/deadmoose-ap) · [LinkedIn](https://www.linkedin.com/in/aleksei-panin/).

## Пользователю

- [Контекст для следующего агента](../../AGENT_CONTEXT.md) — проверенные паттерны, причины багов, TCC/event-tap ограничения и release lessons. Файл лежит в корне рабочего пространства, на уровень выше пакета `app/`.
- [Руководство пользователя](USER_GUIDE.md) — установка, первый запуск, все функции, настройки, hotkeys и troubleshooting.
- [Безопасность данных, приватность и разрешения](PRIVACY.md) — какие данные видит процесс, что сохраняется, зачем нужны Input Monitoring и Accessibility.
- [Ручная проверка](MANUAL_TESTS.md) — сценарии в браузерах, мессенджерах, Office и IDE.
- [Тестовое покрытие](TESTING.md) — автоматические suites, системные границы и обязательные release gates.
- [Отличия и преимущества](DIFFERENTIATORS.md) — продуктовые отличия от открытых альтернатив.

## Разработчику

- [Архитектура](ARCHITECTURE.md) — input pipeline, state machine, detection, correction gate, Accessibility и расширение языков.
- [Стек и руководство разработчика](DEVELOPMENT.md) — framework, паттерны, структура, сборка, тесты, privacy gate и релиз.
- [Иконка приложения](APP_ICON.md) — утверждённая композиция, палитра, файлы, Apple HIG и переход на Icon Composer.
- [Статус реализации](IMPLEMENTATION_STATUS.md) — реализованное, ручные проверки и текущие ограничения.
- [Бэклог](BACKLOG.md) — запланированные функции и интеграции.

## Быстрые команды

```bash
./Scripts/verify.sh
./Scripts/build-app.sh
./Scripts/package-dmg.sh
```

Готовые локальные артефакты находятся в `dist/`.
