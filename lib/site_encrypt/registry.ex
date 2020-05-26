defmodule SiteEncrypt.Registry do
  @moduledoc false

  def child_spec(_),
    do: Supervisor.child_spec({Registry, keys: :unique, name: __MODULE__}, id: __MODULE__)

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

  def register_challenge!(id, challenge_token, key_thumbprint) do
    Registry.register(__MODULE__, {id, {:challenge, challenge_token}}, key_thumbprint)
    :ok
  end

  def get_challenge(id, challenge_token) do
    case Registry.lookup(__MODULE__, {id, {:challenge, challenge_token}}) do
      [{pid, key_thumbprint}] -> {pid, key_thumbprint}
      [] -> nil
    end
  end

  def name(id, role), do: {:via, Registry, {__MODULE__, {id, role}}}

  def whereis(id, role), do: GenServer.whereis(name(id, role))
end
