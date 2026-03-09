# === ЭТАП 1: СБОРКА ===
# Используем актуальную версию Elixir 1.17
FROM elixir:1.17-slim AS builder

# Устанавливаем git и build-essential
RUN apt-get update && apt-get install -y git build-essential

WORKDIR /app

# Устанавливаем Hex и Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Копируем файлы зависимостей
COPY mix.exs mix.lock ./

# Скачиваем зависимости только для продакшена
RUN mix deps.get --only prod

# Копируем исходный код
COPY config config
COPY lib lib

# Собираем релиз
ENV MIX_ENV=prod
RUN mix release

# === ЭТАП 2: ЗАПУСК (Финальный образ) ===
# Используем Debian 12 (Bookworm) для совместимости с Elixir 1.17
FROM debian:bookworm-slim

# Устанавливаем библиотеки для работы Erlang и локали
RUN apt-get update && apt-get install -y \
    openssl \
    libncurses6 \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Настраиваем локаль
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

WORKDIR /app

# Копируем собранный релиз
COPY --from=builder /app/_build/prod/rel/time_bot ./

ENV REPLACE_OS_VARS=true

# Команда запуска
CMD ["bin/time_bot", "start"]