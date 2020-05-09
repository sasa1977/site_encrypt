defmodule SiteEncrypt.Certifier do
  alias SiteEncrypt.{Certbot, Logger}

  @spec force_renew(module) :: :ok | {:error, String.t()}
  def force_renew(callback),
    do: do_get_cert(callback, callback.config(), force_renewal: true)

  @spec tick_at(GenServer.name(), DateTime.t()) :: :ok | {:error, any}
  def tick_at(name, datetime) do
    :persistent_term.put(__MODULE__, datetime)

    case Periodic.Test.sync_tick(name, :infinity) do
      {:ok, :normal} -> :ok
      {:ok, abnormal} -> {:error, abnormal}
      error -> error
    end
  after
    :persistent_term.erase({__MODULE__, datetime})
  end

  @spec child_spec(module) :: Supervisor.child_spec()
  def child_spec(callback) do
    config = callback.config()

    renew_interval_ms = Map.get(config, :renew_interval, :timer.hours(24))

    if rem(renew_interval_ms, 1000) != 0,
      do: raise("renew interval must be divisible by 1000 (i.e. expressed in seconds)")

    if renew_interval_ms < 1000,
      do: raise("renew interval must be larger than 1 second")

    renew_interval = div(Map.get(config, :renew_interval, :timer.hours(24)), 1000)

    periodic_opts =
      [
        id: __MODULE__,
        run: fn -> get_cert(callback) end,
        every: :timer.seconds(1),
        when: fn ->
          utc_now() |> DateTime.to_unix() |> rem(renew_interval) == 0 or
            not Certbot.keys_available?(config)
        end,
        on_overlap: :ignore,
        timeout: :timer.minutes(1)
      ]
      |> Keyword.merge(config |> Map.take(~w/name mode/a) |> Map.to_list())

    Periodic.child_spec(periodic_opts)
  end

  defp utc_now, do: :persistent_term.get(__MODULE__, DateTime.utc_now())

  defp get_cert(callback) do
    config = callback.config()
    if Map.get(config, :run_client?, true), do: do_get_cert(callback, config)
  end

  defp do_get_cert(callback, config, opts \\ []) do
    case Certbot.ensure_cert(config, opts) do
      {:error, output} ->
        Logger.log(:error, "Error obtaining certificate for #{config.domain}:\n#{output}")
        {:error, output}

      {:new_cert, output} ->
        log(config, output)
        log(config, "Obtained new certificate for #{config.domain}")

        SiteEncrypt.initialize_certs(config)
        :ssl.clear_pem_cache()
        callback.handle_new_cert()

        :ok

      {:no_change, output} ->
        log(config, output)
        :ok
    end
  end

  defp log(config, output), do: Logger.log(Map.get(config, :log_level, :info), output)
end
