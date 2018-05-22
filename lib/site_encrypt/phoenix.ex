defmodule SiteEncrypt.Phoenix do
  def child_spec(opts) do
    %{id: __MODULE__, type: :supervisor, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link({callback, endpoint}) do
    config = callback.config()

    Supervisor.start_link(
      [
        acme_spec(config, endpoint),
        Supervisor.child_spec(endpoint, id: :endpoint),
        {SiteEncrypt.Certifier, callback}
      ]
      |> Enum.reject(&is_nil/1),
      name: name(config),
      strategy: :rest_for_one
    )
  end

  def restart_endpoint(config) do
    Supervisor.terminate_child(name(config), :endpoint)
    Supervisor.restart_child(name(config), :endpoint)
  end

  defp name(config), do: SiteEncrypt.Registry.via_tuple({__MODULE__, config.domain})

  defp acme_spec(%{ca_url: url}, _endpoint) when is_binary(url), do: nil

  defp acme_spec(%{ca_url: {:local_acme_server, acme_server_config}} = config, endpoint) do
    %{port: port, adapter: adapter} = acme_server_config
    SiteEncrypt.Logger.log(config.log_level, "Running local ACME server at port #{port}")

    AcmeServer.Standalone.child_spec(
      adapter: acme_server_adapter_spec(adapter, port),
      dns: dns(config, endpoint)
    )
  end

  defp acme_server_adapter_spec(Plug.Adapters.Cowboy, port),
    do: {Plug.Adapters.Cowboy, scheme: :http, options: [port: port, acceptors: 1]}

  defp dns(config, endpoint) do
    [config.domain | config.extra_domains]
    |> Enum.map(&{&1, fn -> "localhost:#{endpoint.config(:http) |> Keyword.fetch!(:port)}" end})
    |> Enum.into(%{})
  end
end
