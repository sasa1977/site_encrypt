defmodule SiteEncrypt.MixProject do
  use Mix.Project

  @version "0.5.0"

  def project do
    [
      app: :site_encrypt,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_deps: :transitive, remove_defaults: [:unknown]],
      docs: docs(),
      package: package()
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
      {:bandit, "~> 0.7 or ~> 1.0", optional: true},
      {:castore, "~> 0.1 or ~> 1.0"},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.10"},
      {:mint, "~> 1.4"},
      {:nimble_options, "~> 0.3 or ~> 1.0"},
      {:parent, "~> 0.11"},
      {:phoenix, "~> 1.5", optional: true},
      {:plug_cowboy, "~> 2.5", optional: true},
      {:plug, "~> 1.7", optional: true},
      {:stream_data, "~> 0.1", only: [:dev, :test]},
      {:x509, "~> 0.8.8"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: "https://github.com/sasa1977/site_encrypt/",
      source_ref: @version
    ]
  end

  defp package() do
    [
      description: "Integrated certification via Let's encrypt for Elixir-powered sites",
      maintainers: ["Saša Jurić"],
      licenses: ["MIT"],
      links: %{
        "Github" => "https://github.com/sasa1977/site_encrypt",
        "Changelog" =>
          "https://github.com/sasa1977/site_encrypt/blob/#{@version}/CHANGELOG.md##{String.replace(@version, ".", "")}"
      }
    ]
  end
end
