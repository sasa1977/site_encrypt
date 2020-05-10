defmodule AcmeServer.Standalone do
  def child_spec(opts) do
    {_adapter, adapter_opts} = Keyword.fetch!(opts, :adapter)
    port = port(adapter_opts)
    config = AcmeServer.config(site: "http://localhost:#{port}", dns: Keyword.fetch!(opts, :dns))
    endpoint = adapter_spec([{:plug, {AcmeServer.Plug, config}} | adapter_opts])
    AcmeServer.child_spec(config: config, endpoint: endpoint)
  end

  defp port(adapter_opts),
    do: adapter_opts |> Keyword.fetch!(:options) |> Keyword.fetch!(:port)

  defp adapter_spec(adapter_opts), do: Plug.Cowboy.child_spec(adapter_opts)
end
