defmodule TimeBot.MixProject do
  use Mix.Project

  def project do
  [
    app: :time_bot,
    version: "0.1.0",
    elixir: "~> 1.14",
    start_permanent: Mix.env() == :prod,
    deps: deps()
  ]
end

  def application do
    [
      extra_applications: [:logger],
      mod: {TimeBot.Application, []}
    ]
  end

  defp deps do
    [
      {:telegex, "~> 1.7"},
      {:timex, "~> 3.7"},
      {:finch, "~> 0.16"}
    ]
  end
end
