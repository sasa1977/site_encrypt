defmodule SiteEncrypt.Acme.Server.Db do
  @moduledoc false
  use GenServer
  alias SiteEncrypt.Acme

  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @spec store(Acme.Server.config(), any(), any()) :: :ok
  def store(config, key, value) do
    :ets.insert(table(config), {key, value})
    :ok
  end

  @spec store_new!(Acme.Server.config(), any(), any()) :: :ok
  def store_new!(config, key, value), do: :ok = store_new(config, key, value)

  @spec store_new(Acme.Server.config(), any(), any()) :: :ok | :error
  def store_new(config, key, value),
    do: if(:ets.insert_new(table(config), {key, value}), do: :ok, else: :error)

  @spec fetch!(Acme.Server.config(), any()) :: any()
  def fetch!(config, key) do
    {:ok, value} = fetch(config, key)
    value
  end

  @spec fetch(Acme.Server.config(), any()) :: {:ok, any()} | :error
  def fetch(config, key) do
    case :ets.lookup(table(config), key) do
      [{^key, value}] -> {:ok, value}
      _ -> :error
    end
  end

  @spec pop!(Acme.Server.config(), any()) :: any()
  def pop!(config, key) do
    [{^key, value}] = :ets.take(table(config), key)
    value
  end

  defp table(config) do
    {:ok, table} = Parent.Client.child_meta(Acme.Server.whereis(config.id), __MODULE__)
    table
  end

  @impl GenServer
  def init(config), do: {:ok, nil, {:continue, {:create_table, config}}}

  @impl GenServer
  def handle_continue({:create_table, config}, state) do
    table = :ets.new(__MODULE__, [:public, read_concurrency: true, write_concurrency: true])
    Parent.Client.update_child_meta(Acme.Server.whereis(config.id), __MODULE__, fn _ -> table end)
    {:noreply, state}
  end
end
