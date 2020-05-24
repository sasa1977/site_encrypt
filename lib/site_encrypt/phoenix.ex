defmodule SiteEncrypt.Phoenix do
  use Supervisor

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
  def start_link(endpoint) do
    config = endpoint.certification()

    Supervisor.start_link(
      [
        %{
          id: :site,
          type: :supervisor,
          start: {Supervisor, :start_link, [__MODULE__, {config, endpoint}]}
        }
      ],
      strategy: :one_for_one,
      name: SiteEncrypt.Registry.name(config.id, :root)
    )
  end

  @doc false
  def restart_site(id, fun) do
    root_pid = SiteEncrypt.Registry.whereis(id, :root)
    Supervisor.terminate_child(root_pid, :site)
    fun.()
    Supervisor.restart_child(root_pid, :site)
    :ok
  end

  @impl Supervisor
  def init({config, endpoint}) do
    :ok = SiteEncrypt.Registry.register_main_site(config)

    SiteEncrypt.initialize_certs(config)

    Supervisor.init(
      [
        Supervisor.child_spec(endpoint, id: :endpoint),
        %{
          id: :certification,
          start: {__MODULE__, :start_certification, [config, endpoint]},
          type: :supervisor
        }
      ],
      strategy: :one_for_one
    )
  end

  @doc false
  def start_certification(config, endpoint) do
    server? =
      with nil <- endpoint.config(:server),
           do: Application.get_env(:phoenix, :serve_endpoints, false)

    if server? do
      Supervisor.start_link(
        [
          acme_server_spec(config, endpoint),
          {SiteEncrypt.Certifier, config}
        ]
        |> Enum.reject(&is_nil/1),
        strategy: :one_for_one
      )
    else
      :ignore
    end
  end

  defp acme_server_spec(%{directory_url: url}, _endpoint) when is_binary(url), do: nil

  defp acme_server_spec(%{directory_url: {:internal, acme_server_config}} = config, endpoint) do
    port = Keyword.fetch!(acme_server_config, :port)
    SiteEncrypt.Logger.log(config.log_level, "Running local ACME server at port #{port}")

    AcmeServer.Standalone.child_spec(
      adapter: acme_server_adapter_spec(port),
      dns: dns(config, endpoint)
    )
  end

  defp acme_server_adapter_spec(port), do: {Plug.Cowboy, options: [port: port]}

  defp dns(config, endpoint) do
    config.domains
    |> Enum.map(&{&1, fn -> "localhost:#{endpoint.config(:http) |> Keyword.fetch!(:port)}" end})
    |> Enum.into(%{})
  end
end
