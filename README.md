*This project has been created as part of the 42 curriculum by mzabal-m.*

# Inception

## Description

Inception is a system administration and Docker project from the 42 curriculum. The goal is to build a small infrastructure composed of several Docker containers running different services, while following strict rules about isolation, persistence, security and networking.

This project deploys a WordPress website through three custom Docker images:

- **NGINX**: the public entry point and HTTPS reverse proxy.
- **WordPress**: the PHP-FPM application server hosting the website.
- **MariaDB**: the relational database used by WordPress.

The services are built from Debian Bookworm-based Dockerfiles and orchestrated with Docker Compose. Only NGINX exposes a port to the host: HTTPS on port `443`. WordPress and MariaDB communicate through a private Docker bridge network.

### Project architecture

```text
                         HTTPS :443
                              |
                              v
                    +-------------------+
                    |       nginx       |
                    | TLS reverse proxy |
                    +---------+---------+
                              |
                     Docker network: inception
                              |
                              v
                    +-------------------+
                    |     wordpress     |
                    | PHP-FPM + WP-CLI  |
                    +---------+---------+
                              |
                              v
                    +-------------------+
                    |      mariadb      |
                    |  WordPress data   |
                    +-------------------+
```

### Main design choices

- **One service per container**: NGINX, WordPress and MariaDB have separate responsibilities and lifecycles.
- **Custom images**: every required service is built from a project Dockerfile instead of relying only on pre-built application images.
- **Private service network**: only NGINX is reachable from outside the Docker network.
- **HTTPS only**: NGINX serves the website over TLS 1.2 and TLS 1.3 on port `443`.
- **Persistent data**: MariaDB data and WordPress files are stored in Docker named volumes backed by `/home/<login>/data/` on the host.
- **Health checks and dependencies**: WordPress waits for MariaDB to become healthy, and NGINX waits for WordPress PHP-FPM to become available.
- **Docker secrets**: passwords are mounted as files under `/run/secrets/` instead of being placed in the image or environment variables.
- **Restart policy**: services use `restart: unless-stopped` so that unexpected crashes are recovered automatically.

### Virtual Machines vs Docker

| Virtual Machines | Docker |
|---|---|
| Virtualizes an entire operating system, including its kernel. | Uses the host kernel while isolating applications in containers. |
| Usually requires more CPU, memory and disk space. | Containers are lightweight and start quickly. |
| Provides strong isolation between complete operating systems. | Provides process, filesystem and network isolation at the container level. |
| A separate VM is useful when a different kernel or operating system is required. | Docker is well suited to packaging and running the three services independently. |

This project runs inside a virtual machine, as required by the 42 subject, and uses Docker inside that VM to isolate and orchestrate the application services. The VM isolates the project from the host operating system, while Docker isolates the services from one another.

### Secrets vs Environment Variables

| Docker secrets | Environment variables |
|---|---|
| Mounted as files, normally under `/run/secrets/`. | Injected directly into the process environment. |
| Better suited for passwords and other sensitive values. | Convenient for non-sensitive configuration such as names, domains and titles. |
| Values do not appear in the image configuration or normal environment inspection. | Values can be exposed through process inspection, logs or container metadata. |
| Used in this project for database and WordPress passwords. | Used in this project for `LOGIN`, `DOMAIN_NAME`, database names and WordPress user information. |

The project deliberately keeps passwords out of `srcs/.env`. The environment file contains configuration names and non-secret settings, while the files in `secrets/` contain credentials and are ignored by Git.

### Docker Network vs Host Network

| Docker bridge network | Host network |
|---|---|
| Gives containers their own isolated network namespace. | Containers share the host network namespace. |
| Services can communicate using Docker service names such as `mariadb` and `wordpress`. | Services use the host's network interfaces and ports directly. |
| Allows the Compose file to expose only the required public port. | Reduces network isolation and increases the risk of port conflicts. |
| Used by this project through the `inception` bridge network. | Not used by this project. |

The bridge network is the safer and more explicit choice for this stack: MariaDB and WordPress remain internal, while NGINX is the only service publishing port `443`.

### Docker Volumes vs Bind Mounts

| Docker named volumes | Bind mounts |
|---|---|
| Managed through Docker and referenced by a volume name. | Map a specific host path directly into a container. |
| Reduce dependence on host filesystem details. | Provide precise control over the location of files. |
| Easy to attach to multiple containers when needed. | Useful when host-side access or a required path is important. |
| Used by this project as the Docker-facing storage abstraction. | Used as the underlying storage through the volume driver's `device` option. |

This project uses named volumes called `mariadb` and `wordpress`. Their local driver is configured with bind-style options so that the persistent data is stored at:

- `/home/<login>/data/mariadb`
- `/home/<login>/data/wordpress`

This combines Docker volume management with the host location required by the subject.

## Instructions

### Prerequisites

The project is designed to run in a Debian 12 virtual machine with:

- Docker Engine
- Docker Compose v2 (`docker compose`)
- GNU Make
- Git
- OpenSSL
- `curl`

