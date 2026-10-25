COMPOSE   := docker compose -f srcs/docker-compose.yml
ENV_FILE  := srcs/.env
ENV_KEYS  := LOGIN DOMAIN_NAME MYSQL_DATABASE MYSQL_USER \
             WP_TITLE WP_ADMIN_USER WP_ADMIN_EMAIL WP_USER WP_USER_EMAIL
SECRETS   := secrets/db_root_password.txt secrets/db_password.txt secrets/credentials.txt

LOGIN     := $(shell grep -E '^LOGIN=' $(ENV_FILE) 2>/dev/null | tail -n 1 | cut -d= -f2-)
DATA_DIR  := /home/$(LOGIN)/data

all: up

check:
	@test -f $(ENV_FILE) || { echo "Error: $(ENV_FILE) not found. Copy srcs/.env.example and fill it in."; exit 1; }
	@for key in $(ENV_KEYS); do \
		value=$$(grep -E "^$$key=" $(ENV_FILE) | tail -n 1 | cut -d= -f2-); \
		if [ -z "$$value" ] || echo "$$value" | grep -q CHANGE_ME; then \
			echo "Error: $$key is missing or not set in $(ENV_FILE)."; exit 1; \
		fi; \
	done
	@for file in $(SECRETS); do \
		if [ ! -f $$file ] || [ ! -s $$file ]; then \
			echo "Error: $$file is missing or empty. See secrets.example/."; exit 1; \
		fi; \
		if grep -q CHANGE_ME $$file; then \
			echo "Error: $$file still contains CHANGE_ME."; exit 1; \
		fi; \
	done
	@echo "Configuration OK."

dirs: check
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

up: dirs
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

status:
	$(COMPOSE) ps

clean: down

fclean: clean
	$(COMPOSE) down --rmi all

re: fclean all

.PHONY: all check dirs up down status clean fclean re
