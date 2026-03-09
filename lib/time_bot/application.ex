defmodule TimeBot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Finch,
        name: TimeBot.Finch,
        pools: %{
          default: [
            # Используем системные сертификаты Debian
            conn_opts: [transport_opts: [cacertfile: "/etc/ssl/certs/ca-certificates.crt"]]
          ]
        }
      },
      TimeBot.Bot
    ]

    opts = [strategy: :one_for_one, name: TimeBot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
