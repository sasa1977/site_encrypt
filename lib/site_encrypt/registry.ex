defmodule SiteEncrypt.Registry do
  def start_link(), do: Registry.start_link(keys: :unique, name: __MODULE__)

  def child_spec(_) do
    Supervisor.child_spec(
      Registry,
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    )
  end

  def name(callback),
    do: {:via, Registry, {__MODULE__, callback}}

  @spec config(module) :: SiteEncrypt.config()
  def config(callback) do
    [{_pid, config}] = Registry.lookup(__MODULE__, callback)
    config
  end

  def store_config(callback) do
    {new_config, _} =
      Registry.update_value(__MODULE__, callback, fn _ -> normalized_config(callback) end)

    new_config
  end

  defp normalized_config(callback) do
    config = Map.merge(defaults(), callback.certification_config())

    if rem(config.renew_interval, 1000) != 0,
      do: raise("renew interval must be divisible by 1000 (i.e. expressed in seconds)")

    if config.renew_interval < 1000,
      do: raise("renew interval must be larger than 1 second")

    config
  end

  defp defaults do
    %{
      run_client?: true,
      renew_interval: :timer.hours(24),
      extra_domains: [],
      log_level: :info,
      name: nil,
      mode: :auto
    }
  end
end
