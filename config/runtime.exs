import Config

token = System.get_env("TIME_BOT_TOKEN") || raise("TIME_BOT_TOKEN not set!")
supabase_url = System.get_env("SUPABASE_URL") || raise("SUPABASE_URL not set!")
supabase_key = System.get_env("SUPABASE_KEY") || raise("SUPABASE_KEY not set!")

config :time_bot,
  bot_token: token,
  supabase_url: supabase_url,
  supabase_key: supabase_key

config :telegex, token: token
