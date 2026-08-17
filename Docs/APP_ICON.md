# Иконка TypeSteady

## Утверждённое направление

Иконка использует фронтальную композицию из стеклянных слоёв:

1. чистая белая подложка;
2. коралловая левая панель;
3. тёплая песочная правая панель;
4. более насыщенный голубой S-образный переход.

S-жест обозначает непрерывное переключение между двумя раскладками. Геометрия не имитирует клавишу: все поверхности расположены параллельно плоскости экрана и различаются цветом, прозрачностью и преломлением. Белая подложка повышает контраст цветных слоёв и не загрязняет оттенки прозрачного стекла.

Цветовая схема является утверждённой пользователем, concept-proposed:

- background: clean white, ориентир `#FFFFFF`;
- primary: coral, ориентир `#F17D69`;
- secondary: warm sand, ориентир `#E7C798`;
- transition: cyan glass, ориентир `#65D1D0`.

## Файлы

- `Support/AppIcon.icns` — рабочая многоразмерная иконка приложения;
- `Support/IconSources/TypeSteady-AppIcon-master-1024.png` — квадратный мастер 1024×1024;
- `Support/IconSources/TypeSteady-AppIcon-optical-128.png` — проверочный мастер 128 px;
- `Support/IconSources/TypeSteady-AppIcon-optical-32.png` — проверочный мастер 32 px.

`Scripts/build-app.sh` копирует `AppIcon.icns` в `Contents/Resources`, а `Support/Info.plist` указывает его через `CFBundleIconFile`.

## Соответствие рекомендациям Apple

Мастер имеет квадратный полноразмерный фон. Внешняя rounded-rectangle mask не является частью исходного artwork: системное скругление должно применяться macOS.

Композиция следует основным требованиям Apple Human Interface Guidelines:

- один крупный узнаваемый жест;
- небольшое число заполненных перекрывающихся форм;
- центрированное содержимое и безопасные поля;
- читаемость на малых размерах;
- простая непрозрачная background layer;
- отдельные foreground layers с чёткими границами.

Текущая SwiftPM-сборка использует совместимый `ICNS`, поэтому материал в нём является статическим. Для полноценного динамического Liquid Glass нужно перенести исходную композицию в Apple Icon Composer как отдельные слои. В этих слоях нельзя заранее запекать exterior mask, blur, drop shadow, specular highlight, opacity и refraction: Icon Composer должен применять их динамически.

## План Icon Composer

При переходе на Xcode/`Icon Composer`:

1. восстановить четыре независимых SVG/PNG-слоя в порядке от белого background к S-переходу;
2. задавать фон как полноразмерный непрозрачный цвет или градиент внутри Icon Composer;
3. импортировать foreground artwork без теней, фасок и свечения;
4. настроить translucency, refraction и specular highlights в Composer;
5. проверить macOS Default, Dark, Clear и Tinted previews;
6. проверить автоматически созданный Xcode fallback для macOS 15;
7. сравнить Finder, Dock и собранный `.app` после увеличения build number.

## Проверка

После сборки:

```bash
plutil -p dist/TypeSteady.app/Contents/Info.plist
test -f dist/TypeSteady.app/Contents/Resources/AppIcon.icns
shasum -a 256 Support/AppIcon.icns dist/TypeSteady.app/Contents/Resources/AppIcon.icns
```

Оба SHA-256 должны совпадать. Finder и Dock могут показывать закэшированную предыдущую иконку; сначала следует переустановить новую сборку, а не очищать кэш вручную.
