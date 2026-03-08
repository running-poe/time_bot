import Config

# Настройки вашего бота
config :time_bot,
  bot_token: "8409471854:AAGhK3UE65tnBTZIWguPS2_4fBI1Yed4VM8",
  timezone: "Europe/Moscow"

# Настройки библиотеки Telegex
config :telegex,
  token: "8409471854:AAGhK3UE65tnBTZIWguPS2_4fBI1Yed4VM8",
  adapter: {Telegex.Adapter.Finch, name: TimeBot.Finch}
