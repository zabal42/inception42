# User Documentation

This document explains how to use the Inception stack once it has been set
up. For installation from scratch, see [DEV_DOC.md](DEV_DOC.md).

In the examples, `<login>` is the 42 login configured in `srcs/.env`
(for example `mzabal-m`), and every command is run from the root of the
repository inside the virtual machine.

## 1. Services provided by the stack

The stack serves a WordPress website over HTTPS. It is made of three
containers connected by a private Docker network called `inception`:

| Service     | Role                                                    | Reachable from the host |
|-------------|---------------------------------------------------------|-------------------------|
| `nginx`     | Single entry point. Terminates TLS (TLSv1.2 and TLSv1.3) and forwards PHP requests to WordPress | Yes, port **443** only |
| `wordpress` | WordPress with PHP-FPM, listening on port 9000           | No (internal network only) |
| `mariadb`   | MariaDB database used by WordPress, port 3306            | No (internal network only) |

The website and its database are stored on the host, so they survive
restarts (see [Data](#6-where-the-data-is)).

## 2. Starting and stopping the project

### Start

```sh
make
```

`make` checks the configuration, builds the images if needed and starts the
three containers in order: MariaDB, then WordPress, then NGINX. Each service
waits until the previous one reports itself healthy. Running `make` again
when everything is up changes nothing.

### Stop

```sh
make down
```

This stops and removes the containers and the network. **The website and the
database are kept**: the next `make` starts again with the same content.

### Other targets

| Command        | Effect                                                         |
|----------------|----------------------------------------------------------------|
| `make status`  | Lists the containers and their state                           |
| `make clean`   | Same as `make down`                                            |
| `make fclean`  | Stops the stack and removes the three images. Data is kept     |
| `make re`      | `make fclean` followed by `make`. Data is kept                 |

None of the Makefile targets deletes the website or the database.

## 3. Accessing the website and the administration panel

| Page                 | Address                                |
|----------------------|----------------------------------------|
| Website              | `https://<login>.42.fr`                |
| Administration panel | `https://<login>.42.fr/wp-admin`       |

- The domain must point to the virtual machine: `/etc/hosts` contains
  `127.0.0.1 <login>.42.fr` (see DEV_DOC.md).
- The certificate is self-signed, so the browser shows a security warning the
  first time. Accept it to continue. A new certificate is created whenever the
  `nginx` container is recreated, so the warning can appear again.
- Only HTTPS is available: port 80 is closed on purpose.

Two WordPress accounts exist:

| Account                       | Role          |
|-------------------------------|---------------|
| `WP_ADMIN_USER` in `srcs/.env` | Administrator |
| `WP_USER` in `srcs/.env`       | Author        |

## 4. Credentials

Credentials are never stored in Git. They live in two local places that Git
ignores:

| File                             | Content                                             |
|----------------------------------|-----------------------------------------------------|
| `srcs/.env`                      | Names only: domain, database name and user, WordPress user names and e-mails |
| `secrets/db_root_password.txt`   | Password of the MariaDB `root` account               |
| `secrets/db_password.txt`        | Password of the MariaDB account used by WordPress    |
| `secrets/credentials.txt`        | `WP_ADMIN_PASSWORD=...` and `WP_USER_PASSWORD=...`   |

To read a password, open the file in the virtual machine, for example
`cat secrets/credentials.txt`. Never paste these values into the repository,
an issue or a chat.

### Changing passwords

The secret files are used **only the first time** the stack initialises the
database and WordPress. Editing them afterwards does not change the existing
passwords:

- **WordPress accounts**: change the password from the administration panel
  (*Users* > *Profile*), then update `secrets/credentials.txt` if you want the
  file to stay in sync.
- **Lost administrator password**: see DEV_DOC.md, section 6.2.
- **WordPress database account**: see DEV_DOC.md, section 5.4.

## 5. Checking that the services are running

```sh
make status
```

Expected result: three containers `Up`, with `mariadb` and `wordpress`
marked `(healthy)`, and only `0.0.0.0:443->443/tcp` published for `nginx`.

More checks:

```sh
# The website answers over HTTPS (-k accepts the self-signed certificate)
DOMAIN=$(grep '^DOMAIN_NAME=' srcs/.env | cut -d= -f2-)
curl -k -I "https://$DOMAIN"

# Logs of one service
docker logs nginx
docker logs wordpress
docker logs mariadb

# The two WordPress accounts
docker exec wordpress runuser -u www-data -- env HOME=/tmp \
    wp --path=/var/www/html user list --fields=user_login,roles

# TLS: version 1.2 is accepted, version 1.1 is refused by the server
openssl s_client -connect 127.0.0.1:443 -tls1_2 < /dev/null
openssl s_client -connect 127.0.0.1:443 -tls1_1 -cipher 'DEFAULT:@SECLEVEL=0' < /dev/null
```

A container whose main process crashes is restarted automatically
(`restart: unless-stopped`). A container stopped on purpose with
`docker stop` or `docker kill` stays stopped until the next `make`.

## 6. Where the data is

| Data                   | Location on the host              |
|------------------------|-----------------------------------|
| WordPress database     | `/home/<login>/data/mariadb`      |
| WordPress files        | `/home/<login>/data/wordpress`    |

These folders are owned by the users of the containers (`mysql` and
`www-data`), so they may appear with other owner names on the host. Do not
edit or delete them by hand while the stack is running.
