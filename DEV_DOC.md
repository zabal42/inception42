# Developer Documentation

This document explains how to rebuild the project from scratch on a new
virtual machine, how it is configured, and how to manage its containers and
data. For day-to-day use, see [USER_DOC.md](USER_DOC.md).

In the text, `<login>` stands for the 42 login (for example `mzabal-m`).
Commands never contain `<login>`: they use `$USER` (the login of the Linux
user) or read the value from `srcs/.env`, so they can be copied as they are.

## 1. Setting up the environment from scratch

### 1.1 Prerequisites

| Item                  | Version used and tested                                  |
|-----------------------|----------------------------------------------------------|
| Virtual machine       | Debian 12 (bookworm) amd64, 2 CPU, 4 GB RAM, 40 GB disk  |
| Linux user            | Must be the 42 login: data is stored in `/home/<login>/data` |
| Docker Engine         | 29.9.2 (official Docker repository)                      |
| Docker Compose        | 5.6.1 (`docker-compose-plugin`)                          |
| Tools                 | `git`, `make`, `curl`, `openssl`                         |
| Network               | Internet access while installing and building the images |

### 1.2 Creating the virtual machine

In VirtualBox:

| Setting  | Value                                                     |
|----------|-----------------------------------------------------------|
| Type     | Linux, Debian (64-bit)                                    |
| CPU      | 2                                                         |
| Memory   | 4096 MB                                                   |
| Disk     | 40 GB VDI, dynamically allocated                          |
| Network  | NAT                                                       |
| ISO      | Debian 12 amd64 netinst (`debian-12.*-amd64-netinst.iso`) |

Optional: to work over SSH from the host, add the NAT port forwarding rule
`127.0.0.1:4242 -> 22`. The project itself does not use it.

Check the ISO against the `SHA256SUMS` file published in the same Debian
directory (that file is signed with the Debian CD signing key):

```sh
grep ' debian-12\..*-amd64-netinst\.iso$' SHA256SUMS | sha256sum -c -
```

Choices in the Debian installer:

- **User name**: your 42 login.
- **Root password**: leave it empty. The installer then installs `sudo` and
  gives sudo rights to your user.
- **Partitioning**: guided, use the entire disk, *All files in one partition*.
- **Software**: *Debian desktop environment*, *Xfce*, *SSH server* and
  *standard system utilities* (unselect GNOME). Firefox ESR comes with the
  desktop.

After the first boot, log in with your login and check that `id -un` prints
it and that `id -nG` contains `sudo`.

### 1.3 Preparing Debian

Run these commands once, logged in as your 42 login.

1. Base tools:

   ```sh
   sudo apt-get update
   sudo apt-get install ca-certificates curl git make gpg
   ```

2. Docker signing key. The key is installed only if its fingerprint is the
   official one; if `STOP` is printed, do not continue:

   ```sh
   curl -fsSL https://download.docker.com/linux/debian/gpg -o /tmp/docker.asc
   gpg --show-keys --with-colons /tmp/docker.asc | awk -F: '/^fpr/{print $10; exit}' \
       | grep -qx 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 \
       && sudo install -m 0644 -D /tmp/docker.asc /etc/apt/keyrings/docker.asc \
       && echo "Key OK" || echo "STOP: unexpected Docker key"
   ```

3. Docker repository and packages:

   ```sh
   sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<'EOF'
   Types: deb
   URIs: https://download.docker.com/linux/debian
   Suites: bookworm
   Components: stable
   Signed-By: /etc/apt/keyrings/docker.asc
   EOF
   sudo apt-get update
   sudo apt-get install docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin
   ```

4. Allow your user to run Docker, then log out and back in:

   ```sh
   sudo usermod -aG docker "$USER"
   ```

   **Warning**: members of the `docker` group can start containers that mount
   any host folder as root, so this group is equivalent to root access. Only
   add your own user, and only on this virtual machine.

5. Point the domain to the machine (nothing changes if the line already exists):

   ```sh
   grep -qE "^127\.0\.0\.1[[:space:]]+$USER\.42\.fr\$" /etc/hosts \
       || echo "127.0.0.1 $USER.42.fr" | sudo tee -a /etc/hosts
   ```

