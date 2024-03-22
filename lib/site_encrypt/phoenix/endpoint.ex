defmodule SiteEncrypt.Phoenix.Endpoint do
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

  @doc false
  defmacro __using__(static_opts) do
    quote bind_quoted: [static_opts: static_opts] do
      {endpoint_opts, static_opts} = Keyword.split(static_opts, [:otp_app])
      use Phoenix.Endpoint, endpoint_opts

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
            unquote(static_opts)
            |> Config.Reader.merge(opts)
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
