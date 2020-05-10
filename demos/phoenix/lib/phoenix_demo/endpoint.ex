defmodule PhoenixDemo.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_demo
  @behaviour SiteEncrypt

  plug SiteEncrypt.AcmeChallenge, __MODULE__
  plug Plug.SSL, exclude: []
  plug :hello

  defp hello(conn, _opts),
    do: Plug.Conn.send_resp(conn, :ok, "This site has been encrypted by site_encrypt.")

  @impl Phoenix.Endpoint
  def init(_key, config) do
    {:ok,
     Keyword.merge(config,
       url: [scheme: "https", host: "localhost", port: 4001],
       http: [port: 4000],
       https: [port: 4001] ++ SiteEncrypt.https_keys(__MODULE__),
       server: true,
       mode: unquote(if Mix.env() == :test, do: :manual, else: :auto)
     )}
  end

  @impl SiteEncrypt
  def certification do
    common_settings = [
      base_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("certbot"),
      cert_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("cert")
    ]

    target_machine_settings =
      case System.get_env("MODE", "local") do
        "local" ->
          [
            ca_url: {:local_acme_server, port: 4002},
            domain: "localhost",
            email: "admin@foo.bar"
          ]

        "staging" ->
          [
            ca_url: "https://acme-staging-v02.api.letsencrypt.org/directory",
            domain: "staging.host.name",
            email: "admin@email.address"
          ]

        "production" ->
          [
            ca_url: "https://acme-v02.api.letsencrypt.org/directory",
            domain: "production.host.name",
            email: "admin@email.address"
          ]
      end

    common_settings ++ target_machine_settings
  end

  @impl SiteEncrypt
  def handle_new_cert do
    # backup `base_folder` content
    :ok
  end
end
