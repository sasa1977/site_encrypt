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
      {:parent, "~> 0.4"},
      {:plug_cowboy, "~> 2.1", optional: true},
      {:plug, "~> 1.7", optional: true},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.8"},
      {:x509, "~> 0.3"},
      {:stream_data, "~> 0.1", only: [:dev, :test]},

      {:dialyxir, "~> 1.0", runtime: false}
    ]
  end
end
