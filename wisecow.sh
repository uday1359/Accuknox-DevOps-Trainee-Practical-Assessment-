#!/bin/bash

PORT=4499

echo "Starting Wisecow server on port $PORT..."

while true
do
  RESPONSE=$(fortune | cowsay)

  {
    echo -e "HTTP/1.1 200 OK\r\n"
    echo -e "Content-Type: text/plain\r\n"
    echo -e "\r\n"
    echo "$RESPONSE"
  } | nc -l -p $PORT

done
