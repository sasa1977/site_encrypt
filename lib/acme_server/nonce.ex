defmodule AcmeServer.Nonce do
  @spec new(AcmeServer.config()) :: integer()
  def new(config) do
    nonce = :erlang.unique_integer([:positive, :monotonic])
    AcmeServer.Db.store_new!(config, {:nonce, nonce}, nil)
    nonce
  end

  @spec verify!(AcmeServer.config(), integer()) :: :ok
  def verify!(config, nonce) do
    AcmeServer.Db.pop!(config, {:nonce, nonce})
    :ok
  end
end
