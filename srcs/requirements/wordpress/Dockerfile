FROM debian:bookworm

# Pinned versions; hashes checked against the official publications
ARG WP_VERSION=7.1.3
ARG WP_SHA256=d2a09acb6a15e3b9c471d72557753c266d6f41a79ed19bfe04cbfe49e283b2a5
ARG WPCLI_VERSION=2.12.0
ARG WPCLI_SHA512=be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		php8.2-fpm php8.2-cli php8.2-mysql php8.2-curl php8.2-gd \
		php8.2-mbstring php8.2-xml php8.2-zip curl ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /tmp/wordpress.tar.gz https://wordpress.org/wordpress-${WP_VERSION}.tar.gz \
	&& echo "${WP_SHA256}  /tmp/wordpress.tar.gz" | sha256sum -c - \
	&& tar -xzf /tmp/wordpress.tar.gz -C /usr/src \
	&& rm /tmp/wordpress.tar.gz \
	&& curl -fsSLo /usr/local/bin/wp https://github.com/wp-cli/wp-cli/releases/download/v${WPCLI_VERSION}/wp-cli-${WPCLI_VERSION}.phar \
	&& echo "${WPCLI_SHA512}  /usr/local/bin/wp" | sha512sum -c - \
	&& chmod 755 /usr/local/bin/wp

# PHP-FPM listens on TCP 9000 (reachable only through the Docker network)
RUN sed -i 's|^listen = .*|listen = 9000|' /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm8.2", "-F"]
