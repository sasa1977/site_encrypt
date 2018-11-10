defmodule AcmeServer.Standalone do
  alias Plug.Adapters.{Cowboy, Cowboy2}

  def child_spec(opts) do
    {adapter, adapter_opts} = Keyword.fetch!(opts, :adapter)
    port = port(adapter, adapter_opts)
    config = AcmeServer.config(site: "http://localhost:#{port}", dns: Keyword.fetch!(opts, :dns))
    endpoint = adapter_spec(adapter, [{:plug, {AcmeServer.Plug, config}} | adapter_opts])
    AcmeServer.child_spec(config: config, endpoint: endpoint)
  end

  defp port(Cowboy, adapter_opts), do: cowboy_port(adapter_opts)
  defp port(Cowboy2, adapter_opts), do: cowboy_port(adapter_opts)
  defp port(Plug.Cowboy, adapter_opts), do: cowboy_port(adapter_opts)

  defp cowboy_port(adapter_opts),
    do: adapter_opts |> Keyword.fetch!(:options) |> Keyword.fetch!(:port)

  defp adapter_spec(Cowboy, adapter_opts), do: Cowboy.child_spec(adapter_opts)
  defp adapter_spec(Cowboy2, adapter_opts), do: Cowboy2.child_spec(adapter_opts)
  defp adapter_spec(Plug.Cowboy, adapter_opts), do: Plug.Cowboy.child_spec(adapter_opts)
end
