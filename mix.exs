defmodule TimeBot.MixProject do
  use Mix.Project

  def project do
  [
    app: :time_bot,
    version: "0.1.0",
    elixir: "~> 1.14",
    start_permanent: Mix.env() == :prod,
    deps: deps(),
    # Настройка релизов
    releases: [
      time_bot: [
        steps: [:assemble, &Burrito.wrap/1], # Включаем Burrito
        burrito: [
          targets: [
            # Цель для Raspberry Pi (32-bit или 64-bit)
            # Если ваша "Малина" 32-bit (стандартная): linux_arm
            # Если 64-bit: linux_arm64
            raspberry: [os: :linux, cpu: :arm]
          ]
        ]
      ]
    ]
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
      {:finch, "~> 0.16"},
      {:burrito, "~> 1.0"}
    ]
  end
end
