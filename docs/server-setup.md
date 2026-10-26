# Конфигурация виртуальной машины devops-vm

Гипервизор: VirtualBox 7.x на хосте Windows. Гостевая система: Ubuntu Server 24.04.5 LTS.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя в VirtualBox | `devops-vm` |
| Тип и версия | Linux / Ubuntu (64-bit) |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ, динамически расширяемый (`devops-vm.vdi`) |
| Разметка | Use an entire disk, LVM, `/boot` 2 ГБ, `/` 11,5 ГБ |
| Установка | Ubuntu Server (не minimized), OpenSSH server, без Featured snaps |
| Имя узла | `devops-vm`, FQDN `devops-vm.devops.local` |

## 2. Сетевые интерфейсы

| Интерфейс | Тип адаптера | Адрес | Назначение |
|---|---|---|---|
| `enp0s3` | NAT | `10.0.2.15/24` | Доступ ВМ в Интернет (пакеты) и проброс порта SSH |
| `enp0s8` | Host-only | `192.168.56.101/24` (DHCP VirtualBox, диапазон `.101`–`.254`) | Связь хоста с ВМ, обращение к веб-серверу из браузера хоста |

Имя `devops.local` сопоставлено адресу `192.168.56.101` записью в `C:\Windows\System32\drivers\etc\hosts` на хосте.
На сервере в `/etc/hosts` строка `127.0.1.1 devops-vm.devops.local devops-vm`.

## 3. Правило проброса портов

Адаптер 1 (NAT), правило `ssh`:

| Параметр | Значение |
|---|---|
| Протокол | TCP |
| Адрес хоста | `127.0.0.1` |
| Порт хоста | `2222` |
| Адрес гостя | не задан |
| Порт гостя | `2222` (изменён с 22 после перенастройки sshd) |

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|---|---|---|
| `student` | `student`, `sudo` и др. (создан установщиком) | пароль, только консоль ВМ; по SSH вход запрещён (`AllowUsers devops`) |
| `devops` | `devops`, `sudo`, `users` | только ключ ed25519 (`~/.ssh/devops_vm` на хосте), пароль нужен лишь для `sudo` |

Права: `~/.ssh` = 700, `~/.ssh/authorized_keys` = 600. Файл `authorized_keys` не должен содержать BOM и CRLF.
Вход `root` по SSH запрещён.

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменялся (резервная копия `/etc/ssh/sshd_config.backup`).
Настройки в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Дополнительно:
- в `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована (иначе она перекрывает значение из `99-hardening.conf`, побеждает первое встреченное значение);
- сокетная активация отключена: `systemctl disable --now ssh.socket`, `systemctl enable --now ssh.service`, затем `systemctl restart ssh` (иначе порт остаётся 22);
- проверка: `sudo sshd -t`, действующие значения `sudo sshd -T`.

Клиентская настройка на хосте (`~/.ssh/config`):

```
Host devops devops.local
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 6. Правила межсетевого экрана

Политики по умолчанию: `deny incoming`, `allow outgoing`, `disabled (routed)`. Логирование `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| `2222/tcp` | `LIMIT` | SSH, блокировка источника при 6 и более соединениях за 30 с |
| `80/tcp` | `ALLOW` | HTTP |
| `443/tcp` | `ALLOW` | HTTPS |

Порядок включения: сначала `ufw allow`, затем `ufw enable`. Команда `ufw allow ssh` не используется (она открыла бы порт 22).
Журнал блокировок: `/var/log/ufw.log`.

Команды:

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw enable
```

## 7. Снимки состояния

| Имя | Момент создания (26.10.2026) | Состояние |
|---|---|---|
| `01-clean-install` | 17:58 | чистая установка, система обновлена |
| `02-keys-configured` | 18:22 | пользователь `devops`, ключи, `~/.ssh/config` |
| `03-ssh-hardened` | 18:36 | SSH на порту 2222, парольный вход отключён |
| `04-nginx-https` | 19:33 | Nginx, самоподписанный сертификат, HTTPS, редирект с HTTP |

Настройка UFW и доменного имени выполнена после снимка `03-ssh-hardened` и отдельным снимком не фиксировалась: она входит в состояние снимка `04-nginx-https` и текущее состояние машины.

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` 1.24.0 (репозиторий Ubuntu 24.04), служба `nginx.service`, автозапуск включён |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, активирована ссылкой в `/etc/nginx/sites-enabled/`; стандартный ресурс (`sites-enabled/default`) отключён |
| Имя ресурса | `server_name devops.local` |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталог `755`, файлы `644` |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Сертификат | `/etc/ssl/certs/devops.crt`, владелец `root`, права `644` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, владелец `root`, права `600` |
| Срок действия сертификата | 365 дней, самоподписанный, поле SAN `DNS:devops.local` |
| Протоколы | TLSv1.2, TLSv1.3 |

Команда формирования сертификата:

```
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Структура конфигурации `devops-site`: блок `listen 80` с `return 301 https://$host$request_uri;` и блок `listen 443 ssl` с параметрами сертификата и ключа, `root /var/www/devops-site`, `index index.html`, `error_page 404 /404.html`.

Применение: `sudo nginx -t && sudo systemctl reload nginx` (не `restart`).

Порты 80 и 443 уже разрешены в UFW (раздел 6); правило `ufw allow 'Nginx Full'` не создаётся.

Доставка содержимого: `scripts/deploy.sh` (rsync с `--delete --chmod=D755,F644`, без интерактивного ввода пароля) с хоста. Сертификат для проверки на хосте: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`, затем `curl --cacert ~/devops.crt https://devops.local`.
