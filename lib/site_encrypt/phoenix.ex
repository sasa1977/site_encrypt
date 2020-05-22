defmodule SiteEncrypt.Phoenix do
  use Supervisor

  def start_link({callback, opts}) do
    endpoint = Keyword.get(opts, :endpoint, callback)

    config =
      update_in(
        SiteEncrypt.normalized_config(callback, id: endpoint).assigns,
        &Map.put(&1, :endpoint, endpoint)
      )

    Supervisor.start_link(
      [
        %{
          id: :site,
          type: :supervisor,
          start: {Supervisor, :start_link, [__MODULE__, config]}
        }
      ],
      strategy: :one_for_one,
      name: SiteEncrypt.Registry.name(config.id, :root)
    )
  end

  @doc false
  def start_link(callback), do: start_link({callback, []})

  @impl Supervisor
  def init(config) do
    :ok = SiteEncrypt.Registry.register_main_site(config)

    SiteEncrypt.initialize_certs(config)

    Supervisor.init(
      [
        acme_server_spec(config),
        Supervisor.child_spec(config.assigns.endpoint, id: :endpoint),
        {SiteEncrypt.Certifier, config}
      ]
      |> Enum.reject(&is_nil/1),
      strategy: :rest_for_one
    )
  end

  defp acme_server_spec(%{ca_url: url}) when is_binary(url), do: nil

  defp acme_server_spec(%{ca_url: {:local_acme_server, acme_server_config}} = config) do
    port = Keyword.fetch!(acme_server_config, :port)
    SiteEncrypt.Logger.log(config.log_level, "Running local ACME server at port #{port}")

    AcmeServer.Standalone.child_spec(
      adapter: acme_server_adapter_spec(port),
      dns: dns(config)
    )
  end

  defp acme_server_adapter_spec(port) do
    {
      Plug.Cowboy,
      options: [port: port]
    }
  end

  defp dns(config) do
    [config.domain | config.extra_domains]
    |> Enum.map(
      &{&1,
       fn -> "localhost:#{config.assigns.endpoint.config(:http) |> Keyword.fetch!(:port)}" end}
    )
    |> Enum.into(%{})
  end
end
