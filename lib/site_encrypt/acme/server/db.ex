defmodule SiteEncrypt.Acme.Server.Db do
  @moduledoc false
  use GenServer

  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @spec store(SiteEncrypt.Acme.Server.config(), any(), any()) :: :ok
  def store(config, key, value) do
    :ets.insert(table(config), {key, value})
    :ok
  end

  @spec store_new!(SiteEncrypt.Acme.Server.config(), any(), any()) :: :ok
  def store_new!(config, key, value), do: :ok = store_new(config, key, value)

  @spec store_new(SiteEncrypt.Acme.Server.config(), any(), any()) :: :ok | :error
  def store_new(config, key, value),
    do: if(:ets.insert_new(table(config), {key, value}), do: :ok, else: :error)

  @spec fetch!(SiteEncrypt.Acme.Server.config(), any()) :: any()
  def fetch!(config, key) do
    {:ok, value} = fetch(config, key)
    value
  end

  @spec fetch(SiteEncrypt.Acme.Server.config(), any()) :: {:ok, any()} | :error
  def fetch(config, key) do
    case :ets.lookup(table(config), key) do
      [{^key, value}] -> {:ok, value}
      _ -> :error
    end
  end

  @spec pop!(SiteEncrypt.Acme.Server.config(), any()) :: any()
  def pop!(config, key) do
    [{^key, value}] = :ets.take(table(config), key)
    value
  end

  defp table(config) do
    {:ok, _pid, table} = SiteEncrypt.Acme.Server.Registry.lookup({__MODULE__, config.site})
    table
  end

  @impl GenServer
  def init(config) do
    table = :ets.new(__MODULE__, [:public, read_concurrency: true, write_concurrency: true])
    SiteEncrypt.Acme.Server.Registry.register({__MODULE__, config.site}, table)
    {:ok, nil}
  end
end
