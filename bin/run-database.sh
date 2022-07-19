#!/bin/bash
set -o errexit
set -o nounset

# shellcheck disable=SC1091
. /usr/bin/utilities.sh

export ARGUMENT_FILE="${CONFIG_DIRECTORY}/arguments"
export RUNTIME_ARGUMENT_FILE="$(mktemp)"
export CONFIG_EXTRA_FILE="${CONFIG_DIRECTORY}/redis.extra.conf"
export ACL_DIRECTORY="${CONFIG_DIRECTORY}/acls"
export ACL_FILE="${ACL_DIRECTORY}/users.acl"
CA_CERT_FILE="/usr/local/share/ca-certificates/custom_ca.crt"
DUMP_FILENAME="/tmp/dump.rdb"

# This port is an arbitrary constant, and must point to the master we'll be
# connecting to.
MASTER_FORWARD_PORT=8765
MASTER_FORWARD_CONF="${DATA_DIRECTORY}/master-tunnel.conf"

# Redis 6 introduced user management
if [[ -n "${VERSION_GTE_6:-}" ]]; then
  : ${USERNAME:=aptible}
else
  USERNAME=''
fi

save_ca_certificate() {
  if [[ -z "${CA_CERTIFICATE:-}" ]] || [[ -e "$CA_CERT_FILE" ]]; then
    # Nothing to do!
    return
  fi

  echo "$CA_CERTIFICATE" > "$CA_CERT_FILE"
  update-ca-certificates
}

ensure_ssl_material() {
  if [[ -n "${SSL_CERTIFICATE:-}" ]] && [[ -n "${SSL_KEY:-}" ]]; then
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
  save_ca_certificate

  # shellcheck disable=SC2154
  if [[ "$protocol" = "redis://" ]]; then
    if [[ -z "$port" ]]; then
      port="$REDIS_PORT"
    fi

    if [[ -n "${VERSION_GTE_6:-}" ]]; then
      # shellcheck disable=SC2154
      redis-cli -h "$host" -p "$port" --user "$user" --pass "$password" "$@"
    else
      # shellcheck disable=SC2154
      redis-cli -h "$host" -p "$port" -a "$password" "$@"
    fi

  elif [[ "$protocol" = "rediss://" ]]; then
    if [[ -z "$port" ]]; then
      port="$SSL_PORT"
    fi

    if [[ -n "${VERSION_GTE_6:-}" ]]; then
      # shellcheck disable=SC2154
      redis-cli -h "$host" -p "$port" --user "$user" --pass "$password" --tls "$@"
    else
      stunnel_dir="$(create_ephemeral_tunnel "$host" "$port")"
      redis-cli -h "127.0.1" -p "$(cat "${stunnel_dir}/port")" -a "$password" "$@"
      kill -TERM "$(cat "${stunnel_dir}/pid")"
      rm -r "${stunnel_dir}"
    fi

  else
    echo "Unknown protocol: $protocol"
  fi
}

start_server() {
  ensure_ssl_material
  save_ca_certificate

  if [[ -n "${VERSION_GTE_6:-}" ]]; then
    TLS_CERT_FILE="$(mktemp)"
    TLS_KEY_FILE="$(mktemp)"

    echo "$SSL_CERTIFICATE" > "$TLS_CERT_FILE"
    echo "$SSL_KEY" > "$TLS_KEY_FILE"

    chown "${REDIS_USER}:${REDIS_USER}" "$TLS_CERT_FILE" "$TLS_KEY_FILE"
  else
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
  fi

  # Finally, we force-chown the data directory and its contents. There won't be many
  # files there so this isn't expensive, and it's needed because we used to run Redis
  # as root but no longer do.
  chown -R "${REDIS_USER}:${REDIS_USER}" "$DATA_DIRECTORY"

  touch "$ARGUMENT_FILE" # don't crash and burn if initialize wasn't called.

  if [[ -n "${MAX_MEMORY:-}" ]]; then
    echo "--maxmemory-policy allkeys-lru" >> "$RUNTIME_ARGUMENT_FILE"
    echo "--maxmemory ${MAX_MEMORY}" >> "$RUNTIME_ARGUMENT_FILE"
  fi

  if [[ -n "${VERSION_GTE_6:-}" ]]; then
    echo "--tls-port ${SSL_PORT}" >> "$RUNTIME_ARGUMENT_FILE"
    echo "--tls-cert-file ${TLS_CERT_FILE}" >> "$RUNTIME_ARGUMENT_FILE"
    echo "--tls-key-file ${TLS_KEY_FILE}" >> "$RUNTIME_ARGUMENT_FILE"
    echo "--tls-auth-clients no" >> "$RUNTIME_ARGUMENT_FILE"

    chown "${REDIS_USER}:${REDIS_USER}" "$RUNTIME_ARGUMENT_FILE"
    exec sudo -E -u "$REDIS_USER" redis-wrapper
  else
    chown "${REDIS_USER}:${REDIS_USER}" "$RUNTIME_ARGUMENT_FILE"
    exec supervisord -c "/etc/supervisord.conf"
  fi
}

