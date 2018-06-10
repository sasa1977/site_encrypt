defmodule AcmeServer.Nonce do
  @type site :: String.t()
  @type dns :: %{String.t() => String.t()}
  @type config :: %{site: site, site_uri: URI.t(), dns: dns}

  @spec new(config) :: integer()
  def new(config) do
    nonce = :erlang.unique_integer([:positive, :monotonic])
    AcmeServer.Db.store_new!(config, {:nonce, nonce}, nil)
    nonce
  end

  @spec verify!(config, integer()) :: :ok
  def verify!(config, nonce) do
    AcmeServer.Db.pop!(config, {:nonce, nonce})
    :ok
  end
end
