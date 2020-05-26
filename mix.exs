defmodule SiteEncrypt.MixProject do
  use Mix.Project

  def project do
    [
      app: :site_encrypt,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_deps: :transitive, remove_defaults: [:unknown]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {SiteEncrypt.Application, []}
    ]
  end

  defp deps do
    [
      {:castore, "~> 0.1"},
      {:dialyxir, "~> 1.0", runtime: false},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.10"},
      {:mint, "~> 1.1"},
      {:parent, "~> 0.9"},
      {:phoenix, "~> 1.5", optional: true},
      {:plug_cowboy, "~> 2.2", optional: true},
      {:plug, "~> 1.7", optional: true},
      {:stream_data, "~> 0.1", only: [:dev, :test]},
      {:x509, "~> 0.3"}
    ]
  end
end
