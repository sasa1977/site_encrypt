defmodule SiteEncrypt.AcmeChallenge do
  @behaviour Plug

  @impl Plug
  def init(config_mod), do: config_mod

  @impl Plug
  def call(%{request_path: "/.well-known/acme-challenge/" <> challenge} = conn, config_mod) do
    conn
    |> Plug.Conn.send_file(
      200,
      SiteEncrypt.Certbot.challenge_file(config_mod.config().base_folder, challenge)
    )
    |> Plug.Conn.halt()
  end

  def call(conn, _endpoint), do: conn
end
