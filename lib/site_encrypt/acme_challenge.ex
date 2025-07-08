defmodule SiteEncrypt.AcmeChallenge do
  @moduledoc false
  @behaviour Plug
  alias SiteEncrypt.Registry

  require Logger

  @impl Plug
  def init(id), do: id

  @impl Plug
  def call(%{request_path: "/.well-known/acme-challenge/" <> challenge} = conn, id) do
    case challenge_response(id, challenge) do
      {:ok, response} ->
        conn
        |> Plug.Conn.send_resp(200, response)
        |> Plug.Conn.halt()

      {:error, error} ->
        Logger.info(
          "An unknown challenge request (#{challenge}) was received from #{get_client_ip(conn)}, #{inspect(error)} "
        )

        conn
        |> Plug.Conn.send_resp(404, "Invalid or unknown challenge")
        |> Plug.Conn.halt()
    end
  end

  def call(conn, _endpoint), do: conn

  defp challenge_response(id, challenge) do
    case Registry.get_challenge(id, challenge) do
      nil ->
        config = Registry.config(id)
        SiteEncrypt.client(config).full_challenge(config, challenge)

      key_thumbprint ->
        {:ok, "#{challenge}.#{key_thumbprint}"}
    end
  end

  def get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> List.first() |> String.trim()

      [] ->
        # Try X-Real-IP header
        case Plug.Conn.get_req_header(conn, "x-real-ip") do
          [real_ip | _] ->
            String.trim(real_ip)

          [] ->
            # Fall back to direct connection IP
            case Plug.Conn.get_peer_data(conn) do
              %{address: address} -> :inet.ntoa(address) |> to_string()
              _ -> "unknown"
            end
        end
    end
  end
end
