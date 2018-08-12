defmodule SiteEncrypt.MixProject do
  use Mix.Project

  def project do
    [
      app: :site_encrypt,
      version: "0.1.0",
      elixir: "~> 1.6",
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
      {:plug, "~> 1.5", optional: true},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.8"},
      {:x509, "~> 0.1"},
      {:stream_data, "~> 0.1", only: [:dev, :test]},
      {:dialyxir, "~> 0.5.0", runtime: false, only: [:dev, :test]}
    ]
  end
end
