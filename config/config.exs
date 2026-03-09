import Config

# Настройки вашего бота
config :time_bot,
  bot_token: "",
  timezone: "Europe/Moscow"

# Настройки библиотеки Telegex
config :telegex,
  token: "",
  adapter: {Telegex.Adapter.Finch, name: TimeBot.Finch}
