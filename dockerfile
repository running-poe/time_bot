# === ЭТАП 1: СБОРКА ===
# Используем официальный образ Elixir для сборки
FROM elixir:1.14-slim AS builder

# Устанавливаем git (нужен для некоторых зависимостей) и build-essential
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

# Собираем релиз (RELEASE)
ENV MIX_ENV=prod
RUN mix release

# === ЭТАП 2: ЗАПУСК (Финальный образ) ===
# Используем легкий образ Debian для запуска
FROM debian:bullseye-slim

# Устанавливаем библиотеки, необходимые для работы Erlang (SSL, курсоры, локали)
RUN apt-get update && apt-get install -y \
    openssl \
    libncurses6 \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Настраиваем локаль (чтобы нормально выводились даты и текст)
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

WORKDIR /app

# Копируем собранный релиз из первого этапа
COPY --from=builder /app/_build/prod/rel/time_bot ./

# Переменная окружения для работы с конфигом Elixir
ENV REPLACE_OS_VARS=true

# Команда запуска бота
CMD ["bin/time_bot", "start"]