defmodule PhoenixDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_demo,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixDemo.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.2"},
      {:site_encrypt, path: "../.."}
    ]
  end
end