6. Check:

   ```sh
   docker version && docker compose version && getent hosts "$USER.42.fr"
   ```

### 1.4 Getting the project

Clone or copy the repository into your home folder and work from its root.
The repository contains no credentials: they are created locally in the next
steps.

### 1.5 Configuration files

| File                          | In Git | Purpose                                     |
|-------------------------------|--------|---------------------------------------------|
| `srcs/.env.example`           | Yes    | Template of the environment file            |
| `srcs/.env`                   | No     | Environment variables (names, no passwords) |
| `secrets.example/*.txt`       | Yes    | Templates of the secret files               |
| `secrets/*.txt`               | No     | Passwords, mounted as Docker secrets        |
| `srcs/docker-compose.yml`     | Yes    | Services, network, volumes and secrets      |
| `srcs/requirements/*/`        | Yes    | One Dockerfile per service, with its configuration and start script |

Create the environment file and replace every `CHANGE_ME`:

```sh
cp srcs/.env.example srcs/.env
```

`make check` only verifies that each variable below is present, not empty and
free of `CHANGE_ME`. The containers apply further checks when they start and
stop with a message if one fails:

| Variable         | Required by the subject       | Checked by the code                        | Recommended |
|------------------|-------------------------------|--------------------------------------------|-------------|
| `LOGIN`          | Data in `/home/login/data`    | Only `make check`                          | Same as `id -un`; `make` must be able to create `/home/$LOGIN/data` |
| `DOMAIN_NAME`    | Must be `login.42.fr`         | `wordpress`: letters, digits, `.` and `-`. `nginx`: valid host name (labels of letters, digits and `-`, ending in a top-level domain), at most 253 characters | `$LOGIN.42.fr` (the code does not compare it with `LOGIN`) |
| `MYSQL_DATABASE` | —                             | `mariadb`, `wordpress`: `[A-Za-z0-9_]`, 1 to 32 characters | `wordpress` |
| `MYSQL_USER`     | —                             | Same rule as `MYSQL_DATABASE`              | —           |
| `WP_TITLE`       | —                             | `wordpress`: not empty                     | —           |
| `WP_ADMIN_USER`  | Must not contain `admin` or `administrator` | `wordpress`: `[A-Za-z0-9_.-]`, 1 to 60 characters, and must not contain `admin` in any case | — |
| `WP_ADMIN_EMAIL` | —                             | `wordpress`: `text@text`, without spaces   | A real-looking address |
| `WP_USER`        | A second user                 | `wordpress`: same rule as `WP_ADMIN_USER` (without the `admin` restriction) and different from it, ignoring case | — |
| `WP_USER_EMAIL`  | —                             | Same rule as `WP_ADMIN_EMAIL`              | —           |

### 1.6 Secrets

Create the secret files with random values:

```sh
mkdir -m 700 secrets
openssl rand -base64 24 > secrets/db_root_password.txt
openssl rand -base64 24 > secrets/db_password.txt
printf 'WP_ADMIN_PASSWORD=%s\nWP_USER_PASSWORD=%s\n' \
    "$(openssl rand -base64 18)" "$(openssl rand -base64 18)" > secrets/credentials.txt
chmod 600 secrets/*.txt
```

What each file must contain, and what is really checked:

| File                    | `make check`                         | At container start |
|-------------------------|--------------------------------------|--------------------|
| `db_root_password.txt`  | Exists, not empty, no `CHANGE_ME`    | `mariadb`: not empty, one line |
| `db_password.txt`       | Exists, not empty, no `CHANGE_ME`    | `mariadb`: not empty, one line. `wordpress`: also no carriage return and no leading or trailing spaces |
| `credentials.txt`       | Exists, not empty, no `CHANGE_ME`    | `wordpress`: keys `WP_ADMIN_PASSWORD` and `WP_USER_PASSWORD` each exactly once at the start of a line; each value not empty, one line, no carriage return, no leading or trailing spaces |

