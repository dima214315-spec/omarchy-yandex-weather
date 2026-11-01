# Как выложить плагин на GitHub

Папка плагина уже под git: один commit с рабочей версией, ветка `main`.
Осталось залогиниться и создать репозиторий.

## 1. Войти в GitHub

```bash
gh auth login
```

Выберите `GitHub.com` → `HTTPS` → `Login with a web browser` (или вставьте
токен). Потом проверьте:

```bash
gh auth status
```

## 2. Создать репозиторий и отправить

```bash
cd ~/.config/omarchy/plugins/pole.yandex-weather
gh repo create omarchy-yandex-weather --public --source=. --push \
  --description "Яндекс Погода — виджет бара для Omarchy"
```

Если репозиторий с таким именем уже есть, то:

```bash
git remote add origin https://github.com/dima214315-spec/omarchy-yandex-weather.git
git push -u origin main
```

## 3. Проверить установку с нуля

```bash
cd ~/tmp   # любая пустая папка
git clone https://github.com/dima214315-spec/omarchy-yandex-weather.git
cp -r omarchy-yandex-weather ~/.config/omarchy/plugins/pole.yandex-weather
omarchy restart shell
omarchy bar put pole.yandex-weather --section centerEnd
```

## Обновления

После правок:

```bash
cd ~/.config/omarchy/plugins/pole.yandex-weather
git add -A
git commit -m "что изменилось"
git push
```

На другой машине — `git -C ~/.config/omarchy/plugins/pole.yandex-weather pull`
и `omarchy restart shell`.

## Альтернатива: без GitHub

`git bundle` — один файл, который можно копировать на флешке:

```bash
cd ~/.config/omarchy/plugins
git -C pole.yandex-weather bundle create ~/omarchy-yandex-weather.bundle --all
# на другой машине:
git clone ~/omarchy-yandex-weather.bundle ~/.config/omarchy/plugins/pole.yandex-weather
```

Или просто архив папки:

```bash
cd ~/.config/omarchy/plugins
tar czf ~/omarchy-yandex-weather.tar.gz pole.yandex-weather
# на другой машине:
tar xzf omarchy-yandex-weather.tar.gz -C ~/.config/omarchy/plugins/
omarchy restart shell
```
