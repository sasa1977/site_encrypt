defmodule SiteEncrypt.Acme.Server.Plug do
  @behaviour Plug
  import Plug.Conn

  @impl Plug
  def init(config), do: config

  @impl Plug
  def call(conn, config) do
    case SiteEncrypt.Acme.Server.resource_path(config, conn.request_path) do
      {:ok, path} -> handle_request(conn, config, path) |> halt()
      :error -> conn
    end
  end

  defp handle_request(conn, config, path) do
    method = method(conn.method)
    {:ok, body, conn} = read_body(conn)
    acme_response = SiteEncrypt.Acme.Server.handle(config, method, path, body)
    send_response(conn, acme_response)
  end

  defp method("GET"), do: :get
  defp method("HEAD"), do: :head
  defp method("POST"), do: :post
  defp method("PUT"), do: :put
  defp method("DELETE"), do: :delete

  defp send_response(conn, acme_response) do
    conn
    |> merge_resp_headers(acme_response.headers)
    |> send_resp(acme_response.status, acme_response.body)
  end
end
