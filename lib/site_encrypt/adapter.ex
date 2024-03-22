defmodule SiteEncrypt.Adapter do
  alias SiteEncrypt.{Acme, Registry}

  use Parent.GenServer

  @callback config(SiteEncrypt.id(), Keyword.t()) :: %{
              certification: SiteEncrypt.certification(),
              site_spec: Parent.child_spec()
            }

  @callback http_port(SiteEncrypt.id(), arg :: any) :: {:ok, pos_integer} | :error

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour SiteEncrypt.Adapter

      @doc """
      Returns a specification to start this module under a supervisor.

      See `Supervisor`.
      """
      def child_spec(start_opts) do
        Supervisor.child_spec(
          %{
            id: __MODULE__,
            type: :supervisor,
            start: {__MODULE__, :start_link, [start_opts]}
          },
          unquote(opts)
        )
      end
    end
  end

  def start_link(callback, id, opts),
    do: Parent.GenServer.start_link(__MODULE__, {callback, id, opts}, name: Registry.root(id))

  @doc false
  # used only in tests
  def restart_site(id, fun) do
    Parent.Client.shutdown_all(Registry.root(id))
    fun.()
    GenServer.call(Registry.root(id), :start_all_children)
  end

  @doc """
  Refresh the configuration for a given endpoint
  """
  def refresh_config(id) do
    GenServer.call(Registry.root(id), :refresh_config)
  end

  @impl GenServer
  def init({callback, id, opts}) do
    state = %{callback: callback, id: id, opts: opts}
    start_all_children!(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:start_all_children, _from, state) do
    start_all_children!(state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:refresh_config, _from, state) do
    adapter_config = state.callback.config(state.id, state.opts)
    Registry.store_config(state.id, adapter_config.certification)
    {:reply, :ok, state}
  end

  defp start_all_children!(state) do
    adapter_config = state.callback.config(state.id, state.opts)
    Registry.store_config(state.id, adapter_config.certification)

    SiteEncrypt.initialize_certs(adapter_config.certification)

    Parent.start_all_children!([
      Parent.child_spec(adapter_config.site_spec, id: :site),
      Parent.child_spec(Acme.Server,
        start: fn -> start_acme_server(state, adapter_config) end,
        binds_to: [:site]
      )
      | SiteEncrypt.Certification.child_specs(state.id)
    ])
  end

  defp start_acme_server(state, adapter_config) do
    config = adapter_config.certification

    with {:ok, site_port} <- state.callback.http_port(state.id, state.opts),
         %{directory_url: {:internal, acme_server_opts}} <- config do
      {acme_server_port, acme_server_opts} = Keyword.pop!(acme_server_opts, :port)
      dns = dns(config.id, site_port)
      acme_server_opts = [log_level: config.log_level] ++ acme_server_opts
      Acme.Server.start_link(config.id, acme_server_port, dns, acme_server_opts)
    else
      _ -> :ignore
    end
  end

  defp dns(id, endpoint_port) do
    fn ->
      # refetching the new config before resolving domain names allows us to correctly handle
      # config changes made after the endpoint has been started
      Enum.into(Registry.config(id).domains, %{}, &{&1, "localhost:#{endpoint_port}"})
    end
  end
end
