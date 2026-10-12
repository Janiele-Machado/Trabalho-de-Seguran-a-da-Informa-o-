FROM alpine:3.20
RUN apk add --no-cache curl nmap netcat-openbsd iproute2 bind-tools
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
