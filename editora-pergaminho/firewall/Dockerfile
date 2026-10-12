FROM alpine:3.20
RUN apk add --no-cache iptables iproute2 tcpdump conntrack-tools \
    && (apk add --no-cache iptables-legacy || true)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
