#!/usr/bin/env bash
# Local certificate authority and an HTTPS certificate for the Mac's address in the Wi-Fi network.
# Safari gives a page the camera only over HTTPS, and an HTTPS page may call only HTTPS, so Caddy
# (server/docker-compose.yml, profile "lan") serves the game, the admin panel and Nakama with it.
#
#   tools/lan/make-certs.sh 10.20.30.40
#
# The CA is made once and kept in server/certs (ignored by git). Phones trust it after installing
# server/certs/public/office-game-ca.cer (served at http://<ip>:8080). The Mac's own trust store is
# not touched. The server certificate is remade when the address changes.
set -euo pipefail

ip="${1:?usage: $0 <lan ip>}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
dir="$root/server/certs"
public="$dir/public"
mkdir -p "$public"
chmod 700 "$dir"

if [[ ! -f "$dir/rootCA.key" ]]; then
	echo "Creating the local certificate authority..."
	openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
		-keyout "$dir/rootCA.key" -out "$dir/rootCA.crt" \
		-subj "/O=Office Game LAN/CN=Office Game LAN CA" \
		-addext "basicConstraints=critical,CA:TRUE" \
		-addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
	chmod 600 "$dir/rootCA.key"
fi

if [[ -f "$dir/server.crt" && "$(cat "$dir/server.ip" 2>/dev/null)" == "$ip" ]]; then
	echo "Certificate for $ip is up to date."
else
	echo "Creating the HTTPS certificate for $ip..."
	extensions="$(mktemp)"
	trap 'rm -f "$extensions" "$dir/server.csr"' EXIT
	cat >"$extensions" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:$ip,IP:127.0.0.1,DNS:localhost
EOF
	openssl req -newkey rsa:2048 -sha256 -nodes -keyout "$dir/server.key" -out "$dir/server.csr" \
		-subj "/O=Office Game LAN/CN=$ip" 2>/dev/null
	# iOS accepts certificates of a private CA for at most 825 days; 397 is safe everywhere.
	openssl x509 -req -in "$dir/server.csr" -CA "$dir/rootCA.crt" -CAkey "$dir/rootCA.key" -CAcreateserial \
		-days 397 -sha256 -extfile "$extensions" -out "$dir/server.crt" 2>/dev/null
	chmod 600 "$dir/server.key"
	echo "$ip" >"$dir/server.ip"
fi

# The public part of the CA and a page with install steps, served over plain HTTP on port 8080.
openssl x509 -in "$dir/rootCA.crt" -outform der -out "$public/office-game-ca.cer"
cat >"$public/index.html" <<EOF
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Office Game: сертификат</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;margin:24px;line-height:1.5;max-width:560px}
a.button{display:block;background:#ef3124;color:#fff;text-align:center;padding:14px;border-radius:10px;text-decoration:none;font-weight:600}</style>
</head><body>
<h1>Office Game в локальной сети</h1>
<p>Один раз на каждом телефоне:</p>
<ol>
<li><a class="button" href="office-game-ca.cer">Скачать сертификат</a><br>Safari спросит, разрешить ли загрузку профиля. Нажмите «Разрешить».</li>
<li>Настройки → Основные → VPN и управление устройством → «Office Game LAN CA» → Установить.</li>
<li>Настройки → Основные → Об этом устройстве → Доверие сертификатам → включить «Office Game LAN CA».</li>
</ol>
<p>После этого:</p>
<ul>
<li>Игра: <a href="https://$ip:8443">https://$ip:8443</a></li>
<li>Админка: <a href="https://$ip:5443">https://$ip:5443</a></li>
</ul>
</body></html>
EOF
echo "Certificates are in server/certs."
