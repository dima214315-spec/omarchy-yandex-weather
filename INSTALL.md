# Установка «Яндекс Погода» для Omarchy

Виджет бара: температура на баре, по клику — панель с прогнозом на 10 дней,
городами, поиском и определением города по IP.

## Что нужно

- Omarchy 4 (Quickshell-шелл). Проверить: `omarchy version` — должно быть 4.x.
- `python3` — в Arch стоит по умолчанию; проверить: `python3 --version`.
- Интернет: страницы `yandex.ru/pogoda` (данные) и `ipinfo.io` (только для
  кнопки «Определить»).

## Установка — 3 команды

```bash
git clone https://github.com/dima214315-spec/omarchy-yandex-weather.git \
  ~/.config/omarchy/plugins/pole.yandex-weather
omarchy restart shell
omarchy bar put pole.yandex-weather --section centerEnd
```

- первая команда скачивает плагин в папку пользовательских плагинов
  (`~/.config/omarchy/plugins/`, её не трогает `omarchy update`);
- вторая перезапускает шелл, чтобы он увидел новый плагин;
- третья ставит виджет на бар справа от часов.

Другие места на баре: `--section centerBegin`, `centerEnd`, `left`, `right`
(по умолчанию — `centerEnd`). После установки виджет в баре можно двигать
мышью, как любую иконку бара.

## Без git (архивом)

1. На странице репозитория: **Code → Download ZIP**.
2. Распакуйте и переименуйте папку в `pole.yandex-weather`, положите по пути
   `~/.config/omarchy/plugins/pole.yandex-weather` (внутри должны лежать
   `manifest.json`, `BarWidget.qml`, …).
3. Затем:

```bash
omarchy restart shell
omarchy bar put pole.yandex-weather --section centerEnd
```

## Первая настройка

1. Кликните по температуре в баре — откроется панель.
2. В поле «Найти город…» введите город (по-русски или по-английски) и выберите
   из списка; или нажмите **«Определить»**, чтобы взять город по геолокации.
3. Выбранный город сохраняется в `~/.config/omarchy/shell.json` и остаётся
   после перезагрузки.

Настройки (в том же файле, запись `pole.yandex-weather`):
`refreshMinutes` (0 — обновлять только при открытии панели), `showCondition`
(слово «ясно/дождь» в баре), `outerGap` (отступ от соседних иконок).

## Проверка, что всё на месте

```bash
python3 ~/.config/omarchy/plugins/pole.yandex-weather/bin/yandex-weather.py \
  weather moscow | head -c 200
```

Должен прийти JSON с городом «Москва» и температурой.

## Обновление

```bash
git -C ~/.config/omarchy/plugins/pole.yandex-weather pull
omarchy restart shell
```

## Удаление

```bash
omarchy bar move pole.yandex-weather --section unused   # или удалить иконку с бара мышью
rm -rf ~/.config/omarchy/plugins/pole.yandex-weather
omarchy restart shell
```

## Если что-то не так

- Виджета нет в баре: `omarchy restart shell`, затем
  `omarchy bar put pole.yandex-weather --section centerEnd`.
- Пусто вместо температуры: проверьте `python3` и интернет; запустите
  команду из «Проверки» выше.
- Ошибки в журнале: `journalctl --user -b | grep pole.yandex-weather`.
- «Определить» показывает не тот город: геолокация по IP, точность зависит от
  провайдера — выберите город вручную в поиске.
