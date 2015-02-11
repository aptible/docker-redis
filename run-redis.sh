#!/bin/sh

CONF_FILE="/redis.conf"
echo "maxmemory-policy ${REDIS_MAX_MEMORY_POLICY:-"allkeys-lru"}" >> "$CONF_FILE"
echo "maxmemory ${REDIS_MAX_MEMORY:-100mb}" >> "$CONF_FILE"

if [[ -n "$REDIS_PASSWORD" ]]; then
	echo "requirepass "$REDIS_PASSWORD"" >> "$CONF_FILE"
fi

redis-server "$CONF_FILE"
