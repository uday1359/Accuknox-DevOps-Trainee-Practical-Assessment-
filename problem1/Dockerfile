# Wisecow Application Dockerfile
FROM debian:bookworm-slim

# Metadata
LABEL maintainer="uday1359"
LABEL description="Wisecow application with fortune and cowsay"

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PORT=4499

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    fortune-mod \
    cowsay \
    bash \
    socat \
    curl && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean
RUN apt-get update && apt-get reinstall -y \
    cowsay \
    fortune-mod \
    netcat-openbsd
# Create app directory
WORKDIR /app
COPY wisecow/wisecow.sh /usr/local/bin/wisecow.sh
RUN chmod +x /usr/local/bin/wisecow.sh
#Copy application script
COPY wisecow.sh /app/wisecow.sh

# Set permissions
RUN chmod +x /app/wisecow.sh
RUN sed -i 's/\r$//' /app/wisecow.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4499/ || exit 1

# Expose port
EXPOSE 4499

# Start application
CMD ["/bin/bash","/app/wisecow.sh"]

