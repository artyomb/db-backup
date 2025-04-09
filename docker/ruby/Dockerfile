FROM ruby:3.3.1-slim-bookworm AS base

RUN apt update && apt install -y curl gnupg2 lsb-release \
 && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
 && apt update \
 && apt install -y postgresql-client \
    build-essential pkg-config bash libpq-dev openssh-client \
    libsqlite3-dev libssl-dev libgeos-dev jq \
 && rm -rf /var/lib/apt/lists/*

RUN echo 'gem: --no-document' >> ~/.gemrc

WORKDIR /app

COPY Gemfile* /app/

RUN bundle install --jobs $(nproc) --retry=3 && \
    bundle clean --force && rm -rf /usr/local/bundle/cache/*

FROM ruby:3.3.1-slim-bookworm AS deploy
RUN apt update && apt install -y curl gnupg2 lsb-release \
 && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
 && apt update \
 && apt install -y postgresql-client \
    build-essential pkg-config bash libpq-dev openssh-client \
    libsqlite3-dev libssl-dev libgeos-dev jq \
 && rm -rf /var/lib/apt/lists/*

COPY --from=base /usr/local/bundle /usr/local/bundle
COPY . /app

ENV SERVER_ENV=production \
    RACK_ENV=production \
    PORT=7000

WORKDIR /app

# --start_period=5s (Unknown flag: start_period)
# HEALTHCHECK --interval=15s --timeout=2s --retries=3 CMD curl --fail http://127.0.0.1:$PORT/healthcheck || exit 1
RUN mkdir -p /backups
RUN chmod +x /app/backup.sh

CMD ls && bundle exec rackup -o 0.0.0.0 -p $PORT -s falcon