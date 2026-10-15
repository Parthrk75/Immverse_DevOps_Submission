#!/usr/bin/env bash
# RESTORE TEST: restore a dump into a FRESH Postgres and prove the data is intact.
# Works locally (docker) for the evidence run; in prod the same checks run against a PITR-restored Aurora clone.
#   scripts/restore-test.sh                       # seeds source, dumps, restores into a new instance, compares
#   DUMP=/path/app.dump scripts/restore-test.sh   # restore an existing dump only
set -euo pipefail
SRC=restore-src; DST=restore-dst; PW=testpw; IMG=postgres:16-alpine
cleanup(){ docker rm -f $SRC $DST >/dev/null 2>&1 || true; }; trap cleanup EXIT
t0=$(date +%s)
if [[ -z "${DUMP:-}" ]]; then
  docker run -d --name $SRC -e POSTGRES_PASSWORD=$PW -e POSTGRES_DB=app $IMG >/dev/null
  until docker exec $SRC pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
  docker exec $SRC psql -U postgres -d app -qc "CREATE TABLE orders(id serial primary key, tenant text, amount numeric); \
    INSERT INTO orders(tenant,amount) SELECT 't'||(g%5), g*1.5 FROM generate_series(1,50000) g;"
  src_count=$(docker exec $SRC psql -U postgres -d app -Atc "select count(*) from orders")
  src_sum=$(docker exec $SRC psql -U postgres -d app -Atc "select sum(amount) from orders")
  docker exec $SRC pg_dump -U postgres -Fc app > /tmp/app.dump
  DUMP=/tmp/app.dump
fi
docker run -d --name $DST -e POSTGRES_PASSWORD=$PW $IMG >/dev/null
until docker exec $DST pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
docker exec $DST createdb -U postgres app
docker exec -i $DST pg_restore -U postgres -d app --no-owner < "$DUMP"
dst_count=$(docker exec $DST psql -U postgres -d app -Atc "select count(*) from orders")
dst_sum=$(docker exec $DST psql -U postgres -d app -Atc "select sum(amount) from orders")
echo "source : rows=${src_count:-n/a} sum=${src_sum:-n/a}"
echo "restore: rows=$dst_count sum=$dst_sum"
[[ -z "${src_count:-}" || ( "$src_count" == "$dst_count" && "$src_sum" == "$dst_sum" ) ]] && echo "RESTORE TEST PASSED in $(( $(date +%s) - t0 )) s (RTO sample)" \
  || { echo "RESTORE TEST FAILED"; exit 1; }
