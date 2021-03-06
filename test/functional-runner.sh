#!/bin/bash
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
DIRECTORY_HOST=${HOST_IP:-localhost}
FUNC_TEST_CMD=${FUNC_TEST_CMD:-tape \'test/functional/**/*.test.js\' | faucet}
docker_compose_file=$1
docker_functional_compose_file=$2
env_file=$3

if [ $# -ne 3 ]; then
    echo "Usage: $0 docker-compose-file docker-functional-compose-file env-file"
    exit 1
fi

psql() {
	docker run --rm -i \
		--net centraldirectory_back \
		--entrypoint psql \
		-e PGPASSWORD=$POSTGRES_PASSWORD \
		"postgres:9.4" \
    --host postgres \
		--username $POSTGRES_USER \
		--quiet --no-align --tuples-only \
		"$@"
}

is_psql_up() {
    psql -c '\l' > /dev/null 2>&1
}

is_central_directory_up() {
    curl --output /dev/null --silent --head --fail http://${DIRECTORY_HOST}:3000/health
}

run_test_command()
{
  eval "$FUNC_TEST_CMD"
}

shutdown_and_remove() {
  npm run docker:clean
}

>&2 echo "Loading environment variables"
source $env_file

>&2 echo "Postgres is starting"
docker-compose -f $docker_compose_file -f $docker_functional_compose_file up -d postgres > /dev/null 2>&1

until is_psql_up; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

>&2 echo "Postgres is up - creating functional database"
psql <<'EOSQL'
    DROP DATABASE IF EXISTS "central_directory_functional";
	  CREATE DATABASE "central_directory_functional";
EOSQL

>&2 echo "Central-directory is building ..."
docker-compose -f $docker_compose_file -f $docker_functional_compose_file up -d central-directory

>&2 printf "Central-directory is starting ..."
until is_central_directory_up; do
  >&2 printf "."
  sleep 1
done

>&2 echo " done"

>&2 echo "Functional tests are starting"
set -o pipefail && run_test_command
test_exit_code=$?

if [ "$test_exit_code" != 0 ]
then
  docker logs centraldirectory_central-directory_1
fi

shutdown_and_remove

exit "$test_exit_code"
