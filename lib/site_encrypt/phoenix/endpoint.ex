defmodule SiteEncrypt.Phoenix.Endpoint do
  @moduledoc """
  `SiteEncrypt` adapter for Phoenix endpoints.

  ## Usage

  1. Replace `use Phoenix.Endpoint` with `use SiteEncrypt.Phoenix.Endpoint`
  2. Add the implementation of `c:SiteEncrypt.certification/0` to the endpoint (the
    `@behaviour SiteEncrypt` is injected when this module is used).

  See `__using__/1` for details.
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
  Turns the module into a Phoenix Endpoint certified by site_encrypt.

  This macro will add `use Phoenix.Endpoint` and `@behaviour SiteEncrypt` to the caller module.
  It will also provide the default implementation of `c:SiteEncrypt.handle_new_cert/0`.

  The macro accepts the following options:

    - `:otp_app` - Same as with `Phoenix.Endpoint`, specifies the otp_app running the endpoint. Any
      app env endpoint options must be placed under that app.
    - `:endpoint_opts` - Endpoint options which are deep merged on top of options defined in app
      config.

  The macro generates the `child_spec/1` function, so you can list your endpoint module as a
  supervisor child. In addition, you can pass additional endpoint options with `{MyEndpoint, opts}`,
  where `opts` is standard
  [Phoenix endpoint configuration](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#module-endpoint-configuration).

  The final endpoint config is assembled in the following order:

  1. Options provided in config.exs and runtime.exs (via `config :my_app, MyEndpoint, [...]`)
  2. Options provided via `use SiteEncrypt.Phoenix.Endpoint, endpoint_opts: [...]`
  3. Options provided via `{MyEndpoint, opts}`.

  ## Overriding child_spec

  To provide config at runtime and embed it inside the endpoint module, you can override the
  `child_spec/1` function:

      defmodule MyEndpoint do
        use SiteEncrypt.Phoenix.Endpoint, otp_app: :my_app

        defoverridable child_spec: 1

        def child_spec(_arg) do
          # invoked at runtime, before the endpoint is first started

          # builds endpoint config at runtime
          endpoint_config = [
            http: [...],
            https: [...],
            ...
          ]

          # Invokes the base implementation with the built config. This will be merged on top of
          # options provided via `use SiteEncrypt.Phoenix.Endpoint` and app config.
          super(endpoint_config)
        end

        ...
      end
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      {phoenix_using_opts, using_opts} = Keyword.split(opts, [:otp_app])
      use Phoenix.Endpoint, phoenix_using_opts

      @behaviour SiteEncrypt
      require SiteEncrypt

      plug SiteEncrypt.AcmeChallenge, __MODULE__

      @impl SiteEncrypt
      def handle_new_cert, do: :ok

      defoverridable handle_new_cert: 0

      @doc false
      def app_env_config, do: Application.get_env(@otp_app, __MODULE__, [])

      defoverridable child_spec: 1

      def child_spec(opts) do
        Supervisor.child_spec(
          {
            SiteEncrypt.Phoenix.Endpoint,
            unquote(using_opts)
            |> Config.Reader.merge(endpoint_opts: opts)
            |> Keyword.put(:endpoint, __MODULE__)
          },
          []
        )
      end
    end
  end

  @impl Adapter
  def config(id, opts) do
    endpoint = Keyword.fetch!(opts, :endpoint)
    endpoint_opts = Keyword.get(opts, :endpoint_opts, [])

    %{
      certification: endpoint.certification(),
      site_spec: %{
        id: id,
        start: {__MODULE__, :start_endpoint, [id, endpoint, endpoint_opts]},
        type: :supervisor
      }
    }
  end

  @doc false
  def start_endpoint(id, endpoint, endpoint_opts) do
    adapter =
      Keyword.get_lazy(
        # 1. Try to get adapter from opts passed to start_link
        endpoint_opts,
        :adapter,
        fn ->
          Keyword.get(
            # 2. Try to get adapter from app env
            endpoint.app_env_config(),
            :adapter,
            # 3. If adapter is not provided, default to cowboy
            Phoenix.Endpoint.Cowboy2Adapter
          )
        end
      )

    endpoint_opts =
      case adapter do
        Phoenix.Endpoint.Cowboy2Adapter ->
          Config.Reader.merge(endpoint_opts, https: SiteEncrypt.https_keys(id))

        Bandit.PhoenixAdapter ->
          Config.Reader.merge(endpoint_opts,
            https: [thousand_island_options: [transport_options: SiteEncrypt.https_keys(id)]]
          )
      end

    endpoint.start_link(endpoint_opts)
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
