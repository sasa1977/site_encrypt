defmodule SiteEncrypt.MixProject do
  use Mix.Project

  @version "0.3.0"

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
      {:castore, "~> 0.1"},
      {:dialyxir, "~> 1.0", runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.10"},
      {:mint, "~> 1.1"},
      {:nimble_options, "~> 0.2"},
      {:parent, "~> 0.9.0 or ~> 0.10.0"},
      {:phoenix, "~> 1.5", optional: true},
      {:plug_cowboy, "~> 2.2", optional: true},
      {:plug, "~> 1.7", optional: true},
      {:stream_data, "~> 0.1", only: [:dev, :test]},
      {:x509, "~> 0.3"}
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
          "https://github.com/sasa1977/site_encrypt/blob/#{@version}/CHANGELOG.md##{
            String.replace(@version, ".", "")
          }"
      }
    ]
  end
end
