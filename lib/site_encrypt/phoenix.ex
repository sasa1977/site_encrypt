defmodule SiteEncrypt.Phoenix do
  @moduledoc """
  `SiteEncrypt` adapter for Phoenix endpoints.

  ## Usage

  1. Add `use SiteEncrypt.Phoenix` to your endpoint immediately after `use Phoenix.Endpoint`
  2. Configure https via `configure_https/2`.
  3. Add the implementation of `c:SiteEncrypt.certification/0` to the endpoint (the
    `@behaviour SiteEncrypt` is injected when this module is used).

  """

  use Parent.GenServer
  alias SiteEncrypt.{Acme, Registry}

  @doc """
  Merges paths to key and certificates to the `:https` configuration of the endpoint config.

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
      https_config =
        (Keyword.get(config, :https) || [])
        |> Config.Reader.merge(https_opts)
        |> Config.Reader.merge(SiteEncrypt.https_keys(__MODULE__))

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

  @doc false
  def start_link(endpoint), do: Parent.GenServer.start_link(__MODULE__, endpoint)

  @doc false
  def restart_site(id, fun) do
    GenServer.call(Registry.name(id, :root), :stop_site)
    fun.()
    GenServer.call(Registry.name(id, :root), :start_site)
    :ok
  end

  @impl GenServer
  def init(endpoint) do
    config = endpoint.certification()
    Registry.register(config.id, :root, config)
    start_site(config, endpoint)
    {:ok, %{config: config, endpoint: endpoint}}
  end

  @impl GenServer
  def handle_call(:stop_site, _from, state) do
    Parent.shutdown_all()
    {:reply, :ok, state}
  end

  def handle_call(:start_site, _from, state) do
    start_site(state.config, state.endpoint)
    {:reply, :ok, state}
  end

  @impl Parent.GenServer
  # Naive one-for-all with max_restarts of 0. If any of site services stop, we'll stop all remaining
  # siblings, effectively escalating restart to the parent supervisor.
  def handle_child_terminated(_id, _meta, _pid, _reason, state), do: {:stop, :shutdown, state}

  defp start_site(config, endpoint) do
    # Using parent as a supervisor, because we have a more dynamic startup flow.
    # We have to start the endpoint first, and then fetch its config to figure out if its serving
    # traffic. Based on that, and other options, we're determining whether additional processes,
    # such as local ACME server and certifier need to be started.
    #
    # Additionally, this approach allows a simple implementation of stop and restart site.

    SiteEncrypt.initialize_certs(config)

    start_child!(endpoint)

    if server?(endpoint) do
      with %{directory_url: {:internal, acme_server_config}} <- config do
        port = Keyword.fetch!(acme_server_config, :port)
        SiteEncrypt.log(config, "Running local ACME server at port #{port}")
        start_child!({Acme.Server, port: port, dns: dns(config, endpoint)})
      end

      start_child!({SiteEncrypt.Certification, config})
    end
  end

  defp start_child!(child_spec),
    do: {:ok, _} = Parent.start_child(Supervisor.child_spec(child_spec, []))

  defp server?(endpoint) do
    with nil <- endpoint.config(:server),
         do: Application.get_env(:phoenix, :serve_endpoints, false)
  end

  defp dns(config, endpoint) do
    Enum.into(
      config.domains,
      %{},
      &{&1, fn -> "localhost:#{endpoint.config(:http) |> Keyword.fetch!(:port)}" end}
    )
  end
end
