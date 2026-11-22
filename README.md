# ДЗ 3. Docker

## Один контейнер

```sh
docker build -t ipr-counter .
docker run --rm -p 127.0.0.1:8080:8000 -e GREETING=Hi ipr-counter
```

[Логи](answer.log)

## SQLite

```sh
cp -n .env.example .env
docker compose -f compose.sqlite.yaml up -d --build
```

Порт и приветствие можно поменять в `.env` (`APP_PORT` и `GREETING`).

Сделал один `POST /increment`, получил `1`. Пересоздал контейнер через `docker compose -f compose.sqlite.yaml up -d --force-recreate app`. Счётчик остался `1`.

## Redis

```sh
docker compose -f compose.sqlite.yaml down
docker compose up -d --build --wait
```

Три раза сделал `POST /increment`, получил `1`, `2`, `3`. После `docker compose down` и `docker compose up -d --wait` было всё ещё `3`.

После `docker compose stop redis` запрос `/healthz` дал `200`, а `/readyz` и `POST /increment` дали `503`. После `docker compose start redis` снова получил `3`, следующий POST дал `4`. Приложение всё это время работало в том же контейнере.

## Скрипт

```sh
./scripts/check.sh
```

У `app` UID `10001`, корень только для чтения, лимиты 256 МиБ и 1 ядро.

С тестами всё норм. Запустил два раза подряд. Оба раза счётчик восстановился до `4`, после POST стал `5`.

[Вывод](check.log)
