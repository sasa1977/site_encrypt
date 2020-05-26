defmodule SiteEncrypt.Acme.Server.Registry do
  @moduledoc false

  def start_link(), do: Registry.start_link(keys: :unique, name: __MODULE__)

  def child_spec(_) do
    Supervisor.child_spec(
      Registry,
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    )
  end

  def via_tuple(key), do: {:via, Registry, {__MODULE__, key}}

  def register(key, value), do: Registry.register(__MODULE__, key, value)

  def lookup(key) do
    case Registry.lookup(__MODULE__, key) do
      [{pid, value}] -> {:ok, pid, value}
      _ -> :error
    end
  end
end
