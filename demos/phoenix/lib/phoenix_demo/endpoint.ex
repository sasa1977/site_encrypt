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
    SiteEncrypt.configure(
      client: :native,
      domains: ["mysite.com", "www.mysite.com"],
      emails: ["admin@email.address"],
      db_folder: System.get_env("SITE_ENCRYPT_DB", Path.join("tmp", "site_encrypt_db")),
      directory_url:
        case System.get_env("CERT_MODE", "local") do
          "local" -> {:internal, port: 4002}
          "staging" -> "https://acme-staging-v02.api.letsencrypt.org/directory"
          "production" -> "https://acme-v02.api.letsencrypt.org/directory"
        end
    )
  end
end
