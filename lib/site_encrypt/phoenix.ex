defmodule SiteEncrypt.Phoenix do
  @moduledoc """
  `SiteEncrypt` adapter for Phoenix endpoints.

  ## Usage

  1. Add `use SiteEncrypt.Phoenix` to your endpoint immediately after `use Phoenix.Endpoint`
  2. Configure https via `configure_https/2`.
  3. Add the implementation of `c:SiteEncrypt.certification/0` to the endpoint (the
    `@behaviour SiteEncrypt` is injected when this module is used).
  4. Start the endpoint by providing `{SiteEncrypt.Phoenix, endpoint: PhoenixDemo.Endpoint}` as a supervisor child.
  """

  use SiteEncrypt.Adapter
  alias SiteEncrypt.Adapter

  @type start_opts :: [endpoint: module, endpoint_opts: Keyword.t()]

  @spec child_spec(start_opts) :: Supervisor.child_spec()

  @doc "Starts the endpoint managed by `SiteEncrypt`."
  @spec start_link(start_opts) :: Supervisor.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :endpoint)
    Adapter.start_link(__MODULE__, id, opts)
  end

  @doc """
  Merges paths to key and certificates to the `:https` configuration of the endpoint config for Cowboy.

  Invoke this macro from `c:Phoenix.Endpoint.init/2` to complete the https configuration:

      defmodule MyEndpoint do
        # ...

        @impl Phoenix.Endpoint
        def init(_key, config) do
          # this will merge key, cert, and chain into `:https` configuration from config.exs
          {:ok, SiteEncrypt.Phoenix.configure_https(config)}

          # to completely configure https from `init/2`, invoke:
          #   SiteEncrypt.Phoenix.configure_https(config, port: 4001, ...)
        end

        # ...
      end

  The `options` are any valid adapter HTTPS options. For many great tips on configuring HTTPS for
  production refer to the [Plug HTTPS guide](https://hexdocs.pm/plug/https.html#content).
  """
  defmacro configure_https(config, https_opts \\ []) do
    quote bind_quoted: [config: config, https_opts: https_opts] do
      # Default to cowboy
      adapter = Keyword.get(config, :adapter, Phoenix.Endpoint.Cowboy2Adapter)

      https_config =
        case adapter do
          Phoenix.Endpoint.Cowboy2Adapter ->
            (Keyword.get(config, :https) || [])
            |> Config.Reader.merge(https_opts)
            |> Config.Reader.merge(SiteEncrypt.https_keys(__MODULE__))

          Bandit.PhoenixAdapter ->
            (Keyword.get(config, :https) || [])
            |> Config.Reader.merge(https_opts)
            |> Config.Reader.merge(
              thousand_island_options: [transport_options: SiteEncrypt.https_keys(__MODULE__)]
            )
        end

      Keyword.put(config, :https, https_config)
    end
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      unless Enum.member?(@behaviour, Phoenix.Endpoint),
        do: raise("SiteEncrypt.Phoenix must be used after Phoenix.Endpoint")

      @behaviour SiteEncrypt
      require SiteEncrypt
      require SiteEncrypt.Phoenix

      plug SiteEncrypt.AcmeChallenge, __MODULE__

      @impl SiteEncrypt
      def handle_new_cert, do: :ok

      defoverridable handle_new_cert: 0
    end
  end

  @impl Adapter
  def config(_id, opts) do
    endpoint = Keyword.fetch!(opts, :endpoint)
    endpoint_opts = Keyword.get(opts, :endpoint_opts, [])

    %{
      certification: endpoint.certification(),
      site_spec: {endpoint, endpoint_opts}
    }
  end

  @impl Adapter
  def http_port(_id, opts) do
    endpoint = Keyword.fetch!(opts, :endpoint)

    if server?(endpoint) do
      http_config = endpoint.config(:http)

      with true <- Keyword.keyword?(http_config),
           port when is_integer(port) <- Keyword.get(http_config, :port) do
        {:ok, port}
      else
        _ ->
          raise_http_required(http_config)
      end
    else
      :error
    end
  end

  defp raise_http_required(http_config) do
    raise "Unable to retrieve HTTP port from the HTTP configuration. SiteEncrypt relies on the Lets Encrypt " <>
            "HTTP-01 challenge type which requires an HTTP version of the endpoint to be running and " <>
            "the configuration received did not include an http port.\n" <>
            "Received: #{inspect(http_config)}"
  end

  defp server?(endpoint) do
    endpoint.config(:server) ||
      Application.get_env(:phoenix, :serve_endpoints, false)
  end
end
