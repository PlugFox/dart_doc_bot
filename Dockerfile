FROM ubuntu:lunar as build
USER root
WORKDIR /app

COPY . .

ENV FLUTTER_HOME="/opt/flutter"
ENV PATH="$PATH:$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin"

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    libssl-dev sqlite3 libsqlite3-dev git curl unzip \
    ca-certificates locales wget apt-transport-https gnupg \
    && apt-get purge --auto-remove -y gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt /app/.temp \
    && git clone -b master --depth 1 "https://github.com/flutter/flutter.git" "$FLUTTER_HOME" \
    && dart pub get \
    && dart run build_runner build --delete-conflicting-outputs \
    && dart run bin/generate.dart \
    && mv /app/.temp /app/db \
    && dart compile exe bin/server.dart -o bin/server


FROM ubuntu:lunar as producation
USER root
WORKDIR /app

COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /app/db /app/db

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends libssl-dev sqlite3 libsqlite3-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Start server.
EXPOSE 8080
CMD ["/app/bin/server"]