create_user() {
  # Create an ACL file to store users in and create the initial user
  mkdir -p "$ACL_DIRECTORY"
  echo "user ${USERNAME} on >${PASSPHRASE} ~* &* +@all" > "$ACL_FILE"
  echo "user default on >${PASSPHRASE} ~* &* +@all" >> "$ACL_FILE"
  echo "--aclfile ${ACL_FILE}" >> "$ARGUMENT_FILE"
  # The aclfile must be in a directory owned by the $REDIS_USER in order for
  # ACL SAVE to work as this command creates a temporary file in the same directory
  chown -R "${REDIS_USER}:${REDIS_USER}" "$ACL_DIRECTORY"
}

if [[ "$#" -eq 0 ]]; then
  start_server

elif [[ "$1" == "--initialize" ]]; then
  touch "$CONFIG_EXTRA_FILE"
  touch "$ARGUMENT_FILE"

  if [[ -n "${REDIS_NORDB:-}" ]]; then
    echo 'appendonly no' >> "$CONFIG_EXTRA_FILE"
    echo 'save ""' >> "$CONFIG_EXTRA_FILE"
  fi

  if [[ -n "${REDIS_AOF:-}" ]]; then
    echo 'appendonly yes' >> "$CONFIG_EXTRA_FILE"
  fi

  if [[ -n "${VERSION_GTE_6:-}" ]]; then
    create_user
  else
    echo "--requirepass ${PASSPHRASE}" > "$ARGUMENT_FILE"
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
    if [[ -n "${VERSION_GTE_6:-}" ]]; then
      if [[ -z "$port" ]]; then
        port="$SSL_PORT"
      fi

    else
      create_tunnel_configuration redis-master \
        "127.0.0.1" "$MASTER_FORWARD_PORT" \
        "$host" "$port" \
        > "$MASTER_FORWARD_CONF"

      host="127.0.0.1"
      port="$MASTER_FORWARD_PORT"
    fi
  else
    echo "Unknown protocol: $protocol"
  fi

  {
    echo "--slaveof ${host} ${port}" > "$ARGUMENT_FILE"
    if [[ -n "${VERSION_GTE_6:-}" ]]; then
      create_user

      if [[ -n "${REPLCIATION_USERNAME:-}" ]]; then
        REPL_USER="$REPLICATION_USERNAME"
      else
        if [[ -n "${APTIBLE_DATABASE_HREF:-}" ]]; then
          DATABASE_ID="${APTIBLE_DATABASE_HREF##*/}"
          REPL_USER="repl_${DATABASE_ID}"
        else
          REPL_USER="repl_$(pwgen -s 20 | tr '[:upper:]' '[:lower:]')_$(date +%s)"
        fi
      fi

      REPL_PASS="${REPLICATION_PASSPHRASE:-"$(pwgen -s 32)"}"

      # Replica permissions https://redis.io/docs/manual/security/acl/#acl-rules-for-sentinel-and-replicas
      start_redis_cli "$url" ACL SETUSER "$REPL_USER" on ">${REPL_PASS}" +psync +replconf +ping
      start_redis_cli "$url" ACL SAVE

      echo "--masteruser ${REPL_USER}" >> "$ARGUMENT_FILE"
      echo "--masterauth ${REPL_PASS}" >> "$ARGUMENT_FILE"
      if [[ "$protocol" = "rediss://" ]]; then
        echo '--tls-replication yes' >> "$ARGUMENT_FILE"
        echo "--tls-ca-cert-dir ${SSL_CERTS_DIRECTORY}" >> "$ARGUMENT_FILE"
      fi
    else
      echo "--masterauth ${password}" >> "$ARGUMENT_FILE"
      echo "--requirepass ${password}" >> "$ARGUMENT_FILE"
    fi
  }

elif [[ "$1" == "--client" ]]; then
  [ -z "$2" ] && echo "docker run -it aptible/redis --client redis://..." && exit
  shift
  start_redis_cli "$@"

elif [[ "$1" == "--dump" ]]; then
  [ -z "$2" ] && echo "docker run -i aptible/redis --dump redis://... > dump.rdb" && exit
  shift

  # Redis 6+ outputs additional data to stdout.
  # Redirect it to stderr so that stdout only contains the dump
  start_redis_cli "$@" --rdb "$DUMP_FILENAME" >&2

  #shellcheck disable=SC2015
  [ -e /dump-output ] && exec 3>/dump-output || exec 3>&1
  cat "$DUMP_FILENAME" >&3
  rm "$DUMP_FILENAME"

elif [[ "$1" == "--restore" ]]; then
  [ -z "$2" ] && echo "docker run -i aptible/redis --restore redis://... < dump.rdb" && exit
  shift

  #shellcheck disable=SC2015
  [ -e /restore-input ] && exec 3</restore-input || exec 3<&0
  cat > "$DUMP_FILENAME" <&3
  rdb --command protocol "$DUMP_FILENAME" | start_redis_cli "$@" --pipe
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
      "connection_url": "${REDIS_PROTOCOL}://${USERNAME}:${PASSPHRASE}@${EXPOSE_HOST}:${!REDIS_EXPOSE_PORT_PTR}"
    },
    {
      "type": "redis+ssl",
      "default": false,
      "connection_url": "${SSL_PROTOCOL}://${USERNAME}:${PASSPHRASE}@${EXPOSE_HOST}:${!SSL_EXPOSE_PORT_PTR}"
    }
  ]
}
EOM

else
  echo "Unrecognized command: $1"
  exit 1
fi
