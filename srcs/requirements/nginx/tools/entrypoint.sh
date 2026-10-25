#!/bin/sh
set -eu

SSL_DIR=/etc/nginx/ssl
CERT=$SSL_DIR/inception.crt
KEY=$SSL_DIR/inception.key

fail() { echo "nginx: $*" >&2; exit 1; }

# Hostname labels only: safe to use in the template and in the certificate subject
DOMAIN_NAME=${DOMAIN_NAME:-}
[ "${#DOMAIN_NAME}" -le 253 ] || fail "DOMAIN_NAME is too long"
printf '%s' "$DOMAIN_NAME" \
	| grep -Eqx '([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}' \
	|| fail "invalid DOMAIN_NAME"

# Self-signed certificate generated in the container, never stored in the image
if [ ! -f "$KEY" ] || [ ! -f "$CERT" ] \
	|| [ "$(openssl x509 -in "$CERT" -noout -subject -nameopt RFC2253)" != "subject=CN=$DOMAIN_NAME" ]; then
	mkdir -p "$SSL_DIR"
	chmod 700 "$SSL_DIR"
	(umask 077 && openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
		-keyout "$KEY" -out "$CERT" \
		-subj "/CN=$DOMAIN_NAME" -addext "subjectAltName=DNS:$DOMAIN_NAME" 2> /dev/null) \
		|| fail "cannot generate the TLS certificate"
	chmod 644 "$CERT"
	echo "nginx: certificate generated for $DOMAIN_NAME"
fi

sed "s/@DOMAIN_NAME@/$DOMAIN_NAME/g" /etc/nginx/templates/inception.conf \
	> /etc/nginx/conf.d/inception.conf
nginx -t 2> /dev/null || fail "invalid nginx configuration"

exec "$@"
