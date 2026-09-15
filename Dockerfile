FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash \
        binutils \
        default-jre-headless \
        file \
        libreoffice-java-common \
        libreoffice-writer \
        pandoc \
        wamerican \
    && rm -rf /var/lib/apt/lists/*

COPY convert-docs.sh /usr/local/bin/convert-docs.sh
RUN chmod +x /usr/local/bin/convert-docs.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/convert-docs.sh"]
