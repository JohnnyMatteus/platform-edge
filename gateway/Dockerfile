# Imagem do gateway: Kong OSS com o plugin token-policy e a configuração
# declarativa embutidos. A mesma imagem roda no compose e no chart Helm.
FROM kong:3.9.3

COPY plugins/kong/plugins/token-policy /usr/local/share/lua/5.1/kong/plugins/token-policy
COPY declarative/kong.yaml /kong/declarative/kong.yaml

ENV KONG_DATABASE=off \
    KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yaml \
    KONG_PLUGINS=bundled,token-policy \
    KONG_PROXY_LISTEN="0.0.0.0:8000" \
    KONG_ADMIN_LISTEN="127.0.0.1:8001" \
    KONG_STATUS_LISTEN="0.0.0.0:8100" \
    KONG_PROXY_ACCESS_LOG=off \
    KONG_PROXY_ERROR_LOG=/dev/stderr \
    KONG_ADMIN_ACCESS_LOG=off \
    KONG_HEADERS="X-Kong-Request-Id" \
    KONG_TRACING_INSTRUMENTATIONS=all \
    KONG_TRACING_SAMPLING_RATE=1.0 \
    KONG_NGINX_PROXY_CLIENT_BODY_BUFFER_SIZE=1m

USER kong
