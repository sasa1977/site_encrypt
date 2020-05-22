defmodule AcmeServer.Account do
  @type t :: %{id: id, location: String.t()}
  @type id :: String.t()
  @type key :: map
  @type order :: %{
          id: integer(),
          status: :valid | :pending | :ready,
          cert: nil | binary(),
          domains: AcmeServer.domains(),
          token: binary()
        }

  @spec create(AcmeServer.config(), key) :: t()
  def create(config, client_key) do
    id = client_key |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
    location = "#{config.site}/account/#{id}"
    account = %{id: id, location: location}

    AcmeServer.Db.store_new!(config, {:account, client_key}, account)

    account
  end

  @spec client_key(id) :: key
  def client_key(account_id),
    do: account_id |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term()

  @spec fetch(AcmeServer.config(), key) :: {:ok, t()} | :error
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

  @spec update_order(AcmeServer.config(), id, order) :: :ok
  def update_order(config, account_id, order),
    do: AcmeServer.Db.store(config, {:order, account_id, order.id}, order)

  @spec get_order!(AcmeServer.config(), id, integer()) :: any()
  def get_order!(config, account_id, order_id),
    do: AcmeServer.Db.fetch!(config, {:order, account_id, order_id})
end
