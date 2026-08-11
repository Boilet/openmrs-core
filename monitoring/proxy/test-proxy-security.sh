#!/usr/bin/env bash
# Smoke test del wrapper de seguridad del proxy TLS (ver docs/arquitectura-seguridad.md).
#
# Verifica contra un stack YA CORRIENDO (docker compose -f docker-compose.yml
# -f docker-compose.override.yml -f docker-compose.proxy.yml up -d) que:
#   1. El puerto HTTP del proxy SOLO redirige a HTTPS (nunca sirve contenido en claro).
#   2. El Set-Cookie de sesion en HTTPS trae Secure + HttpOnly + SameSite.
#   3. Los headers de seguridad (HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy)
#      estan presentes.
#   4. (opcional, --network <nombre>) prueba negativa: pegarle directo a `api` (bypaseando el
#      proxy) SI debe carecer de Secure/SameSite - confirma que el chequeo tiene dientes, no que
#      siempre pasa. Requiere Docker (usa un contenedor curlimages/curl efimero en esa red).
#
# Uso:
#   OMRS_HTTP_HOST_PORT=8083 OMRS_HTTPS_HOST_PORT=8446 bash monitoring/proxy/test-proxy-security.sh
#   bash monitoring/proxy/test-proxy-security.sh --network openmrs-core_default
#
# Exit code 0 si todo pasa, 1 si algo falla (usable como gate manual o en CI).
set -u

HTTP_PORT="${OMRS_HTTP_HOST_PORT:-8083}"
HTTPS_PORT="${OMRS_HTTPS_HOST_PORT:-8446}"
NETWORK=""
FAILURES=0

while [ $# -gt 0 ]; do
	case "$1" in
		--network)
			NETWORK="$2"
			shift 2
			;;
		--http-port)
			HTTP_PORT="$2"
			shift 2
			;;
		--https-port)
			HTTPS_PORT="$2"
			shift 2
			;;
		*)
			echo "Argumento desconocido: $1" >&2
			exit 2
			;;
	esac
done

fail() {
	echo "  FALLO: $1"
	FAILURES=$((FAILURES + 1))
}

ok() {
	echo "  OK: $1"
}

echo "== 1. HTTP (puerto $HTTP_PORT) debe redirigir a HTTPS, nunca servir contenido en claro =="
http_headers=$(curl -sk -D - -o /dev/null --max-time 10 "http://localhost:${HTTP_PORT}/openmrs/" 2>&1)
status_line=$(printf '%s\n' "$http_headers" | head -1 | tr -d '\r')
location=$(printf '%s\n' "$http_headers" | grep -i '^Location:' | tr -d '\r')

if printf '%s' "$status_line" | grep -qE ' 30[1278] '; then
	ok "responde con redirect ($status_line)"
else
	fail "esperaba 301/302/307/308, obtuvo: $status_line"
fi

if printf '%s' "$location" | grep -qi 'https://'; then
	ok "redirige a HTTPS ($location)"
else
	fail "el header Location no apunta a https:// ($location)"
fi

echo
echo "== 2. HTTPS (puerto $HTTPS_PORT): Set-Cookie con Secure + HttpOnly + SameSite =="
https_headers=$(curl -sk -D - -o /dev/null --max-time 10 "https://localhost:${HTTPS_PORT}/openmrs/index.htm" 2>&1)
cookie=$(printf '%s\n' "$https_headers" | grep -i '^Set-Cookie:')

if [ -z "$cookie" ]; then
	fail "no se recibio ningun Set-Cookie - revisar que /openmrs/index.htm siga abriendo sesion"
else
	for flag in Secure HttpOnly SameSite; do
		if printf '%s' "$cookie" | grep -qi "$flag"; then
			ok "cookie trae $flag"
		else
			fail "cookie NO trae $flag ($cookie)"
		fi
	done
fi

echo
echo "== 3. Headers de seguridad en la respuesta HTTPS =="
for h in "Strict-Transport-Security" "X-Content-Type-Options" "X-Frame-Options" "Referrer-Policy"; do
	if printf '%s\n' "$https_headers" | grep -qi "^${h}:"; then
		ok "header $h presente"
	else
		fail "header $h ausente"
	fi
done

if [ -n "$NETWORK" ]; then
	echo
	echo "== 4. Prueba negativa: api:8080 directo (bypaseando el proxy) NO debe traer Secure/SameSite =="
	direct_headers=$(docker run --rm --network "$NETWORK" curlimages/curl:8.12.1 -s --max-time 10 \
		"http://api:8080/openmrs/index.htm" -D - -o /dev/null 2>&1)
	direct_cookie=$(printf '%s\n' "$direct_headers" | grep -i '^Set-Cookie:')

	if [ -z "$direct_cookie" ]; then
		fail "no se pudo alcanzar api:8080 en la red '$NETWORK' para la prueba negativa"
	elif printf '%s' "$direct_cookie" | grep -qi 'Secure'; then
		fail "api:8080 SIN el proxy ya trae Secure - o cambio algo en el core, o esta prueba ya no es un control negativo valido"
	else
		ok "confirmado: sin el proxy, la cookie carece de Secure/SameSite (por eso existe el wrapper)"
	fi
fi

echo
if [ "$FAILURES" -eq 0 ]; then
	echo "TODO OK - el wrapper de seguridad del proxy esta funcionando como se documenta en docs/arquitectura-seguridad.md."
	exit 0
else
	echo "$FAILURES chequeo(s) fallaron - ver detalle arriba y el runbook en docs/arquitectura-seguridad.md #7."
	exit 1
fi
