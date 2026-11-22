#!/bin/sh
set -eu

proj=
stage=подготовка

dc() {
    docker compose -f compose.yaml -p "$proj" "$@"
}

finish() {
    rc=$?
    trap - EXIT
    if [ -n "$proj" ]; then
        dc down -v --rmi local >&2 || rc=1
    fi
    if [ "$rc" -ne 0 ]; then
        printf 'Ошибка на этапе «%s»\n' "$stage" >&2
    fi
    exit "$rc"
}

count() {
    body=$(curl -fsS --max-time 5 -X "$1" "$url$2")
    got=$(printf '%s' "$body" | dc exec -T app python -c 'import json, sys; print(json.load(sys.stdin)["count"])')
    printf '%s %s: count=%s\n' "$1" "$2" "$got"
    [ "$got" = "$3" ]
}

code() {
    got=$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -X "$1" "$url$2")
    printf '%s %s: HTTP %s\n' "$1" "$2" "$got"
    [ "$got" = "$3" ]
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "${0%/*}/.."
export APP_PORT=0
id=$(docker run --rm --entrypoint cat redis:7.4-alpine /proc/sys/kernel/random/uuid)
proj="check-$id"
backup="${TMPDIR:-/tmp}/$proj.tar"

stage='запуск с пустым volume'
printf '\n%s\n' "$stage"
dc up -d --build --wait --wait-timeout 40
url="http://$(dc port app 8000)"

stage='лимиты app'
uid=$(dc exec -T app id -u)
app=$(dc ps -q app)
limits=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}' "$app")
[ "$uid" -gt 0 ]
[ "$limits" = 'true 268435456 1000000000' ]
printf 'UID %s, read_only/memory/CPU: %s\n' "$uid" "$limits"

stage='счётчик'
count GET / 0
for n in 1 2 3; do
    count POST /increment "$n"
done
count GET / 3

stage='пересоздание app'
printf '\n%s\n' "$stage"
redis=$(dc ps -q redis)
dc up -d --no-deps --force-recreate --wait --wait-timeout 40 app
url="http://$(dc port app 8000)"
[ "$(dc ps -q redis)" = "$redis" ]
new_app=$(dc ps -q app)
[ "$new_app" != "$app" ]
count GET / 3

stage='остановка Redis'
printf '\n%s\n' "$stage"
started=$(docker inspect --format '{{.State.StartedAt}}' "$new_app")
dc stop redis
code GET /healthz 200
code GET /readyz 503
code POST /increment 503

stage='запуск Redis'
printf '\n%s\n' "$stage"
dc start redis
curl -fsS --max-time 5 --retry 10 --retry-delay 1 --retry-max-time 20 -o /dev/null "$url/readyz"
[ "$(dc ps -q app)" = "$new_app" ]
[ "$(docker inspect --format '{{.State.StartedAt}}' "$new_app")" = "$started" ]
count GET / 3
count POST /increment 4

stage='копия Redis'
printf '\n%s\n' "$stage"
dc stop app
dc stop redis
(
    set -C
    dc run --rm --no-deps -T --user 0 --entrypoint tar redis -C /data -cf - . > "$backup"
)
[ -s "$backup" ]
printf 'Архив %s\n' "$backup"

stage='удаление исходного проекта'
printf '\n%s\n' "$stage"
dc down -v --rmi local
proj="restore-$id"

stage='восстановление из копии'
printf '\n%s\n' "$stage"
dc run --rm --no-deps -T --user 0 --entrypoint tar redis -C /data -xpf - < "$backup"
dc up -d --build --wait --wait-timeout 40
url="http://$(dc port app 8000)"
count GET / 4
count POST /increment 5

stage='удаление проекта восстановления'
dc down -v --rmi local
proj=
printf '\nПроверка прошла\n'
