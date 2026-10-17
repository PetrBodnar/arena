# Makefile проекта Arena — уровень M0.
# Главные команды: make up и make down. Полный список: make help.
#
# Синтаксис Make: строки команд (рецепты) начинаются с ТАБА, а не с пробелов.
# Если редактор заменил таб на пробелы, make ответит «missing separator».

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Параметры можно переопределить при вызове: make up CLUSTER=test
CLUSTER    ?= arena
K3D_CONFIG ?= k3d/arena.yaml
CONTEXT    := k3d-$(CLUSTER)
KUBECTL    := kubectl --context $(CONTEXT)

# Без этих программ ничего не заработает — их проверяет make check
TOOLS := docker k3d kubectl helm

# Цели ниже — команды, а не файлы. .PHONY говорит об этом make
.PHONY: help tools check up down stop start status

help: ## Показать список команд
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "} {printf "  make %-8s %s\n", $$1, $$2}'

tools: ## Поставить все инструменты из Brewfile
	brew bundle --file=Brewfile

check: ## Проверить, что инструменты стоят и Docker запущен
	@for t in $(TOOLS); do \
		command -v $$t >/dev/null 2>&1 || { echo "Нет $$t. Запустите: make tools"; exit 1; }; \
	done
	@docker info >/dev/null 2>&1 || { echo "Docker не отвечает. Запустите OrbStack"; exit 1; }
	@echo "OK: инструменты на месте, Docker работает"

up: check ## Создать кластер или поднять существующий
	@if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $$1}' | grep -qx '$(CLUSTER)'; then \
		echo "Создаю кластер $(CLUSTER)"; \
		k3d cluster create $(CLUSTER) --config $(K3D_CONFIG); \
	elif [ "$$(docker inspect -f '{{.State.Running}}' k3d-$(CLUSTER)-server-0 2>/dev/null)" != "true" ]; then \
		echo "Кластер $(CLUSTER) остановлен, запускаю"; \
		k3d cluster start $(CLUSTER); \
	else \
		echo "Кластер $(CLUSTER) уже работает"; \
	fi
	@$(KUBECTL) wait --for=condition=Ready nodes --all --timeout=180s
	@$(MAKE) --no-print-directory status

down: ## Удалить кластер целиком (всё внутри пропадёт)
	k3d cluster delete $(CLUSTER)

stop: ## Остановить кластер, не удаляя (освободить память)
	k3d cluster stop $(CLUSTER)

start: ## Запустить остановленный кластер
	k3d cluster start $(CLUSTER)
	@$(KUBECTL) wait --for=condition=Ready nodes --all --timeout=180s

status: ## Показать ноды, StorageClass и системные поды
	@$(KUBECTL) get nodes -L kubernetes.io/arch
	@echo
	@$(KUBECTL) get storageclass
	@echo
	@$(KUBECTL) -n kube-system get pods
