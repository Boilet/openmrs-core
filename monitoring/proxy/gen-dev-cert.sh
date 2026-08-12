#!/bin/sh
# Genera una CA local de desarrollo y un certificado TLS para localhost firmado por ella —mismo
# patron de dos niveles que herramientas como mkcert, pero generado 100% dentro de Docker con
# openssl, sin depender de ningun binario instalado en el host (Windows, macOS o Linux)—. Corre
# una sola vez como init-container (mismo patron que loki-init en docker-compose.grafana.yml):
# sale con exito y el contenedor no vuelve a arrancar.
#
# NO USAR EN PRODUCCION. Para un despliegue real, reemplazar el volumen `proxy-certs` montando un
# certificado emitido por una CA real (Let's Encrypt, CA corporativa, etc.) en dev.crt/dev.key, o
# apuntar ssl_certificate/ssl_certificate_key en default.conf.template a esos ficheros.
set -eu

CERT_DIR=/certs
CA_KEY="$CERT_DIR/ca.key"
CA_CRT="$CERT_DIR/ca.crt"
CRT="$CERT_DIR/dev.crt"
KEY="$CERT_DIR/dev.key"
CA_EXPORT_DIR=/ca-export

apk add --no-cache openssl >/dev/null

if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CRT" ]; then
	echo "Generando CA local de desarrollo en $CERT_DIR..."
	openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
		-keyout "$CA_KEY" -out "$CA_CRT" \
		-subj "/CN=Seguimiento Oncologico Dev CA"
	chmod 600 "$CA_KEY"
	chmod 644 "$CA_CRT"
else
	echo "CA local de desarrollo ya existe en $CERT_DIR, no se regenera (evita romper la confianza que el host ya le haya otorgado)."
fi

if [ ! -f "$CRT" ] || [ ! -f "$KEY" ]; then
	echo "Emitiendo certificado de desarrollo para localhost, firmado por la CA local..."
	CSR="$CERT_DIR/dev.csr"
	EXT_FILE="$CERT_DIR/dev-ext.cnf"
	openssl req -nodes -newkey rsa:2048 \
		-keyout "$KEY" -out "$CSR" \
		-subj "/CN=localhost"
	printf "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1\n" > "$EXT_FILE"
	openssl x509 -req -in "$CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
		-out "$CRT" -days 825 -extfile "$EXT_FILE"
	rm -f "$CSR" "$EXT_FILE"
	chmod 644 "$CRT"
	chmod 600 "$KEY"
else
	echo "Certificado de desarrollo ya existe en $CERT_DIR, no se regenera."
fi

mkdir -p "$CA_EXPORT_DIR"
cp "$CA_CRT" "$CA_EXPORT_DIR/dev-ca.crt"

echo ""
echo "Listo. La CA local quedo exportada en monitoring/proxy/ca/dev-ca.crt (bind mount al host)."
echo "Para que el navegador/cliente HTTP confie en https://localhost sin advertencias, importarla"
echo "UNA VEZ al almacen de confianza del sistema operativo (ver docs/arquitectura-seguridad.md"
echo "para el comando exacto por plataforma). Sin ese paso, el navegador seguira marcando la"
echo "conexion como no confiable -- es esperado hasta que se haga esa importacion, no un error del"
echo "proxy ni del backend."
