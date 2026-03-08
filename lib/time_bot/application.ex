defmodule TimeBot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Запускаем Finch (HTTP клиент)
      {Finch, name: TimeBot.Finch},

      # Запускаем бота
      TimeBot.Bot
    ]

    opts = [strategy: :one_for_one, name: TimeBot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
