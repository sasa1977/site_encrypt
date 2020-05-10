defmodule SiteEncrypt.AcmeChallenge do
  @behaviour Plug

  @impl Plug
  def init(config_mod), do: config_mod

  @impl Plug
  def call(%{request_path: "/.well-known/acme-challenge/" <> challenge} = conn, config_mod) do
    conn
    |> Plug.Conn.send_file(200, challenge_file(config_mod, challenge))
    |> Plug.Conn.halt()
  end

  def call(conn, _endpoint), do: conn

  defp challenge_file(config_mod, challenge) do
    SiteEncrypt.Certbot.challenge_file(
      SiteEncrypt.Registry.config(config_mod).base_folder,
      challenge
    )
  end
end
