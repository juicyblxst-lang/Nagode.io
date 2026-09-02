#!/bin/sh
set -eu

# Render exposes PostgreSQL connection strings as postgres:// or postgresql://.
# Spring Boot/Hikari requires a JDBC URL. Normalize it before the JVM starts so
# environment-property precedence cannot bypass the conversion.
case "${SPRING_DATASOURCE_URL:-}" in
  postgres://*)
    export SPRING_DATASOURCE_URL="jdbc:postgresql://${SPRING_DATASOURCE_URL#postgres://}"
    ;;
  postgresql://*)
    export SPRING_DATASOURCE_URL="jdbc:postgresql://${SPRING_DATASOURCE_URL#postgresql://}"
    ;;
esac

exec "$@"
