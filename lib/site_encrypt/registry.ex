defmodule SiteEncrypt.Registry do
  def start_link(), do: Registry.start_link(keys: :unique, name: __MODULE__)

  def child_spec(_) do
    Supervisor.child_spec(
      Registry,
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    )
  end

  @spec config(SiteEncrypt.id()) :: SiteEncrypt.config()
  def config(id) do
    [{_pid, config}] = Registry.lookup(__MODULE__, {id, :site})
    config
  end

  @spec register_main_site(SiteEncrypt.config()) :: :ok | {:error, {:already_registered, pid}}
  def register_main_site(config) do
    with {:ok, _pid} <- Registry.register(__MODULE__, {config.id, :site}, config),
         do: :ok
  end

  @doc false
  def name(id, role), do: {:via, Registry, {__MODULE__, {id, role}}}
end
