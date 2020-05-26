defmodule SiteEncrypt.Acme.Server.Account do
  @moduledoc false

  @type t :: %{id: id, location: String.t()}
  @type id :: String.t()
  @type key :: map
  @type order :: %{
          id: integer(),
          status: :valid | :pending | :ready,
          cert: nil | binary(),
          domains: SiteEncrypt.Acme.Server.domains(),
          token: binary()
        }

  @spec create(SiteEncrypt.Acme.Server.config(), key) :: t()
  def create(config, client_key) do
    id = client_key |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
    location = "#{config.site}/account/#{id}"
    account = %{id: id, location: location}

    SiteEncrypt.Acme.Server.Db.store_new!(config, {:account, client_key}, account)

    account
  end

  @spec client_key(id) :: key
  def client_key(account_id),
    do: account_id |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term()

  @spec fetch(SiteEncrypt.Acme.Server.config(), key) :: {:ok, t()} | :error
  def fetch(config, client_key),
    do: SiteEncrypt.Acme.Server.Db.fetch(config, {:account, client_key})

  @spec new_order(SiteEncrypt.Acme.Server.config(), t(), SiteEncrypt.Acme.Server.domains()) ::
          order()
  def new_order(config, account, domains) do
    order = %{
      id: :erlang.unique_integer([:positive, :monotonic]),
      status: :pending,
      cert: nil,
      domains: domains,
      token: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }

    SiteEncrypt.Acme.Server.Db.store_new!(config, {:order, account.id, order.id}, order)
    order
  end

  @spec update_order(SiteEncrypt.Acme.Server.config(), id, order) :: :ok
  def update_order(config, account_id, order),
    do: SiteEncrypt.Acme.Server.Db.store(config, {:order, account_id, order.id}, order)

  @spec get_order!(SiteEncrypt.Acme.Server.config(), id, integer()) :: any()
  def get_order!(config, account_id, order_id),
    do: SiteEncrypt.Acme.Server.Db.fetch!(config, {:order, account_id, order_id})
end
