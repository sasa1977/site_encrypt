defmodule PhoenixDemoWeb.Certbot do
  @behaviour SiteEncrypt

  def https_keys(), do: SiteEncrypt.https_keys(config())

  @impl SiteEncrypt
  def config() do
    %{
      run_client?: unquote(Mix.env() != :test),
      ca_url: local_acme_server(),
      domain: "foo.bar",
      extra_domains: ["www.foo.bar", "blog.foo.bar"],
      email: "admin@foo.bar",
      base_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("certbot"),
      cert_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("cert"),
      renew_interval: :timer.hours(6),
      log_level: :info
    }
  end

  @impl SiteEncrypt
  def handle_new_cert() do
    # Optionally backup the folder configured via`:base_folder`.
    :ok
  end

  defp local_acme_server(), do: {:local_acme_server, %{adapter: Plug.Adapters.Cowboy, port: 4002}}
end