- A final newline at the end of a file is fine.
- Special characters such as `' " \ $ ;` are supported.
- Not checked by the code: file permissions and password strength. Keep
  `secrets/` in mode 700 and the files in mode 600, and use random values.
- The procedures in section 5.4 assume passwords created with
  `openssl rand -base64`, which only contain letters, digits, `+`, `/` and `=`.
- The values are read **only during the first initialisation**. Changing a file
  afterwards does not change the existing passwords (see sections 5.4 and 6.2).

## 2. Building and launching the project

### 2.1 Makefile

| Target   | Effect                                                                  |
|----------|-------------------------------------------------------------------------|
| `all`    | Default target, same as `up`                                            |
| `check`  | Validates `srcs/.env` and `secrets/`; nothing is created if it fails     |
| `dirs`   | `check`, then creates `/home/$LOGIN/data/{mariadb,wordpress}`            |
| `up`     | `dirs`, then `docker compose up -d --build`                              |
| `down`   | Removes containers and network; volumes and data are kept               |
| `status` | `docker compose ps`                                                     |
| `clean`  | Same as `down`                                                          |
| `fclean` | `clean`, then removes the three images; volumes and data are kept       |
| `re`     | `fclean`, then `all`                                                    |

No target deletes data. Deleting it is a manual operation (section 5.5).

### 2.2 What happens on `make`

1. The three images are built from `debian:bookworm`. WordPress 7.1.3 and
   WP-CLI 2.12.0 are downloaded during the build and checked against pinned
   SHA-256 and SHA-512 hashes.
2. `mariadb` starts. On its first start with an empty data folder it creates
   the system tables, sets the `root` password (password login only, no
   `unix_socket`), removes the default `mysql@localhost` account, and creates
   the WordPress database and user. A marker file prevents this from running
   twice.
3. Once MariaDB is healthy, `wordpress` starts. On its first start it copies
   the WordPress files, writes `wp-config.php` with fresh random keys, installs
   WordPress and creates the two accounts. An interrupted installation is
   completed on the next start (section 6.3).
4. Once PHP-FPM is healthy, `nginx` starts, creates its self-signed
   certificate if needed and publishes port 443.

### 2.3 Docker Compose commands

Run from the root of the repository:

```sh
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f wordpress
docker compose -f srcs/docker-compose.yml build nginx
docker compose -f srcs/docker-compose.yml up -d nginx
docker compose -f srcs/docker-compose.yml restart wordpress
docker compose -f srcs/docker-compose.yml config
```

`nginx` finds `wordpress` by name when it starts. After **recreating**
`wordpress`, also run `docker compose -f srcs/docker-compose.yml restart nginx`
so that it uses the new container.

## 3. Managing containers

```sh
docker ps                                   # state and health
docker logs mariadb                         # start-up messages
docker exec -it wordpress sh                # shell in a container
docker exec mariadb cat /proc/1/comm        # main process (PID 1): mariadbd
docker inspect -f '{{.RestartCount}}' nginx # automatic restarts
```

Each container runs its service in the foreground as PID 1 (`mariadbd`,
`php-fpm8.2 -F`, `nginx -g 'daemon off;'`), without loops or `tail -f`.

To check the restart policy, kill the main process of **one** container from
the host. Use the PID that Docker reports for that container, never a
process-name search:

```sh
sudo kill -9 "$(docker inspect -f '{{.State.Pid}}' mariadb)"
docker ps    # mariadb is back, its restart count has increased
```

`docker stop` and `docker kill` count as a manual stop, so they do not trigger
a restart.

WordPress administration from the command line:

```sh
docker exec wordpress runuser -u www-data -- env HOME=/tmp \
    wp --path=/var/www/html user list
```

## 4. Network

| Element          | Value                                                       |
|------------------|-------------------------------------------------------------|
| Network          | `inception_inception`, bridge driver                       |
| Service names    | `mariadb`, `wordpress`, `nginx` (resolved by Docker DNS)    |
| Internal ports   | 3306 (MariaDB), 9000 (PHP-FPM)                              |
| Published ports  | 443 only, on `nginx`                                        |

