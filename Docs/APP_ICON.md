# Иконка TypeSteady

## Иконка menu bar

Статусная иконка намеренно не является уменьшенной цветной app icon. Она строится нативно в
`StatusBarIcon.swift` как монохромный template `NSImage`: две сплошные панели разделены прозрачным
S-образным каналом, повторяющим главный жест TypeSteady. Внешняя графитовая подложка, цвет,
стеклянные эффекты и текст `AЯ` не используются. AppKit самостоятельно задаёт цвет для светлой,
тёмной, нажатой и отключённой строки меню.

Статусный элемент использует квадратную системную длину, режим `imageOnly`, tooltip и accessibility
label `TypeSteady`. Геометрия и прозрачность канала проверяются в `StatusBarIconTests`.

## Утверждённое направление

Иконка использует фронтальную композицию из стеклянных слоёв:

1. спокойная тёмно-графитовая подложка;
2. коралловая левая панель;
3. тёплая песочная правая панель;
4. более насыщенный голубой S-образный переход.

S-жест обозначает непрерывное переключение между двумя раскладками. Геометрия не имитирует клавишу: все поверхности расположены параллельно плоскости экрана и различаются цветом, прозрачностью и преломлением. Низкохроматическая графитовая подложка отделяет светлые стеклянные грани от Finder и Dock, повышает контраст бирюзового жеста и при этом не уводит тёплые слои в грязные оттенки.

Цветовая схема является утверждённой пользователем, concept-proposed:

- background: calm neutral graphite, ориентир `#22272B`;
- primary: coral, ориентир `#F17D69`;
- secondary: warm sand, ориентир `#E7C798`;
- transition: cyan glass, ориентир `#65D1D0`.

## Файлы

- `Support/IconSources/IconComposer/TypeSteady.icon` — исходный многослойный документ Apple Icon Composer;
- `Support/AppIcon.icns` — зафиксированный системный fallback, сгенерированный Xcode из `.icon`;
- `Support/IconSources/TypeSteady-AppIcon-master-1024.png` — квадратный мастер 1024×1024;
- `Support/IconSources/TypeSteady-AppIcon-optical-128.png` — проверочный мастер 128 px;
- `Support/IconSources/TypeSteady-AppIcon-optical-32.png` — проверочный мастер 32 px.
- `Support/IconSources/IconComposer/Layers/*.svg` — чистые плоские слои для импорта в Icon Composer;
- `Support/IconSources/IconComposer/layer-manifest.json` — порядок групп, цвет canvas и material intent.

`Scripts/build-app.sh` перед каждой release-сборкой компилирует `.icon` официальным `xcrun actool`. В приложение входят `Assets.car` с адаптивными слоями Liquid Glass и системный `TypeSteady.icns` для macOS 15 и статических потребителей. `Support/Info.plist` связывает их через `CFBundleIconName` и `CFBundleIconFile`.

## Соответствие рекомендациям Apple

Мастер имеет квадратный полноразмерный фон. Внешняя системная rounded-rectangle mask не является частью clean source artwork: системное скругление должно применяться macOS. Вложенная цветная панель является частью собственного символа TypeSteady, поэтому её скругление сохранено, но после аудита у неё оставлен только один контролируемый оптический кант.

Композиция следует основным требованиям Apple Human Interface Guidelines:

- один крупный узнаваемый жест;
- небольшое число заполненных перекрывающихся форм;
- центрированное содержимое и безопасные поля;
- читаемость на малых размерах;
- простая непрозрачная background layer;
- отдельные foreground layers с чёткими границами.

Иконка собрана в Apple Icon Composer из отдельных SVG-слоёв без запечённых exterior mask, blur, drop shadow, bevel, specular highlight, opacity и refraction. Цветовые панели используют один материал в режиме `Combined`, поэтому на их стыках не возникают лишние параллельные преломления. Бирюзовый S-жест остаётся отдельной верхней группой. Системный материал, адаптивные варианты и fallback создаются инструментами Apple.

## Конфигурация Icon Composer

Документ собран следующим образом:

1. открыть `Xcode > Open Developer Tool > Icon Composer`;
2. создать документ с macOS target и canvas 1024×1024;
3. задать canvas `#22272B` или спокойный System Dark-подобный градиент;
4. импортировать `TypeSteady-10-coral.svg` и `TypeSteady-20-sand.svg` в одну группу `01 Semantic Masses` с режимом `Combined`;
5. импортировать `TypeSteady-30-switch.svg` в верхнюю группу `02 Switch Gesture`;
6. настроить для S слабое преломление, один согласованный specular и компактную нейтральную тень; если появляются параллельные белые линии, ослабить/отключить specular у группы;
7. проверить macOS Default, Dark, Mono, clear/tinted results, разные фоны и малые размеры;
8. сохранить документ как `Support/IconSources/IconComposer/TypeSteady.icon`;
9. скомпилировать его `actool` с deployment target macOS 15.0;
10. проверить автоматически созданный fallback отдельно от live-preview и сравнить Finder, Dock и собранный `.app` после увеличения build number.

`Icon Composer` не предоставляет CLI для создания документа: встроенный `ictool` экспортирует уже существующие `.icon`-документы. Поэтому clean layers и manifest генерируются автоматически, а создание и визуальная настройка самого `.icon` выполняются один раз в GUI.

## Проверка

После сборки:

```bash
plutil -p dist/TypeSteady.app/Contents/Info.plist
test -f dist/TypeSteady.app/Contents/Resources/Assets.car
test -f dist/TypeSteady.app/Contents/Resources/TypeSteady.icns
shasum -a 256 Support/AppIcon.icns dist/TypeSteady.app/Contents/Resources/TypeSteady.icns
```

Оба SHA-256 должны совпадать. Finder и Dock могут показывать закэшированную предыдущую иконку; сначала следует переустановить новую сборку, а не очищать кэш вручную.

Дополнительно структурный аудит можно выполнить установленным App Icon Studio:

```bash
python3 "/Users/playrix/plugins/app-icon-studio/skills/design-app-icons/scripts/audit_apple_icon.py" \
  --master Support/IconSources/TypeSteady-AppIcon-master-1024.png \
  --medium Support/IconSources/TypeSteady-AppIcon-optical-128.png \
  --small Support/IconSources/TypeSteady-AppIcon-optical-32.png \
  --icns Support/AppIcon.icns \
  --packaged-icns dist/TypeSteady.app/Contents/Resources/TypeSteady.icns \
  --assets-car .build/icon-assets/Assets.car \
  --packaged-assets-car dist/TypeSteady.app/Contents/Resources/Assets.car \
  --preview dist/TypeSteady-AppIcon-audit.png
```
