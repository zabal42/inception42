#!/bin/sh
set -eu

DATADIR=/var/lib/mysql
MARKER=$DATADIR/.inception-initialized

fail() { echo "mariadb: $*" >&2; exit 1; }

read_secret() {
	value=$(cat "/run/secrets/$1") || fail "cannot read secret $1"
	[ -n "$value" ] || fail "secret $1 is empty"
	[ "$(printf '%s' "$value" | wc -l)" -eq 0 ] || fail "secret $1 has several lines"
	printf '%s' "$value"
}

# Escape a value for a single-quoted SQL string literal
sql_string() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"
}

check_name() {
	printf '%s' "$2" | grep -Eqx '[A-Za-z0-9_]{1,32}' || fail "invalid $1"
}

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [ ! -f "$MARKER" ]; then
	[ -z "$(ls -A "$DATADIR")" ] || fail "$DATADIR is not empty and was not initialised by this image; refusing to touch it"
	check_name MYSQL_DATABASE "${MYSQL_DATABASE:-}"
	check_name MYSQL_USER "${MYSQL_USER:-}"
	root_pw=$(read_secret db_root_password)
	user_pw=$(read_secret db_password)
	root_pw=$(sql_string "$root_pw")
	user_pw=$(sql_string "$user_pw")
	# In database-level grants, _ is a wildcard: escape it
	grant_db=$(printf '%s' "$MYSQL_DATABASE" | sed 's/_/\\_/g')

	chown mysql:mysql "$DATADIR"
	mariadb-install-db --user=mysql --datadir="$DATADIR" --skip-test-db > /dev/null
	mariadbd --user=mysql --bootstrap --skip-networking > /dev/null 2>&1 <<-EOF || fail "bootstrap failed (output hidden to protect secrets)"
		FLUSH PRIVILEGES;
		ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$root_pw');
		DROP USER IF EXISTS 'mysql'@'localhost';
		CREATE DATABASE \`$MYSQL_DATABASE\`;
		CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$user_pw';
		GRANT ALL PRIVILEGES ON \`$grant_db\`.* TO '$MYSQL_USER'@'%';
		FLUSH PRIVILEGES;
	EOF
	touch "$MARKER"
fi

exec "$@"
