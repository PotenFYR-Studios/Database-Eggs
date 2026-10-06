#!/bin/bash
DB_PORT="${SERVER_PORT:-3306}"

_dbcli(){
  command -v mariadb >/dev/null 2>&1 && echo mariadb || echo mysql
}

_db_sql_session(){
  local fd="${1:-3}" c="${2:-$(_dbcli)}"
  shift 2 || true
  local -a args=("$@")
  local line

  echo "MySQL interactive console mode."
  echo "Enter SQL commands normally. Type 'exit' or 'quit' to leave."
  echo "Example: SHOW DATABASES;"

  while IFS= read -r -u "$fd" line; do
    line="${line//$'\r'/}"
    [ -n "$line" ] || continue

    case "${line,,}" in
      exit|quit|exit;|quit;)
        echo "Interactive console closed."
        return 0
        ;;
      *)
        MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" "${args[@]}" --table -e "$line"
        ;;
    esac
  done

  echo "Interactive console closed."
}

db_console_handle(){
  local line="$1" fd="${2:-3}" cmd rest db file out c
  line="${line//$'\r'/}"
  cmd="${line%%[[:space:]]*}"
  rest="${line#"$cmd"}"
  rest="${rest#${rest%%[![:space:]]*}}"

  case "${cmd,,}" in
    help)
      printf '%s\n' \
        'help' 'status' 'version' 'databases' 'users' \
        'dump' 'dump <database>' 'dump create [database]' \
        'restore <file>' 'dump restore <file>' \
        'sql <SQL>' 'sql' 'root' 'root <new_password>' \
        'mysql [mysql arguments]' 'mariadb [mariadb arguments]'
      ;;

    status)
      c=$(_dbcli)
      MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -Nse 'SELECT 1' >/dev/null 2>&1 \
        && echo "${PROJECT_TYPE^^} status: ONLINE" \
        || echo "${PROJECT_TYPE^^} status: OFFLINE"
      ;;

    version)
      c=$(_dbcli)
      MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -Nse 'SELECT VERSION();'
      ;;

    databases)
      c=$(_dbcli)
      MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e 'SHOW DATABASES;'
      ;;

    users)
      c=$(_dbcli)
      MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e 'SELECT User,Host FROM mysql.user ORDER BY User,Host;'
      ;;

    dump)
      if [[ "$rest" == restore\ * ]]; then
        file="${rest#restore }"
        db="$DB_NAME"
        [ -f "$file" ] || file="$SERVER_DIR/$file"
        [ -f "$file" ] || { echo "File not found: $file"; return 0; }
        c=$(_dbcli)
        echo "Restoring $file into $db..."
        if [[ "$file" == *.gz ]]; then
          gzip -dc "$file" | MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db"
        else
          MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db" < "$file"
        fi
        return 0
      fi

      [[ "$rest" == create\ * ]] && rest="${rest#create }"
      db="${rest:-$DB_NAME}"
      mkdir -p "$SERVER_DIR/dumps"
      out="$SERVER_DIR/dumps/$db-$(date -u +%Y-%m-%d_%H-%M-%S).sql.gz"
      c=$(_dbcli)
      echo "Creating dump: $db"

      if command -v mariadb-dump >/dev/null 2>&1; then
        MYSQL_PWD="$DB_ROOT_PASSWORD" mariadb-dump --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root \
          --single-transaction --routines --events --triggers "$db" | gzip -c > "$out"
      else
        MYSQL_PWD="$DB_ROOT_PASSWORD" mysqldump --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root \
          --single-transaction --routines --events --triggers "$db" | gzip -c > "$out"
      fi

      if [ "${PIPESTATUS[0]}" -eq 0 ] && [ -s "$out" ]; then
        echo "Dump completed: $out"
      else
        rm -f "$out"
        echo "Dump failed."
      fi
      ;;

    restore)
      [[ "$rest" == dump\ * ]] && rest="${rest#dump }"
      file="${rest%% *}"
      db="${rest#"$file"}"
      db="${db# }"
      [ -n "$db" ] || db="$DB_NAME"
      [ -f "$file" ] || file="$SERVER_DIR/$file"
      [ -f "$file" ] || { echo "File not found: $rest"; return 0; }

      c=$(_dbcli)
      echo "Restoring $file into $db..."
      if [[ "$file" == *.gz ]]; then
        gzip -dc "$file" | MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db"
      else
        MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db" < "$file"
      fi
      echo 'Restore completed.'
      ;;

    sql)
      c=$(_dbcli)
      if [ -n "$rest" ]; then
        MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e "$rest"
      else
        _db_sql_session "$fd" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root
      fi
      ;;

    root)
      local new="$rest"
      if [ -z "$new" ]; then
        printf 'New root password: '
        IFS= read -r -s new <&"$fd" || return 0
        printf '\nConfirm root password: '
        local confirm
        IFS= read -r -s confirm <&"$fd" || return 0
        printf '\n'
        [ "$new" = "$confirm" ] || { echo 'Passwords do not match.'; return 0; }
      fi

      c=$(_dbcli)
      local q
      q=$(printf '%s' "$new" | sed "s/'/''/g")

      MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e \
        "ALTER USER 'root'@'localhost' IDENTIFIED BY '$q'; ALTER USER IF EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$q'; FLUSH PRIVILEGES;" \
        && {
          DB_ROOT_PASSWORD="$new"
          export DB_ROOT_PASSWORD
          declare -F pf_users_store_root >/dev/null 2>&1 && pf_users_store_root "$new"

          if [ -f "$SERVER_DIR/.env" ]; then
            if grep -q '^DB_ROOT_PASSWORD=' "$SERVER_DIR/.env"; then
              sed -i "s|^DB_ROOT_PASSWORD=.*$|DB_ROOT_PASSWORD=$new|" "$SERVER_DIR/.env"
            else
              printf '\nDB_ROOT_PASSWORD=%s\n' "$new" >> "$SERVER_DIR/.env"
            fi
            chmod 600 "$SERVER_DIR/.env" 2>/dev/null || true
          fi

          echo 'Root password successfully changed.'
        }
      ;;

    mysql|mariadb)
      # Pterodactyl/Wings sends console commands as lines to container STDIN.
      # A real interactive mysql client expects a terminal, so use a persistent
      # SQL session driven by subsequent console lines instead.
      read -r -a argv <<< "$line"
      unset 'argv[0]'
      c=$(_dbcli)

      local execute_sql="" i=0 a next
      local -a args=(--protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root)

      while [ "$i" -lt "${#argv[@]}" ]; do
        a="${argv[$i]}"
        case "$a" in
          -e|--execute)
            i=$((i + 1))
            execute_sql="${argv[$i]:-}"
            ;;
          --execute=*)
            execute_sql="${a#--execute=}"
            ;;
          -p|--password|-p*|--password=*)
            ;;
          -u|--user)
            i=$((i + 1))
            next="${argv[$i]:-}"
            [ "$next" = "root" ] || echo "Console authentication is fixed to root; requested user '$next' was ignored."
            ;;
          -h|--host|-P|--port|-D|--database)
            i=$((i + 1))
            args+=( "$a" "${argv[$i]:-}" )
            ;;
          --host=*|--port=*|--database=*)
            args+=( "${a%%=*}" "${a#*=}" )
            ;;
          --user=*)
            next="${a#--user=}"
            [ "$next" = "root" ] || echo "Console authentication is fixed to root; requested user '$next' was ignored."
            ;;
          *)
            args+=( "$a" )
            ;;
        esac
        i=$((i + 1))
      done

      if [ -n "$execute_sql" ]; then
        MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" "${args[@]}" -e "$execute_sql"
      else
        _db_sql_session "$fd" "$c" "${args[@]}"
      fi
      ;;

    *)
      return 1
      ;;
  esac

  return 0
}
