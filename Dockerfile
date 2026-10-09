FROM eclipse-temurin:17-jre-jammy

ARG TIKA_VERSION=4.1.0
ARG TIKA_SHA512=c932f84c569fb02df4f72ab060d6f2cf77b6797417040202401bc256e18a8f6f0ebc25d12d6dce222cb9328abfcb388cfa6511d7382c765a45687240a8a4bd7e

ENV TIKA_HOME=/opt/tika

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        bash \
        binutils \
        ca-certificates \
        curl \
        tesseract-ocr \
        tesseract-ocr-eng \
        unzip \
        wamerican \
    && curl --fail --location --show-error \
        "https://downloads.apache.org/tika/${TIKA_VERSION}/tika-server-standard-${TIKA_VERSION}.zip" \
        --output /tmp/tika-server.zip \
    && echo "${TIKA_SHA512}  /tmp/tika-server.zip" | sha512sum --check --strict \
    && mkdir --parents "${TIKA_HOME}" \
    && unzip -q /tmp/tika-server.zip -d "${TIKA_HOME}" \
    && ln -s "${TIKA_HOME}/tika-server-standard-${TIKA_VERSION}.jar" "${TIKA_HOME}/tika-server.jar" \
    && rm -f /tmp/tika-server.zip \
    && rm -rf /var/lib/apt/lists/*

COPY convert-docs.sh /usr/local/bin/convert-docs.sh
COPY tika-config.json /opt/tika/tika-config.json
RUN chmod +x /usr/local/bin/convert-docs.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/convert-docs.sh"]
