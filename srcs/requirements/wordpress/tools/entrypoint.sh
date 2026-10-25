#!/bin/sh
set -eu

WP_PATH=/var/www/html
SECRET_DIR=/run/wp
CREDENTIALS=/run/secrets/credentials
PENDING=$WP_PATH/.inception-init-pending

fail() { echo "wordpress: $*" >&2; exit 1; }

require_env() {
	for name in "$@"; do
		[ -n "$(printenv "$name" || true)" ] || fail "$name is not set"
	done
}

check_pattern() {
	printf '%s' "$2" | grep -Eqx "$3" || fail "invalid $1"
}

# Single line, no carriage return, no leading or trailing spaces
check_secret() {
	[ -n "$2" ] || fail "$1 is empty"
	[ "$(printf '%s' "$2" | wc -l)" -eq 0 ] || fail "$1 has several lines"
	case "$2" in *"$(printf '\r')"*) fail "$1 contains a carriage return" ;; esac
	case "$2" in [[:space:]]*|*[[:space:]]) fail "$1 has leading or trailing spaces" ;; esac
}

# Value of KEY=VALUE in the credentials secret; the key must appear exactly once
credential() {
	[ -r "$CREDENTIALS" ] || fail "cannot read secret credentials"
	count=$(grep -c "^$1=" "$CREDENTIALS" || true)
	[ "$count" -ne 0 ] || fail "$1 is missing in credentials"
	[ "$count" -eq 1 ] || fail "$1 is duplicated in credentials"
	grep "^$1=" "$CREDENTIALS" | cut -d= -f2-
}

wpcli() {
	runuser -u www-data -- env HOME=/tmp WP_CLI_CACHE_DIR=/tmp/wp-cli-cache \
		/usr/local/bin/wp --path="$WP_PATH" "$@"
}

# Password read from stdin and stored as given (wp-cli options alter quotes and backslashes)
set_password() {
	wpcli eval '$u = get_user_by("login", "'"$1"'");
		if (!$u) exit(1);
		wp_set_password(stream_get_contents(STDIN), $u->ID);' || fail "cannot set password for $1"
}

db_reachable() {
	runuser -u www-data -- php -r '
		mysqli_report(MYSQLI_REPORT_OFF);
		$db = mysqli_init();
		$db->options(MYSQLI_OPT_CONNECT_TIMEOUT, 5);
		$ok = @$db->real_connect("mariadb", getenv("MYSQL_USER"),
			file_get_contents("/run/wp/db_password"), getenv("MYSQL_DATABASE"), 3306);
		exit($ok ? 0 : 1);'
}

require_env DOMAIN_NAME MYSQL_DATABASE MYSQL_USER WP_TITLE \
	WP_ADMIN_USER WP_ADMIN_EMAIL WP_USER WP_USER_EMAIL
check_pattern DOMAIN_NAME "$DOMAIN_NAME" '[A-Za-z0-9.-]+'
check_pattern MYSQL_DATABASE "$MYSQL_DATABASE" '[A-Za-z0-9_]{1,32}'
check_pattern MYSQL_USER "$MYSQL_USER" '[A-Za-z0-9_]{1,32}'
check_pattern WP_ADMIN_USER "$WP_ADMIN_USER" '[A-Za-z0-9_.-]{1,60}'
check_pattern WP_USER "$WP_USER" '[A-Za-z0-9_.-]{1,60}'
check_pattern WP_ADMIN_EMAIL "$WP_ADMIN_EMAIL" '[^@[:space:]]+@[^@[:space:]]+'
check_pattern WP_USER_EMAIL "$WP_USER_EMAIL" '[^@[:space:]]+@[^@[:space:]]+'
! printf '%s' "$WP_ADMIN_USER" | grep -qi admin || fail "WP_ADMIN_USER must not contain 'admin'"
[ "$(printf '%s' "$WP_ADMIN_USER" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$WP_USER" | tr 'A-Z' 'a-z')" ] \
	|| fail "WP_ADMIN_USER and WP_USER must be different"

