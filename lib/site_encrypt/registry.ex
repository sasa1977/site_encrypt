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

  @spec register_challenge(SiteEncrypt.id(), String.t(), String.t()) :: :ok
  def register_challenge(id, challenge_token, key_thumbprint) do
    Registry.register(__MODULE__, {id, {:challenge, challenge_token}}, key_thumbprint)
    :ok
  end

  @spec get_challenge(SiteEncrypt.id(), String.t()) :: {pid, String.t()} | nil
  def get_challenge(id, challenge_token) do
    case Registry.lookup(__MODULE__, {id, {:challenge, challenge_token}}) do
      [{pid, key_thumbprint}] ->
        send(pid, {:got_challenge, id, challenge_token})
        key_thumbprint

      [] ->
        nil
    end
  end

  @spec await_challenges(SiteEncrypt.id(), [String.t()], non_neg_integer) :: boolean
  def await_challenges(_id, [], _timeout), do: true

  def await_challenges(id, [token | tokens], timeout) do
    start = System.monotonic_time()

    receive do
      {:got_challenge, ^id, ^token} ->
        time = System.convert_time_unit(System.monotonic_time() - start, :native, :millisecond)
        await_challenges(id, tokens, max(timeout - time, 0))
    after
      timeout -> false
    end
  end

  def name(id, role), do: {:via, Registry, {__MODULE__, {id, role}}}

  def whereis(id, role), do: GenServer.whereis(name(id, role))
end
