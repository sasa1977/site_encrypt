defmodule SiteEncrypt.Phoenix do
  use Supervisor

  def start_link({callback, opts}) do
    config = SiteEncrypt.normalized_config(callback, id: Keyword.get(opts, :endpoint, callback))
    Supervisor.start_link(__MODULE__, {config, opts})
  end

  def start_link(callback), do: start_link({callback, []})

  @impl Supervisor
  def init({config, opts}) do
    with :ok <- SiteEncrypt.Registry.register_main_site(config) do
      endpoint = Keyword.get(opts, :endpoint, config.callback)
      SiteEncrypt.initialize_certs(config)

      Supervisor.init(
        [
          acme_server_spec(config, endpoint),
          Supervisor.child_spec(endpoint, id: :endpoint),
          {SiteEncrypt.Certifier, config}
        ]
        |> Enum.reject(&is_nil/1),
        strategy: :rest_for_one
      )
    end
  end

  defp acme_server_spec(%{ca_url: url}, _endpoint) when is_binary(url), do: nil

  defp acme_server_spec(%{ca_url: {:local_acme_server, acme_server_config}} = config, endpoint) do
    port = Keyword.fetch!(acme_server_config, :port)
    SiteEncrypt.Logger.log(config.log_level, "Running local ACME server at port #{port}")

    AcmeServer.Standalone.child_spec(
      adapter: acme_server_adapter_spec(port),
      dns: dns(config, endpoint)
    )
  end

  defp acme_server_adapter_spec(port),
    do: {Plug.Cowboy, scheme: :http, options: [port: port, transport_options: [num_acceptors: 1]]}

  defp dns(config, endpoint) do
    [config.domain | config.extra_domains]
    |> Enum.map(&{&1, fn -> "localhost:#{endpoint.config(:http) |> Keyword.fetch!(:port)}" end})
    |> Enum.into(%{})
  end
end
