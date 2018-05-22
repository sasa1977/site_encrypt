defmodule SiteEncrypt.AcmeChallenge do
  @behaviour Plug

  @impl Plug
  def init(base_folder), do: base_folder

  @impl Plug
  def call(%{request_path: "/.well-known/acme-challenge/" <> challenge} = conn, base_folder) do
    conn
    |> Plug.Conn.send_file(
      200,
      SiteEncrypt.Certbot.challenge_file(base_folder, challenge)
    )
    |> Plug.Conn.halt()
  end

  def call(conn, _endpoint), do: conn
end
