defmodule PhoenixDemo.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_demo
  use SiteEncrypt.Phoenix

  plug SiteEncrypt.AcmeChallenge, __MODULE__
  plug Plug.SSL, exclude: [], host: "localhost:4001"
  plug :hello

  defp hello(conn, _opts),
    do: Plug.Conn.send_resp(conn, :ok, "This site has been encrypted by site_encrypt.")

  @impl Phoenix.Endpoint
  def init(_key, config) do
    {:ok,
     config
     |> SiteEncrypt.Phoenix.configure_https(port: 4001)
     |> Keyword.merge(
       url: [scheme: "https", host: "localhost", port: 4001],
       http: [port: 4000]
     )}
  end

  @impl SiteEncrypt
  def certification do
    common_settings = [
      db_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("db"),
      certifier: SiteEncrypt.Native
    ]

    target_machine_settings =
      case System.get_env("MODE", "local") do
        "local" ->
          [
            ca_url: {:local_acme_server, port: 4002},
            domains: ["localhost"],
            emails: ["admin@foo.bar"]
          ]

        "staging" ->
          [
            ca_url: "https://acme-staging-v02.api.letsencrypt.org/directory",
            domains: ["staging.host", "www.staging.host"],
            emails: ["admin@email.address"]
          ]

        "production" ->
          [
            ca_url: "https://acme-v02.api.letsencrypt.org/directory",
            domains: ["production.host", "www.production.host"],
            emails: ["admin@email.address"]
          ]
      end

    SiteEncrypt.configure(common_settings ++ target_machine_settings)
  end
end