```sh
docker network inspect inception_inception
```

## 5. Data and persistence

### 5.1 Volumes

| Named volume          | Mounted in                        | Host folder                     | Owner on the host |
|-----------------------|-----------------------------------|---------------------------------|-------------------|
| `inception_mariadb`   | `mariadb:/var/lib/mysql`          | `/home/<login>/data/mariadb`    | UID 100 (`mysql` in the container) |
| `inception_wordpress` | `wordpress:/var/www/html`, `nginx:/var/www/html` (read-only) | `/home/<login>/data/wordpress` | UID 33 (`www-data`) |

Both are Docker named volumes of the `local` driver; their `driver_opts`
place the data in `/home/<login>/data`:

```sh
docker volume ls
docker volume inspect inception_mariadb
```

### 5.2 What persists

| Event                                    | Database and website | TLS certificate |
|------------------------------------------|----------------------|-----------------|
| Container crash or restart               | Kept                 | Kept            |
| `make down` / `make` or `make re`        | Kept                 | New one         |
| Virtual machine reboot                   | Kept                 | Kept            |

### 5.3 Where the secrets go at run time

- Secrets are mounted read-only in `/run/secrets/` of the containers that need
  them; they never appear in the images, in `docker inspect` or in the
  environment.
- `wp-config.php` does not contain the database password. At each start the
  `wordpress` container copies it to `/run/wp/db_password`, an in-memory
  `tmpfs` readable only by `www-data`, and `wp-config.php` reads it from there.

### 5.4 Changing the WordPress database password

The secret file is only read during the first initialisation, so the new
password must also be applied in MariaDB. WordPress is stopped first so that
nothing uses the old password during the change. No password appears in
command arguments, in the shell history or in MariaDB logs: the SQL statement
goes through standard input and the root password through an option file read
from a pipe inside the container.

Run the steps in order, from the root of the repository, and only continue if
the previous step succeeded:

```sh
# 1. Stop WordPress (the website shows an error until step 5)
docker compose -f srcs/docker-compose.yml stop wordpress

# 2. New password (letters, digits, + / = only: safe inside SQL quotes)
(umask 077 && openssl rand -base64 24 > secrets/db_password.new)

# 3. Apply it in MariaDB
MYSQL_USER=$(grep '^MYSQL_USER=' srcs/.env | cut -d= -f2-)
printf "ALTER USER '%s'@'%%' IDENTIFIED BY '%s';\n" "$MYSQL_USER" "$(cat secrets/db_password.new)" \
    | docker exec -i mariadb bash -c \
        'mariadb --defaults-extra-file=<(printf "[client]\npassword=%s\n" "$(cat /run/secrets/db_root_password)") -u root' \
    && echo "Password changed in MariaDB"

# 4. Store it in the secret file (same file, so the containers see it)
cat secrets/db_password.new > secrets/db_password.txt && rm secrets/db_password.new

# 5. Start WordPress again (it reloads the password) and refresh nginx
docker compose -f srcs/docker-compose.yml up -d --no-deps --force-recreate wordpress
docker compose -f srcs/docker-compose.yml restart nginx
```

If step 3 fails, nothing has changed: delete `secrets/db_password.new` and run
`docker compose -f srcs/docker-compose.yml start wordpress`.

### 5.5 Deleting all data

**Irreversible.** Only when a completely fresh installation is wanted. Run the
whole block at once from the root of the repository. It stops at the first
failed check, and asks for confirmation before changing anything:

