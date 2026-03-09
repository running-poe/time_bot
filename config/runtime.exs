import Config

# Читаем токен из переменной окружения.
# Если переменная не задана, программа упадет с понятной ошибкой.
token = System.get_env("BOT_TOKEN") || raise("BOT_TOKEN environment variable is not set!")

# Передаем токен в настройки приложения
config :time_bot, bot_token: token

# Передаем токен в библиотеку Telegex
config :telegex, token: token
