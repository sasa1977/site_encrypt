defmodule SiteEncrypt.Certifier do
  alias SiteEncrypt.{Certbot, Logger, Registry}

  @spec force_renew(SiteEncrypt.id()) :: :ok | {:error, String.t()}
  def force_renew(id),
    do: get_cert(Registry.config(id), force_renewal: true)

  @spec tick_at(SiteEncrypt.id(), DateTime.t()) :: :ok | {:error, any}
  def tick_at(id, datetime) do
    :persistent_term.put({__MODULE__, id}, datetime)

    case Periodic.Test.sync_tick(Registry.name(id, :certifier), :infinity) do
      {:ok, :normal} -> :ok
      {:ok, abnormal} -> {:error, abnormal}
      error -> error
    end
  after
    :persistent_term.erase({{__MODULE__, id}, datetime})
  end

  @spec child_spec(SiteEncrypt.config()) :: Supervisor.child_spec()
  def child_spec(config) do
    renew_interval_sec = div(config.renew_interval, 1000)

    Periodic.child_spec(
      id: __MODULE__,
      run: fn -> get_cert(config) end,
      every: :timer.seconds(1),
      when: fn ->
        utc_now(config.id) |> DateTime.to_unix() |> rem(renew_interval_sec) == 0 or
          not Certbot.keys_available?(config)
      end,
      on_overlap: :ignore,
      timeout: :timer.minutes(1),
      mode: config.mode,
      name: Registry.name(config.id, :certifier)
    )
  end

  defp utc_now(id), do: :persistent_term.get({__MODULE__, id}, DateTime.utc_now())

  defp get_cert(config, opts \\ []) do
    case Certbot.ensure_cert(config, opts) do
      {:error, output} ->
        Logger.log(:error, "Error obtaining certificate for #{config.domain}:\n#{output}")
        {:error, output}

      {:new_cert, output} ->
        log(config, output)
        log(config, "Obtained new certificate for #{config.domain}")

        SiteEncrypt.initialize_certs(config)
        :ssl.clear_pem_cache()
        config.callback.handle_new_cert()

        :ok

      {:no_change, output} ->
        log(config, output)
        :ok
    end
  end

  defp log(config, output), do: Logger.log(config.log_level, output)
end
