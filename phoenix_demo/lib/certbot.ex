defmodule PhoenixDemoWeb.Certbot do
  @behaviour SiteEncrypt

  def ssl_keys(), do: SiteEncrypt.Certbot.https_keys(config())

  def folder(), do: Application.app_dir(:phoenix_demo, "priv") |> Path.join("certbot")

  @impl SiteEncrypt
  def config() do
    %{
      run_client?: unquote(Mix.env() != :test),
      ca_url: local_acme_server(),
      domain: "foo.bar",
      extra_domains: ["www.foo.bar", "blog.foo.bar"],
      email: "admin@foo.bar",
      base_folder: folder(),
      renew_interval: :timer.hours(6),
      log_level: :info
    }
  end

  @impl SiteEncrypt
  def handle_new_cert(certbot_config) do
    # restarts the endpoint when the cert has been changed
    SiteEncrypt.Phoenix.restart_endpoint(certbot_config)

    # optionally backup the contents of the folder specified with folder/1
  end

  defp local_acme_server(), do: {:local_acme_server, %{adapter: Plug.Adapters.Cowboy, port: 4002}}
end
