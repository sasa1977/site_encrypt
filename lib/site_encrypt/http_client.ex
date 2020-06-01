defmodule SiteEncrypt.HttpClient do
  @moduledoc false

  # This is a very naive Mint-based HTTP client which does no connection reusing/pooling, i.e.
  # every request is done on a separate connection. This approach has been chosen for simplicity.
  #
  # As an alternative, Finch was also considered, but at the time of writing this it didn't seem
  # suitable for a couple of reasons:
  #
  #   1. We have to explicitly choose http1 vs http2, which we can't do because we don't know
  #      the CA servers upfront.
  #   2. Finch seems to always keep the connection open. Since we interact with CA very
  #      infrequently, and in short burtsts, this is not what we want.
  #
  # A previous version of the client implemented a manual naive pool on top of Mint, but I wasn't
  # able to convince myself that it's reliable enough, and I didn't want to invest extra effort
  # in dealing with errors, reconnects, timeouts, and other pooling-related problems.
  #
  # While this approach is not super fast, it should be sufficient for the typical scenarios (a
  # couple of requests issued every few months).

  @type method :: :get | :head | :post | :put | :delete

  @type opts :: [
          verify_server_cert: boolean,
          headers: Mint.Types.headers(),
          body: binary
        ]

  @type response :: %{status: Mint.Types.status(), headers: Mint.Types.headers(), body: binary}

  @spec request(method, String.t(), opts) :: response
  def request(method, url, opts \\ []) do
    uri = URI.parse(url)
    {scheme, http_opts} = parse_scheme(uri.scheme, opts)
    http_opts = Keyword.put(http_opts, :mode, :passive)

    {:ok, conn} = Mint.HTTP.connect(scheme, uri.host, uri.port, http_opts)

    try do
      method = String.upcase(to_string(method))
      path = URI.to_string(%URI{path: uri.path, query: uri.query})
      headers = Keyword.get(opts, :headers, [])
      body = Keyword.get(opts, :body)
      {:ok, conn, req} = Mint.HTTP.request(conn, method, path, headers, body)
      {response, conn} = get_response(conn, req)
      Mint.HTTP.close(conn)
      response
    after
      Mint.HTTP.close(conn)
    end
  end

  defp parse_scheme("http", _opts), do: {:http, []}
  defp parse_scheme("https", opts), do: {:https, [transport_opts: [verify: verify(opts)]]}

  defp verify(opts),
    do: if(Keyword.get(opts, :verify_server_cert, true), do: :verify_peer, else: :verify_none)

  defp get_response(conn, req, response \\ %{status: nil, headers: [], body: ""}) do
    {:ok, conn, responses} = Mint.HTTP.recv(conn, 0, :timer.minutes(1))
    merge_responses(conn, req, response, responses)
  end

  defp merge_responses(conn, req, response, []), do: get_response(conn, req, response)

  defp merge_responses(conn, req, response, [{:status, req, status} | responses]),
    do: merge_responses(conn, req, Map.put(response, :status, status), responses)

  defp merge_responses(conn, req, response, [{:headers, req, headers} | responses]) do
    headers = Enum.map(headers, fn {key, val} -> {String.downcase(key), val} end)
    merge_responses(conn, req, Map.update!(response, :headers, &[&1, headers]), responses)
  end

  defp merge_responses(conn, req, response, [{:data, req, data} | responses]),
    do: merge_responses(conn, req, Map.update!(response, :body, &[&1, data]), responses)

  defp merge_responses(conn, req, response, [{:done, req}]) do
    {response
     |> Map.update!(:headers, &List.flatten/1)
     |> Map.update!(:body, &IO.iodata_to_binary/1), conn}
  end

  # defp get_response(conn, req) do
  #   Stream.unfold(
  #     conn,
  #     fn conn ->
  #       {:ok, conn, responses} = Mint.HTTP.recv(conn, 0, :timer.minutes(1))
  #       {responses, conn}
  #     end
  #   )
  #   |> Stream.flat_map(& &1)
  #   |> Enum.reduce_while(
  #     %{status: nil, headers: [], body: ""},
  #     fn
  #       {:status, ^req, status}, response ->
  #         {:cont, Map.put(response, :status, status)}

  #       {:headers, ^req, headers}, response ->
  #         headers = Enum.map(headers, fn {key, val} -> {String.downcase(key), val} end)
  #         {:cont, Map.update!(response, :headers, &[&1, headers])}

  #       {:data, ^req, data}, response ->
  #         {:cont, Map.update!(response, :body, &[&1, data])}

  #       {:done, ^req}, response ->
  #         {:halt,
  #          response
  #          |> Map.update!(:headers, &List.flatten/1)
  #          |> Map.update!(:body, &IO.iodata_to_binary/1)}
  #     end
  #   )
  # end
end
