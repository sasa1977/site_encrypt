defmodule AcmeServer.Db do
  use GenServer

  @type site :: String.t()
  @type dns :: %{String.t() => String.t()}
  @type config :: %{site: site, site_uri: URI.t(), dns: dns}

  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @spec store(config, tuple(), map()) :: true
  def store(config, key, value), do: :ets.insert(table(config), {key, value})

  @spec store_new!(config, tuple(), map()) :: true | false
  def store_new!(config, key, value), do: true = :ets.insert_new(table(config), {key, value})

  @spec store_new(config, tuple(), map()) :: true | false
  def store_new(config, key, value), do: :ets.insert_new(table(config), {key, value})

  @spec fetch!(config, any()) :: any()
  def fetch!(config, key) do
    {:ok, value} = fetch(config, key)
    value
  end

  @spec fetch(config, any()) :: {:ok, any()} | :error
  def fetch(config, key) do
    case :ets.lookup(table(config), key) do
      [{^key, value}] -> {:ok, value}
      _ -> :error
    end
  end

  @spec pop!(config, any()) :: any()
  def pop!(config, key) do
    [{^key, value}] = :ets.take(table(config), key)
    value
  end

  defp table(config) do
    {:ok, _pid, table} = AcmeServer.Registry.lookup({__MODULE__, config.site})
    table
  end

  @impl GenServer
  def init(config) do
    table = :ets.new(__MODULE__, [:public, read_concurrency: true, write_concurrency: true])
    AcmeServer.Registry.register({__MODULE__, config.site}, table)
    {:ok, nil}
  end
end
