#!/bin/sh
# Genera un certificado TLS autofirmado para desarrollo local si todavia no existe uno en el
# volumen compartido. Corre una sola vez como init-container (mismo patron que loki-init en
# docker-compose.grafana.yml): sale con exito y el contenedor no vuelve a arrancar.
#
# NO USAR EN PRODUCCION. Para un despliegue real, reemplazar el volumen `proxy-certs` montando
# un certificado emitido por una CA real (Let's Encrypt, CA corporativa, etc.) en dev.crt/dev.key,
# o apuntar ssl_certificate/ssl_certificate_key en default.conf.template a esos ficheros.
set -eu

CERT_DIR=/certs
CRT="$CERT_DIR/dev.crt"
KEY="$CERT_DIR/dev.key"

if [ -f "$CRT" ] && [ -f "$KEY" ]; then
	echo "Certificado de desarrollo ya existe en $CERT_DIR, no se regenera."
	exit 0
fi

apk add --no-cache openssl >/dev/null

openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
	-keyout "$KEY" -out "$CRT" \
	-subj "/CN=localhost" \
	-addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

chmod 644 "$CRT"
chmod 600 "$KEY"

echo "Certificado de desarrollo autofirmado generado en $CERT_DIR (valido 825 dias)."
echo "El navegador/cliente HTTP va a marcarlo como no confiable la primera vez: es esperado en dev."
echo "Para produccion, reemplazar por un certificado real (ver comentario al inicio de este script)."
