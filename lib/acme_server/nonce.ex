defmodule AcmeServer.Nonce do
  def new() do
    nonce = :erlang.unique_integer([:positive, :monotonic])
    AcmeServer.Db.store_new!({:nonce, nonce}, nil)
    nonce
  end

  def verify!(nonce) do
    AcmeServer.Db.pop!({:nonce, nonce})
    :ok
  end
end
