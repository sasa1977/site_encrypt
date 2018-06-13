defmodule AcmeServer.Account do
  @type t :: %{id: integer()}
  @type order :: %{
          id: integer(),
          status: :valid | :pending,
          cert: nil | binary(),
          domains: AcmeServer.domains(),
          token: binary()
        }

  @spec create(AcmeServer.config(), String.t()) :: t()
  def create(config, client_key) do
    account = %{id: :erlang.unique_integer([:positive, :monotonic])}
    AcmeServer.Db.store_new!(config, {:account, client_key}, account)
    account
  end

  @spec fetch(AcmeServer.config(), String.t()) :: {:ok, t()} | :error
  def fetch(config, client_key), do: AcmeServer.Db.fetch(config, {:account, client_key})

  @spec new_order(AcmeServer.config(), t(), AcmeServer.domains()) :: order()
  def new_order(config, account, domains) do
    order = %{
      id: :erlang.unique_integer([:positive, :monotonic]),
      status: :pending,
      cert: nil,
      domains: domains,
      token: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }

    AcmeServer.Db.store_new!(config, {:order, account.id, order.id}, order)
    order
  end

  @spec update_order(AcmeServer.config(), integer(), order) :: true
  def update_order(config, account_id, order),
    do: AcmeServer.Db.store(config, {:order, account_id, order.id}, order)

  @spec get_order!(AcmeServer.config(), integer(), integer()) :: any()
  def get_order!(config, account_id, order_id),
    do: AcmeServer.Db.fetch!(config, {:order, account_id, order_id})
end
