defmodule AcmeServer.Account do
  def create(client_key) do
    account = %{id: :erlang.unique_integer([:positive, :monotonic]), status: :valid, contact: []}
    AcmeServer.Db.store_new!({:account, client_key}, account)
    account
  end

  def fetch(client_key), do: AcmeServer.Db.fetch({:account, client_key})

  def new_order(account, domains) do
    order = %{
      id: :erlang.unique_integer([:positive, :monotonic]),
      status: :pending,
      cert: nil,
      domains: domains,
      token: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }

    AcmeServer.Db.store_new!({:order, account.id, order.id}, order)
    order
  end

  def update_order(account_id, order),
    do: AcmeServer.Db.store({:order, account_id, order.id}, order)

  def get_order!(account_id, order_id), do: AcmeServer.Db.fetch!({:order, account_id, order_id})
end
