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
      {:parent, github: "sasa1977/parent"},
      {:plug, "~> 1.5", optional: true},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.8"},
      {:acme_ex, "~> 0.4"},
      {:dialyxir, "~> 0.5.0", runtime: false, only: [:dev, :test]}
    ]
  end
end
