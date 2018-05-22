defmodule AcmeServer.Db do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def store(key, value), do: :ets.insert(__MODULE__, {key, value})
  def store_new!(key, value), do: true = :ets.insert_new(__MODULE__, {key, value})
  def store_new(key, value), do: :ets.insert_new(__MODULE__, {key, value})

  def fetch!(key) do
    {:ok, value} = fetch(key)
    value
  end

  def fetch(key) do
    case :ets.lookup(__MODULE__, key) do
      [{^key, value}] -> {:ok, value}
      _ -> :error
    end
  end

  def pop!(key) do
    [{^key, value}] = :ets.take(__MODULE__, key)
    value
  end

  def init(nil) do
    :ets.new(__MODULE__, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, nil}
  end
end