The Linux user should be the 42 login because persistent data is created under `/home/<login>/data`.

### Installation and configuration

Clone the repository and enter its root directory:

```sh
git clone https://github.com/zabal42/inception42.git
cd inception42
```

Create the local environment file:

```sh
cp srcs/.env.example srcs/.env
```

Edit `srcs/.env` and replace every `CHANGE_ME`. In particular, configure:

- `LOGIN`: the current Linux/42 login, for example `mzabal-m`.
- `DOMAIN_NAME`: normally `<login>.42.fr`.
- MariaDB database and user names.
- The WordPress site title.
- The administrator and regular WordPress user names and e-mail addresses.

Create the local secrets directory from the provided examples:

```sh
cp -r secrets.example secrets
```

Replace the values in the files inside `secrets/`. For a new installation, random values can be generated with:

```sh
mkdir -m 700 secrets
openssl rand -base64 24 > secrets/db_root_password.txt
openssl rand -base64 24 > secrets/db_password.txt
printf 'WP_ADMIN_PASSWORD=%s\nWP_USER_PASSWORD=%s\n' \
    "$(openssl rand -base64 18)" "$(openssl rand -base64 18)" \
    > secrets/credentials.txt
chmod 600 secrets/*.txt
```

The `secrets/` directory must never be committed. It is intentionally excluded by `.gitignore`.

Add the configured domain to `/etc/hosts` if necessary:

```sh
printf '127.0.0.1 %s\n' "$(grep '^DOMAIN_NAME=' srcs/.env | cut -d= -f2-)" \
    | sudo tee -a /etc/hosts
```

### Build and start

From the repository root:

```sh
make
```

The default target validates the configuration, creates the persistent data directories, builds the three images and starts the services in the correct order.

The website is then available at:

```text
https://<login>.42.fr
```

The certificate is self-signed, so the browser will display a security warning the first time. This is expected for this project.

### Makefile commands

| Command | Description |
|---|---|
| `make` or `make all` | Validate configuration, build images and start the stack. |
| `make check` | Check `srcs/.env` and the local secret files. |
| `make dirs` | Validate configuration and create the data directories. |
| `make up` | Build and start the containers in detached mode. |
| `make down` | Stop and remove containers and the Docker network. |
| `make status` | Display the state of the containers. |
| `make clean` | Equivalent to `make down`. |
| `make fclean` | Stop the stack and remove the project images. Persistent data is kept. |
| `make re` | Perform `make fclean` and start the project again. |

None of these targets deletes the WordPress or MariaDB data. Data deletion must be performed manually and is irreversible.

### Useful Docker commands

```sh
# Show containers and health status
docker compose -f srcs/docker-compose.yml ps

# Follow logs for a service
docker compose -f srcs/docker-compose.yml logs -f wordpress

# Restart a service
docker compose -f srcs/docker-compose.yml restart wordpress

# Inspect the Docker network
docker network inspect inception_inception

# Test HTTPS while accepting the self-signed certificate
DOMAIN=$(grep '^DOMAIN_NAME=' srcs/.env | cut -d= -f2-)
curl -k -I "https://$DOMAIN"
```

## Project structure

```text
.
├── Makefile
├── README.md
├── DEV_DOC.md
├── USER_DOC.md
├── secrets.example/
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env.example
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        ├── nginx/
        └── wordpress/
```

- `srcs/docker-compose.yml` defines services, networks, volumes and secrets.
- `srcs/requirements/mariadb/` contains the MariaDB image and initialization logic.
- `srcs/requirements/wordpress/` contains the WordPress/PHP-FPM image and setup logic.
- `srcs/requirements/nginx/` contains the NGINX image, TLS configuration and reverse proxy setup.
- `DEV_DOC.md` contains detailed development, installation and recovery procedures.
- `USER_DOC.md` contains day-to-day usage instructions.
- `secrets.example/` provides templates without real credentials.

## Resources

### Official documentation and references

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Docker Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
- [Docker volumes](https://docs.docker.com/engine/storage/volumes/)
- [Docker networking overview](https://docs.docker.com/engine/network/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [WordPress Developer Resources](https://developer.wordpress.org/)
- [WP-CLI handbook](https://make.wordpress.org/cli/handbook/)
- [OpenSSL documentation](https://docs.openssl.org/)

### AI usage

AI was used as a documentation assistant for this project. In particular, it helped with:

- Structuring and proofreading this README in English.
- Explaining the conceptual comparisons required by the subject: virtual machines vs Docker, secrets vs environment variables, Docker networks vs host networking, and Docker volumes vs bind mounts.
- Improving the clarity of the installation, execution and project-structure instructions.
- Reviewing the wording of the technical explanations against the files already present in the repository.

AI was not used as a replacement for understanding or testing the infrastructure. The Dockerfiles, Compose configuration, Makefile, service scripts and project decisions remain the responsibility of the project author. Commands should be tested in the target virtual machine before being considered definitive.

## Additional documentation

For more detailed information, see:

- [Developer Documentation](DEV_DOC.md)
- [User Documentation](USER_DOC.md)
