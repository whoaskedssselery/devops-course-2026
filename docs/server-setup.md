# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | VirtualBox 7.2.20 |
| Наименование | `devops-vm` |
| Гостевая система | Ubuntu Server 24.04.5 LTS (64-bit), установка «Use an entire disk» |
| Оперативная память | 2048 МБ |
| Количество ядер процессора | 2 |
| Объём диска | 25 ГБ, динамически расширяемый |
| Имя узла | `devops-vm`, полное имя `devops-vm.devops.local` |

## 2. Сетевые интерфейсы

| Адаптер | Тип | Интерфейс | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | `enp0s3` | `10.0.2.15/24` | доступ в Интернет (репозитории пакетов), проброс порта SSH |
| 2 | Host-only (`vboxnet0`) | `enp0s8` | `192.168.56.101/24` | доступ с хостовой системы (SSH по имени, веб-сервер) |

Адрес хоста в сети Host-only — `192.168.56.1`. Имя `devops.local` сопоставлено адресу
`192.168.56.101` записью в файле `hosts` хостовой системы (`/etc/hosts`):
`192.168.56.101   devops.local`.

## 3. Правило проброса портов

| Параметр | Значение |
|---|---|
| Наименование | `ssh` |
| Протокол | TCP |
| Адрес хоста / порт хоста | `127.0.0.1` / `2222` |
| Адрес гостя / порт гостя | не задан / `2222` |

Порт гостя изменён с 22 на 2222 после смены порта службы SSH (раздел 5).

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|---|---|---|
| `student` | `adm`, `cdrom`, `sudo`, `dip`, `plugdev`, `lxd` | пароль (вход по SSH запрещён директивой `AllowUsers`), только консоль |
| `devops` | `devops`, `sudo`, `users` | по ключу ed25519 (`~/.ssh/devops_vm` на хосте), парольный вход по SSH отключён; пароль нужен только для `sudo` |

Права: `~/.ssh` — `700`, `~/.ssh/authorized_keys` — `600`.

## 5. Служба SSH

Порт и расположение конфигурации: порт `2222`, дополнение `/etc/ssh/sshd_config.d/99-hardening.conf`
(исходный `/etc/ssh/sshd_config` не изменялся, его копия — `/etc/ssh/sshd_config.backup`).

| Директива | Значение |
|---|---|
| `Port` | `2222` |
| `PermitRootLogin` | `no` |
| `PasswordAuthentication` | `no` |
| `PubkeyAuthentication` | `yes` |
| `PermitEmptyPasswords` | `no` |
| `MaxAuthTries` | `3` |
| `LoginGraceTime` | `30` |
| `AllowUsers` | `devops` |
| `X11Forwarding` | `no` |
| `ClientAliveInterval` / `ClientAliveCountMax` | `300` / `2` |

Особенности Ubuntu 24.04:

- В `/etc/ssh/sshd_config.d/50-cloud-init.conf` (создаётся при установке с включённой парольной
  аутентификацией) директива `PasswordAuthentication yes` закомментирована, иначе она (файлы
  читаются по порядку имён, действует первое значение) переопределила бы `99-hardening.conf`.
- Порт определяется сокет-активацией, поэтому выполнено
  `sudo systemctl disable --now ssh.socket && sudo systemctl enable --now ssh.service &&
  sudo systemctl restart ssh`. Проверка: `sudo ss -tlnp | grep sshd` (ожидается `0.0.0.0:2222`),
  действующие значения — `sudo sshd -T`.

## 6. Правила межсетевого экрана

Утилита `ufw`. Политики по умолчанию: входящий трафик — `deny`, исходящий — `allow`.
Журналирование — `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| `2222/tcp` | `LIMIT` | SSH rate-limited |
| `80/tcp` | `ALLOW` | HTTP |
| `443/tcp` | `ALLOW` | HTTPS |

Порядок создания (разрешающие правила — до включения экрана):

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
```

Команда `ufw allow ssh` не используется: имя `ssh` соответствует порту 22 по `/etc/services`.

## 7. Снимки состояния

| Наименование | Момент создания (UTC, 2026-10-19) | Состояние |
|---|---|---|
| `01-clean-install` | 15:18 | чистая установка Ubuntu Server 24.04, обновления |
| `02-keys-configured` | 15:23 | пользователь `devops`, вход по ключу, `~/.ssh/config` на хосте |
| `03-ssh-hardened` | 15:27 | усиление SSH: порт 2222, без `root` и паролей (межсетевой экран и имя узла настроены после снимка) |

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Устанавливаемый пакет | `nginx` 1.24.0 (репозиторий Ubuntu), `sudo apt install -y nginx` |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, активирована ссылкой в `/etc/nginx/sites-enabled/`; стандартный ресурс отключён (`sudo rm /etc/nginx/sites-enabled/default`) |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, права `755` (каталог) и `644` (файлы); содержимое доставляется `scripts/deploy.sh` (`rsync --delete --chmod=D755,F644`) |
| Сертификат | `/etc/ssl/certs/devops.crt`, владелец `root`, права `644`; срок действия — 365 суток (самоподписанный, SAN `DNS:devops.local`) |
| Закрытый ключ | `/etc/ssl/private/devops.key`, владелец `root`, права `600` |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |

Команда формирования сертификата:

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Конфигурация ресурса состоит из двух блоков `server`: блок на порту 80 возвращает
`301 https://$host$request_uri`; блок на порту 443 (`ssl`, `ssl_protocols TLSv1.2 TLSv1.3`) содержит
пути к сертификату и ключу, `root /var/www/devops-site`, `try_files $uri $uri/ =404`,
`error_page 404 /404.html` и отдельные журналы. Каталог ресурса: `sudo mkdir -p /var/www/devops-site`,
`sudo chown -R devops:devops /var/www/devops-site`. Применение конфигурации:
`sudo nginx -t && sudo systemctl reload nginx` (не `restart`). Заголовок HSTS не добавляется.
