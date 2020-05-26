defmodule SiteEncrypt.Acme.Server.Nonce do
  @moduledoc false

  @spec new(SiteEncrypt.Acme.Server.config()) :: integer()
  def new(config) do
    nonce = :erlang.unique_integer([:positive, :monotonic])
    SiteEncrypt.Acme.Server.Db.store_new!(config, {:nonce, nonce}, nil)
    nonce
  end

  @spec verify!(SiteEncrypt.Acme.Server.config(), integer()) :: :ok
  def verify!(config, nonce) do
    SiteEncrypt.Acme.Server.Db.pop!(config, {:nonce, nonce})
    :ok
  end
end
