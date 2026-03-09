FROM elixir:1.17-slim AS builder

RUN apt-get update && apt-get install -y git build-essential

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
COPY lib lib

ENV MIX_ENV=prod
RUN mix release

# === ЭТАП 2: ЗАПУСК ===
FROM debian:bookworm-slim

# Явно устанавливаем ca-certificates и обновляем хранилище
RUN apt-get update && apt-get install -y \
    openssl \
    ca-certificates \
    libncurses6 \
    locales \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/time_bot ./

ENV REPLACE_OS_VARS=true

CMD ["bin/time_bot", "start"]