import Config

# Общие настройки (без токена)
config :time_bot,
  timezone: "Europe/Moscow"

# Настройки HTTP клиента Finch
config :telegex,
  adapter: {Telegex.Adapter.Finch, name: TimeBot.Finch}
