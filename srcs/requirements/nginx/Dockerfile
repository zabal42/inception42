FROM debian:bookworm

RUN apt-get update \
	&& apt-get install -y --no-install-recommends nginx openssl \
	&& rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default \
	&& sed -i 's|^\(\s*ssl_protocols\).*|\1 TLSv1.2 TLSv1.3;|' /etc/nginx/nginx.conf

COPY conf/inception.conf /etc/nginx/templates/inception.conf
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
