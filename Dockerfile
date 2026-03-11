FROM ubuntu:22.04

RUN apt update && \
    apt install -y cowsay fortune netcat

WORKDIR /app

COPY wisecow.sh /app/wisecow.sh

RUN chmod +x /app/wisecow.sh

EXPOSE 4499

CMD ["./wisecow.sh"]