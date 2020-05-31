defmodule SiteEncrypt.Acme.Client.Http do
  @moduledoc false

  use Parent.GenServer
  alias SiteEncrypt.Acme.Client.Http.Connection

  @type opts :: [verify_server_cert: boolean]
  @type method :: :get | :head | :post | :put | :delete
  @type response :: %{status: Mint.Types.status(), headers: Mint.Types.headers(), body: binary}

  @spec start_link(opts) :: GenServer.on_start()
  def start_link(opts), do: Parent.GenServer.start_link(__MODULE__, opts)

  @spec request(pid, method, String.t(), Mint.Types.headers(), binary) ::
          {:ok, response} | {:error, Mint.Types.error()}
  def request(pool, method, url, headers, body) do
    uri = URI.parse(url)
    host = URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port})

    with {:ok, connection} <- GenServer.call(pool, {:connection, host}),
         method = method |> to_string() |> String.upcase(),
         path = URI.to_string(%URI{path: uri.path, query: uri.query}),
         req = {:request, method, path, headers, body},
         {:ok, response} <- GenServer.call(connection, req, :timer.minutes(1)) do
      headers = Enum.map(response.headers, fn {key, val} -> {String.downcase(key), val} end)
      {:ok, %{response | headers: headers}}
    end
  end

  @impl GenServer
  def init(opts), do: {:ok, opts}

  @impl GenServer
  def handle_call({:connection, host}, _client, opts),
    do: {:reply, connection_pid(host, opts), opts}

  @impl GenServer
  # happens if connection couldn't be established during conn init
  def handle_info({:EXIT, _pid, %Mint.TransportError{reason: :econnrefused}}, opts),
    do: {:noreply, opts}

  defp connection_pid(host, opts) do
    with :error <- Parent.GenServer.child_pid(host) do
      Parent.GenServer.start_child(%{id: host, start: {Connection, :start_link, [host, opts]}})
    end
  end

  defmodule Connection do
    @moduledoc false
    use GenServer

    def start_link(url, opts), do: GenServer.start_link(__MODULE__, {url, opts})

    def request(pid, method, path, headers, body),
      do: GenServer.call(pid, {:request, method, path, headers, body})

    @impl GenServer
    def init({url, opts}) do
      uri = URI.parse(url)
      {scheme, opts} = parse_scheme(uri.scheme, opts)

      case Mint.HTTP.connect(scheme, uri.host, uri.port, opts) do
        {:ok, conn} -> {:ok, %{conn: conn, requests: %{}}}
        {:error, reason} -> {:stop, reason}
      end
    end

    @impl GenServer
    def handle_call({:request, method, path, headers, body}, client, state) do
      case Mint.HTTP.request(state.conn, method, path, headers, body) do
        {:ok, conn, req} ->
          {:noreply, init_req(%{state | conn: conn}, req, client)}

        {:error, conn, reason} ->
          state = %{state | conn: conn}

          if Mint.HTTP.open?(state.conn),
            do: {:reply, {:error, reason}, state},
            else: {:stop, :normal, {:error, reason}, state}
      end
    end

    @impl GenServer
    def handle_info(message, state) do
      case Mint.HTTP.stream(state.conn, message) do
        {:ok, conn, responses} ->
          {:noreply, Enum.reduce(responses, %{state | conn: conn}, &process_response(&2, &1))}

        {:error, conn, _, _} ->
          {:stop, :normal, %{state | conn: conn}}
      end
    end

    defp parse_scheme("http", _opts), do: {:http, []}
    defp parse_scheme("https", opts), do: {:https, [transport_opts: [verify: verify(opts)]]}

    defp verify(opts),
      do: if(Keyword.get(opts, :verify_server_cert, true), do: :verify_peer, else: :verify_none)

    defp init_req(state, req, client) do
      update_in(
        state.requests,
        &Map.put(&1, req, %{headers: [], body: [], status: nil, client: client})
      )
    end

    defp process_response(state, {:status, req, status}),
      do: put_in(state.requests[req].status, status)

    defp process_response(state, {:headers, req, headers}),
      do: update_in(state.requests[req].headers, &(&1 ++ headers))

    defp process_response(state, {:data, req, data}),
      do: update_in(state.requests[req].body, &[&1, data])

    defp process_response(state, {:done, req}) do
      reply_to_client(state, req, fn req_data ->
        {:ok,
         %{
           status: req_data.status,
           headers: req_data.headers,
           body: IO.iodata_to_binary(req_data.body)
         }}
      end)
    end

    defp process_response(state, {:error, req, reason}),
      do: reply_to_client(state, req, fn _req_data -> {:error, reason} end)

    defp reply_to_client(state, req, fun) do
      {req_data, requests} = Map.pop!(state.requests, req)
      GenServer.reply(req_data.client, fun.(req_data))
      %{state | requests: requests}
    end
  end
end