db_password=$(cat /run/secrets/db_password) || fail "cannot read secret db_password"
check_secret db_password "$db_password"
admin_password=$(credential WP_ADMIN_PASSWORD)
check_secret WP_ADMIN_PASSWORD "$admin_password"
user_password=$(credential WP_USER_PASSWORD)
check_secret WP_USER_PASSWORD "$user_password"

# The database password only lives in memory (tmpfs), readable by www-data alone
grep -q " $SECRET_DIR tmpfs " /proc/mounts || fail "$SECRET_DIR must be a tmpfs mount"
chown www-data:www-data "$SECRET_DIR"
chmod 700 "$SECRET_DIR"
(umask 377 && printf '%s' "$db_password" > "$SECRET_DIR/db_password")
chown www-data:www-data "$SECRET_DIR/db_password"

mkdir -p /run/php

if [ ! -f "$WP_PATH/wp-config.php" ]; then
	[ -z "$(ls -A "$WP_PATH")" ] || fail "$WP_PATH is not empty and has no wp-config.php; refusing to touch it"
	salts=$(php -r 'foreach (["AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
		"AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT"] as $k)
		printf("define(\"%s\", \"%s\");\n", $k, bin2hex(random_bytes(32)));')
	[ "$(printf '%s\n' "$salts" | wc -l)" -eq 8 ] || fail "cannot generate salts"

	cp -a /usr/src/wordpress/. "$WP_PATH/"
	cat > "$WP_PATH/wp-config.php" <<-EOF
	<?php
	define('DB_NAME', '$MYSQL_DATABASE');
	define('DB_USER', '$MYSQL_USER');
	define('DB_PASSWORD', file_get_contents('$SECRET_DIR/db_password'));
	define('DB_HOST', 'mariadb:3306');
	define('DB_CHARSET', 'utf8mb4');
	define('DB_COLLATE', '');
	$salts
	\$table_prefix = 'wp_';
	define('WP_DEBUG', false);
	if (!defined('ABSPATH')) {
		define('ABSPATH', __DIR__ . '/');
	}
	require_once ABSPATH . 'wp-settings.php';
	EOF
	chown -R www-data:www-data "$WP_PATH"
	chmod 640 "$WP_PATH/wp-config.php"
fi

db_reachable || fail "database unavailable at mariadb:3306"

# Accounts whose initial password is still pending are listed in the marker
# before they are created, and removed once their password is set, so an
# interrupted initialisation is completed on next start
pending_add() {
	grep -qx "$1" "$PENDING" 2> /dev/null || echo "$1" >> "$PENDING"
}

pending_done() {
	sed -i "/^$1\$/d" "$PENDING"
}

if ! wpcli core is-installed 2> /dev/null; then
	pending_add admin
	pending_add user
elif ! wpcli user get "$WP_USER" --field=ID > /dev/null 2>&1; then
	pending_add user
fi

if [ -f "$PENDING" ]; then
	if ! wpcli core is-installed 2> /dev/null; then
		wpcli core install --url="https://$DOMAIN_NAME" --title="$WP_TITLE" \
			--admin_user="$WP_ADMIN_USER" --admin_email="$WP_ADMIN_EMAIL" \
			--skip-email > /dev/null
		echo "wordpress: installed"
	fi
	if ! wpcli user get "$WP_USER" --field=ID > /dev/null 2>&1; then
		wpcli user create "$WP_USER" "$WP_USER_EMAIL" --role=author > /dev/null
		echo "wordpress: user $WP_USER created"
	fi
	if grep -qx admin "$PENDING"; then
		printf '%s' "$admin_password" | set_password "$WP_ADMIN_USER"
		pending_done admin
		echo "wordpress: password set for $WP_ADMIN_USER"
	fi
	if grep -qx user "$PENDING"; then
		printf '%s' "$user_password" | set_password "$WP_USER"
		pending_done user
		echo "wordpress: password set for $WP_USER"
	fi
	rm -f "$PENDING"
fi

unset db_password admin_password user_password
exec "$@"
