defmodule SiteEncrypt.AcmeChallenge do
  @behaviour Plug
  alias SiteEncrypt.Registry

  @impl Plug
  def init(id), do: id

  @impl Plug
  def call(%{request_path: "/.well-known/acme-challenge/" <> challenge} = conn, id) do
    conn
    |> Plug.Conn.send_resp(200, challenge_response(id, challenge))
    |> Plug.Conn.halt()
  end

  def call(conn, _endpoint), do: conn

  defp challenge_response(id, challenge) do
    case Registry.get_challenge(id, challenge) do
      {pid, key_thumbprint} ->
        send(pid, :got_challenge)
        "#{challenge}.#{key_thumbprint}"

      nil ->
        config = Registry.config(id)
        config.certifier.full_challenge(config, challenge)
    end
  end
end
