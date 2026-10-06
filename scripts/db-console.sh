#!/bin/bash
DB_PORT="${SERVER_PORT:-3306}"
_dbcli(){ command -v mariadb >/dev/null 2>&1 && echo mariadb || echo mysql; }
db_console_handle(){
  local line="$1" fd="${2:-3}" cmd rest db file out c
  line="${line//$'\r'/}"; cmd="${line%%[[:space:]]*}"; rest="${line#"$cmd"}"; rest="${rest#${rest%%[![:space:]]*}}"
  case "${cmd,,}" in
    help) printf '%s\n' 'help' 'status' 'version' 'databases' 'users' 'dump' 'dump <database>' 'dump create [database]' 'restore <file>' 'dump restore <file>' 'sql <SQL>' 'sql' 'root' 'root <new_password>' 'mysql [mysql arguments]' 'mariadb [mariadb arguments]' ;;
    status) c=$(_dbcli); MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -Nse 'SELECT 1' >/dev/null 2>&1 && echo "${PROJECT_TYPE^^} status: ONLINE" || echo "${PROJECT_TYPE^^} status: OFFLINE" ;;
    version) c=$(_dbcli); MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -Nse 'SELECT VERSION();' ;;
    databases) c=$(_dbcli); MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e 'SHOW DATABASES;' ;;
    users) c=$(_dbcli); MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e 'SELECT User,Host FROM mysql.user ORDER BY User,Host;' ;;
    dump)
      [[ "$rest" == restore\ * ]] && { file="${rest#restore }"; db="$DB_NAME"; [ -f "$file" ] || file="$SERVER_DIR/$file"; [ -f "$file" ] || { echo "File not found: $file"; return 0; }; c=$(_dbcli); echo "Restoring $file into $db..."; if [[ "$file" == *.gz ]]; then gzip -dc "$file" | MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db"; else MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db" < "$file"; fi; return 0; }
      [[ "$rest" == create\ * ]] && rest="${rest#create }"; db="${rest:-$DB_NAME}"; mkdir -p "$SERVER_DIR/dumps"; out="$SERVER_DIR/dumps/$db-$(date -u +%Y-%m-%d_%H-%M-%S).sql.gz"; c=$(_dbcli); echo "Creating dump: $db"; MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root --batch --skip-lock-tables -e "SHOW CREATE DATABASE \\`$db\\`;" >/dev/null 2>&1; if command -v mariadb-dump >/dev/null 2>&1; then mariadb-dump --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -p"$DB_ROOT_PASSWORD" --single-transaction --routines --events --triggers "$db" | gzip -c > "$out"; else mysqldump --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -p"$DB_ROOT_PASSWORD" --single-transaction --routines --events --triggers "$db" | gzip -c > "$out"; fi; echo "Dump completed: $out" ;;
    restore) file="$rest"; [ -f "$file" ] || file="$SERVER_DIR/$file"; [ -f "$file" ] || { echo "File not found: $rest"; return 0; }; db="$DB_NAME"; c=$(_dbcli); echo "Restoring $file into $db..."; if [[ "$file" == *.gz ]]; then gzip -dc "$file" | MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db"; else MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root "$db" < "$file"; fi; echo 'Restore completed.' ;;
    sql) c=$(_dbcli); if [ -n "$rest" ]; then MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e "$rest"; else MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root <&"$fd"; fi ;;
    root) local new="$rest"; if [ -z "$new" ]; then printf 'New root password: '; IFS= read -r -s new <&"$fd" || return 0; printf '\nConfirm root password: '; local confirm; IFS= read -r -s confirm <&"$fd" || return 0; printf '\n'; [ "$new" = "$confirm" ] || { echo 'Passwords do not match.'; return 0; }; fi; c=$(_dbcli); local q; q=$(printf '%s' "$new" | sed "s/'/''/g"); MYSQL_PWD="$DB_ROOT_PASSWORD" "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$q'; ALTER USER IF EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$q'; FLUSH PRIVILEGES;" && { DB_ROOT_PASSWORD="$new"; export DB_ROOT_PASSWORD; declare -F pf_users_store_root >/dev/null 2>&1 && pf_users_store_root "$new"; echo 'Root password successfully changed.'; } ;;
    mysql|mariadb) read -r -a argv <<< "$line"; unset 'argv[0]'; c=$(_dbcli); echo "Starting $c interactive console. Type exit or quit to return."; "$c" --protocol=tcp -h 127.0.0.1 -P "$DB_PORT" "${argv[@]}" <&"$fd"; echo 'Interactive console closed.' ;;
    *) return 1 ;;
  esac
  return 0
}
