#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         echo "Использование: scripts/deploy.sh [--dry-run]" >&2; exit 2 ;;
esac

cd "$REPO_ROOT"

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: site/index.html не найден, доставка отменена" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Предупреждение: в репозитории есть незафиксированные изменения" >&2
    else
        echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена" >&2
        exit 1
    fi
fi

# 3. Синхронизация каталога site/ на сервер (одно SSH-соединение, без пароля)
RSYNC_OPTS=(-avz --delete --chmod=D755,F644
            -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
[[ $DRY_RUN -eq 1 ]] && RSYNC_OPTS+=(--dry-run)

if ! rsync "${RSYNC_OPTS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"; then
    echo "Ошибка: синхронизация не выполнена" >&2
    exit 1
fi

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Пробный запуск завершён, состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности ресурса с проверкой сертификата
if ! curl -fsS --cacert "$CA_CERT" --max-time 10 -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: ${SITE_URL} недоступен после доставки" >&2
    exit 1
fi

echo "Доставлен коммит $(git rev-parse --short HEAD)"
exit 0
