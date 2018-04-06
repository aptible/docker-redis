#!/bin/bash
set -o errexit
set -o nounset

# shellcheck disable=SC1091
. /usr/bin/utilities.sh

export ARGUMENT_FILE="${CONFIG_DIRECTORY}/arguments"
export CONFIG_EXTRA_FILE="${CONFIG_DIRECTORY}/redis.extra.conf"
DUMP_FILENAME="/tmp/dump.rdb"

# This port is an arbitrary constant, and must point to the master we'll be
# connecting to.
MASTER_FORWARD_PORT=8765
MASTER_FORWARD_CONF="${DATA_DIRECTORY}/master-tunnel.conf"

ensure_ssl_material() {
  if [ -n "${SSL_CERTIFICATE:-}" ] && [ -n "${SSL_KEY:-}" ]; then
    # Nothing to do!
    return
  fi

  echo "SSL Material is not present in the environment, auto-generating"
  local keyfile certfile
  certfile="$(mktemp)"
  keyfile="$(mktemp)"

  openssl req -nodes -new -x509 -sha256 -subj "/CN=redis" -out "$certfile" -keyout "$keyfile"
  SSL_CERTIFICATE="$(cat "$certfile")"
  SSL_KEY="$(cat "$keyfile")"
  export SSL_CERTIFICATE SSL_KEY

  rm "$certfile" "$keyfile"
}

create_tunnel_configuration() {
  local name="$1"
  local local_host="$2"
  local local_port="$3"
  local remote_host="$4"
  local remote_port="$5"

  echo "[${name}]"
  echo "client = yes"
  echo "accept = ${local_host}:${local_port}"
  echo "connect = ${remote_host}:${remote_port}"

  if [[ -z "${DANGER_DISABLE_CERT_VALIDATION:-}" ]]; then
    echo "verifyChain = yes"
    echo "CApath = ${SSL_CERTS_DIRECTORY}"
    echo "checkHost = ${remote_host}"
  fi
}

create_ephemeral_tunnel() {
  local remote_host="$1"
  local remote_port="$2"

  local local_port
  local_port="$(pick-free-port)"

  stunnel_dir="$(mktemp -d)"
  echo "${local_port}" > "${stunnel_dir}/port"

  {
    echo "foreground = no"
    echo "output = ${stunnel_dir}/log"
    echo "pid = ${stunnel_dir}/pid"
  } > "${stunnel_dir}/conf"

  create_tunnel_configuration redis \
    "127.0.0.1" "$local_port" \
    "$remote_host" "$remote_port" \
    >> "${stunnel_dir}/conf"

  stunnel "${stunnel_dir}/conf"

  echo "$stunnel_dir"
}

start_redis_cli() {
  parse_url "$1"
  shift

  # shellcheck disable=SC2154
  if [[ "$protocol" = "redis://" ]]; then
    if [[ -z "$port" ]]; then
      port="$REDIS_PORT"
    fi

    # shellcheck disable=SC2154
    redis-cli -h "$host" -p "$port" -a "$password" "$@"

  elif [[ "$protocol" = "rediss://" ]]; then
    if [[ -z "$port" ]]; then
      port="$SSL_PORT"
    fi

    stunnel_dir="$(create_ephemeral_tunnel "$host" "$port")"
    redis-cli -h "127.0.1" -p "$(cat "${stunnel_dir}/port")" -a "$password" "$@"
    kill -TERM "$(cat "${stunnel_dir}/pid")"
    rm -r "${stunnel_dir}"

  else
    echo "Unknown protocol: $protocol"
  fi
}

start_server() {
  ensure_ssl_material

  STUNNEL_DIRECTORY="$(mktemp -d -p "$STUNNEL_ROOT_DIRECTORY")"
  export STUNNEL_DIRECTORY

  # Set up SSL using stunnel.
  SSL_CERT_FILE="$(mktemp -p "$STUNNEL_DIRECTORY")"
  echo "$SSL_CERTIFICATE" > "$SSL_CERT_FILE"
  unset SSL_CERTIFICATE

  SSL_KEY_FILE="$(mktemp -p "$STUNNEL_DIRECTORY")"
  echo "$SSL_KEY" > "$SSL_KEY_FILE"
  unset SSL_KEY

  STUNNEL_TUNNELS_DIRECTORY="${STUNNEL_DIRECTORY}/tunnels"
  mkdir "$STUNNEL_TUNNELS_DIRECTORY"

  REDIS_TUNNEL_FILE="${STUNNEL_TUNNELS_DIRECTORY}/redis.conf"

  cat > "$REDIS_TUNNEL_FILE" <<EOF
[redis]
accept = ${SSL_PORT}
connect = ${REDIS_PORT}
cert = ${SSL_CERT_FILE}
key = ${SSL_KEY_FILE}
EOF

  if [[ -f "$MASTER_FORWARD_CONF" ]]; then
    cp "$MASTER_FORWARD_CONF" "${STUNNEL_TUNNELS_DIRECTORY}/master-tunnel.conf"
  fi

  # Finally, we force-chown the data directory and its contents. There won't be many
  # files there so this isn't expensive, and it's needed because we used to run Redis
  # as root but no longer do.
  chown -R "${REDIS_USER}:${REDIS_USER}" "$DATA_DIRECTORY"

  touch "$ARGUMENT_FILE" # don't crash and burn if initialize wasn't called.

  if [ -n "${MAX_MEMORY:-}" ]; then
    echo "--maxmemory-policy allkeys-lru" >> "$ARGUMENT_FILE"
    echo "--maxmemory ${MAX_MEMORY}" >> "$ARGUMENT_FILE"
  fi

  exec supervisord -c "/etc/supervisord.conf"
}


