# Документация Lang Switcher

## Пользователю

- [Руководство пользователя](USER_GUIDE.md) — установка, первый запуск, все функции, настройки, hotkeys и troubleshooting.
- [Безопасность данных, приватность и разрешения](PRIVACY.md) — какие данные видит процесс, что сохраняется, зачем нужны Input Monitoring и Accessibility.
- [Ручная проверка](MANUAL_TESTS.md) — сценарии в браузерах, мессенджерах, Office и IDE.
- [Отличия и преимущества](DIFFERENTIATORS.md) — продуктовые отличия от открытых альтернатив.

## Разработчику

- [Архитектура](ARCHITECTURE.md) — input pipeline, state machine, detection, correction gate, Accessibility и расширение языков.
- [Стек и руководство разработчика](DEVELOPMENT.md) — framework, паттерны, структура, сборка, тесты, privacy gate и релиз.
- [Статус реализации](IMPLEMENTATION_STATUS.md) — реализованное, ручные проверки и текущие ограничения.
- [Бэклог](BACKLOG.md) — запланированные функции и интеграции.

## Быстрые команды

```bash
./Scripts/verify.sh
./Scripts/build-app.sh
./Scripts/package-dmg.sh
```

Готовые локальные артефакты находятся в `dist/`.
