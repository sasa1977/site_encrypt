defmodule AcmeServer.Nonce do
  def new(config) do
    nonce = :erlang.unique_integer([:positive, :monotonic])
    AcmeServer.Db.store_new!(config, {:nonce, nonce}, nil)
    nonce
  end

  def verify!(config, nonce) do
    AcmeServer.Db.pop!(config, {:nonce, nonce})
    :ok
  end
end