if [[ "$#" -eq 0 ]]; then
  start_server

elif [[ "$1" == "--initialize" ]]; then
  echo "--requirepass $PASSPHRASE" > "$ARGUMENT_FILE"

  touch "$CONFIG_EXTRA_FILE"
  if [[ -n "${REDIS_NORDB:-}" ]]; then
    echo 'appendonly no' >> "$CONFIG_EXTRA_FILE"
    echo 'save ""' >> "$CONFIG_EXTRA_FILE"
  fi

elif [[ "$1" == "--initialize-from" ]]; then
  [ -z "$2" ] && echo "docker run -i aptible/redis --initialize-from redis://... rediss://..." && exit
  shift

  # Always prefer connecting over SSL if that URL was provided.
  for url in "$@"; do
    parse_url "$url"
    if [[ "$protocol" = "rediss://" ]]; then
      break
    fi
  done

  if [[ "$protocol" = "redis://" ]]; then
    if [[ -z "$port" ]]; then
      port="$REDIS_PORT"
    fi

  elif [[ "$protocol" = "rediss://" ]]; then
    create_tunnel_configuration redis-master \
      "127.0.0.1" "$MASTER_FORWARD_PORT" \
      "$host" "$port" \
      > "$MASTER_FORWARD_CONF"

    host="127.0.0.1"
    port="$MASTER_FORWARD_PORT"
  else
    echo "Unknown protocol: $protocol"
  fi

  {
    echo "--requirepass $password" > "$ARGUMENT_FILE"
    echo "--slaveof $host ${port}" >> "$ARGUMENT_FILE"
    echo "--masterauth $password" >> "$ARGUMENT_FILE"
  }

elif [[ "$1" == "--client" ]]; then
  [ -z "$2" ] && echo "docker run -it aptible/redis --client redis://..." && exit
  shift
  start_redis_cli "$@"

elif [[ "$1" == "--dump" ]]; then
  [ -z "$2" ] && echo "docker run -i aptible/redis --dump redis://... > dump.rdb" && exit
  start_redis_cli "$2"  --rdb "$DUMP_FILENAME"

  #shellcheck disable=SC2015
  [ -e /dump-output ] && exec 3>/dump-output || exec 3>&1
  cat "$DUMP_FILENAME" >&3
  rm "$DUMP_FILENAME"

elif [[ "$1" == "--restore" ]]; then
  [ -z "$2" ] && echo "docker run -i aptible/redis --restore redis://... < dump.rdb" && exit

  #shellcheck disable=SC2015
  [ -e /restore-input ] && exec 3</restore-input || exec 3<&0
  cat > "$DUMP_FILENAME" <&3
  rdb --command protocol "$DUMP_FILENAME" | start_redis_cli "$2" --pipe
  rm "$DUMP_FILENAME"

elif [[ "$1" == "--readonly" ]]; then
  echo "This image does not support read-only mode. Starting database normally."
  start_server

elif [[ "$1" == "--discover" ]]; then
  cat <<EOM
{
  "version": "1.0",
  "environment": {
    "PASSPHRASE": "$(pwgen -s 32)"
  }
}
EOM

elif [[ "$1" == "--connection-url" ]]; then
  REDIS_EXPOSE_PORT_PTR="EXPOSE_PORT_${REDIS_PORT}"
  SSL_EXPOSE_PORT_PTR="EXPOSE_PORT_${SSL_PORT}"

  cat <<EOM
{
  "version": "1.0",
  "credentials": [
    {
      "type": "redis",
      "default": true,
      "connection_url": "${REDIS_PROTOCOL}://:${PASSPHRASE}@${EXPOSE_HOST}:${!REDIS_EXPOSE_PORT_PTR}"
    },
    {
      "type": "redis+ssl",
      "default": false,
      "connection_url": "${SSL_PROTOCOL}://:${PASSPHRASE}@${EXPOSE_HOST}:${!SSL_EXPOSE_PORT_PTR}"
    }
  ]
}
EOM

else
  echo "Unrecognized command: $1"
  exit 1
fi
