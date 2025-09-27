#!/usr/bin/env bash

PORT=${PORT:-4499}

echo "Starting Wisecow server on port $PORT..."

while true; do
    echo -e "HTTP/1.1 200 OK\nContent-Type: text/plain\n\n$(fortune | cowsay -f default)" | \
    socat - TCP-LISTEN:$PORT,reuseaddr,fork
done