```sh
(
  set -eu
  LOGIN=$(grep '^LOGIN=' srcs/.env | cut -d= -f2-)
  DATA=/home/$LOGIN/data
  # LOGIN must be the current user, and every folder must be a real
  # directory at its canonical path (no symbolic link anywhere)
  [ -n "$LOGIN" ] && [ "$LOGIN" = "$(id -un)" ] \
      || { echo "STOP: LOGIN must be the current user"; exit 1; }
  for d in "$DATA" "$DATA/mariadb" "$DATA/wordpress"; do
      [ -d "$d" ] && [ ! -L "$d" ] && [ "$(realpath -e "$d")" = "$d" ] \
          || { echo "STOP: $d is not a real directory"; exit 1; }
  done
  # Human confirmation before any change to the system
  printf 'Type %s to delete %s/mariadb and %s/wordpress: ' "$LOGIN" "$DATA" "$DATA"
  read -r answer
  [ "$answer" = "$LOGIN" ] || { echo "Cancelled, nothing changed"; exit 1; }
  make fclean
  for v in inception_mariadb inception_wordpress; do
      docker volume inspect "$v" > /dev/null 2>&1 && docker volume rm "$v" > /dev/null
  done
  sudo rm -rf --one-file-system -- "$DATA/mariadb" "$DATA/wordpress"
  echo "Data deleted"
)
```

`sudo` is needed because the files belong to the container users. The next
`make` starts a fresh installation.

## 6. Troubleshooting and recovery

### 6.1 Messages

| Message                                                    | Meaning and action |
|------------------------------------------------------------|--------------------|
| `Error: srcs/.env not found` or `... still contains CHANGE_ME` | Complete sections 1.5 and 1.6 |
| `mariadb: /var/lib/mysql is not empty and was not initialised by this image` | The data folder contains unknown files. Nothing was changed; inspect or move the folder |
| `wordpress: /var/www/html is not empty and has no wp-config.php` | Same protection for the website folder |
| `wordpress: database unavailable at mariadb:3306`         | MariaDB is not reachable or the password does not match; check `docker logs mariadb` |
| `wordpress: WP_ADMIN_USER must not contain 'admin'`       | Choose another administrator login |
| `nginx: invalid DOMAIN_NAME`                               | Use a plain host name such as `<login>.42.fr` |
| Browser warning about the certificate                      | Expected: the certificate is self-signed |

### 6.2 Recovering the administrator account

If the administrator password is lost, set a new one from the command line.
The password is read from `secrets/credentials.txt` and sent through standard
input, so it never appears in command arguments. WP-CLI options such as
`--user_pass` are not used: they expose the password in the process list and
alter quotes and backslashes.

1. Edit `secrets/credentials.txt` with a text editor and write the new value
   on the `WP_ADMIN_PASSWORD=` line.
2. Apply it:

   ```sh
   ADMIN=$(grep '^WP_ADMIN_USER=' srcs/.env | cut -d= -f2-)
   grep '^WP_ADMIN_PASSWORD=' secrets/credentials.txt | cut -d= -f2- | tr -d '\n' \
       | docker exec -i wordpress runuser -u www-data -- env HOME=/tmp WP_LOGIN="$ADMIN" \
           wp --path=/var/www/html eval \
           '$u = get_user_by("login", getenv("WP_LOGIN")); if (!$u) exit(1); wp_set_password(stream_get_contents(STDIN), $u->ID); echo "Password updated", PHP_EOL;'
   ```

The same command with `WP_USER` and `WP_USER_PASSWORD` resets the second
account.

### 6.3 Interrupted first installation

While WordPress is being initialised, the file
`/home/<login>/data/wordpress/.inception-init-pending` lists the accounts whose
initial password is not set yet. If the first start is interrupted, start
WordPress again: it completes the pending steps and deletes the file. Accounts
that are not listed are never modified.

```sh
docker compose -f srcs/docker-compose.yml restart wordpress
docker logs wordpress
```

### 6.4 Changing the domain

1. Change `DOMAIN_NAME` in `srcs/.env` and add the new name to `/etc/hosts`
   (section 1.3, step 5).
2. Update WordPress and recreate `nginx` (it creates a certificate for the new
   name):

   ```sh
   NEW_DOMAIN=$(grep '^DOMAIN_NAME=' srcs/.env | cut -d= -f2-)
   for option in home siteurl; do
       docker exec wordpress runuser -u www-data -- env HOME=/tmp \
           wp --path=/var/www/html option update "$option" "https://$NEW_DOMAIN"
   done
   docker compose -f srcs/docker-compose.yml up -d --force-recreate nginx
   ```
