defmodule SiteEncrypt.Certifier do
  alias SiteEncrypt.{Logger, Registry}

  def start_link(config) do
    Supervisor.start_link(
      [
        job_parent_spec(config),
        periodic_scheduler_spec(config)
      ],
      strategy: :one_for_one
    )
  end

  @spec force_renew(SiteEncrypt.id()) :: :already_started | :finished
  def force_renew(id), do: run_job(Registry.config(id), force_renewal: true)

  @spec restore(SiteEncrypt.config()) :: :ok
  def restore(config) do
    if not is_nil(config.backup) and
         File.exists?(config.backup) and
         not File.exists?(config.base_folder) do
      Logger.log(:info, "restoring certificates for #{config.domain}")
      File.mkdir_p!(config.base_folder)

      :ok =
        :erl_tar.extract(
          to_charlist(config.backup),
          [:compressed, cwd: to_char_list(config.base_folder)]
        )

      SiteEncrypt.Certifier.Job.post_certify(config)
      Logger.log(:info, "certificates for #{config.domain} restored")
    end
  end

  defp job_parent_spec(config) do
    {
      DynamicSupervisor,
      strategy: :one_for_one, name: Registry.name(config.id, __MODULE__.JobParent)
    }
  end

  defp periodic_scheduler_spec(config) do
    Periodic.child_spec(
      id: __MODULE__.Scheduler,
      run: fn -> run_job(config, []) end,
      every: :timer.seconds(1),
      when: fn -> time_to_renew?(config) or config.certifier.pems(config) == :error end,
      on_overlap: :ignore,
      mode: config.mode,
      name: Registry.name(config.id, __MODULE__.Scheduler)
    )
  end

  defp time_to_renew?(config) do
    renew_interval_sec = div(config.renew_interval, 1000)
    utc_now(config.id) |> DateTime.to_unix() |> rem(renew_interval_sec) == 0
  end

  defp utc_now(id), do: :persistent_term.get({__MODULE__, id}, DateTime.utc_now())

  defp run_job(config, opts) do
    case DynamicSupervisor.start_child(
           Registry.name(config.id, __MODULE__.JobParent),
           Supervisor.child_spec({SiteEncrypt.Certifier.Job, {config, opts}}, restart: :temporary)
         ) do
      {:ok, pid} ->
        mref = Process.monitor(pid)

        receive do
          {:DOWN, ^mref, :process, ^pid, _reason} -> :finished
        end

      {:error, {:already_started, _pid}} ->
        :already_started
    end
  end

  @doc false
  def tick(id, datetime) do
    :persistent_term.put({__MODULE__, id}, datetime)

    case Periodic.Test.sync_tick(Registry.name(id, __MODULE__.Scheduler), :infinity) do
      {:ok, :normal} -> :ok
      {:ok, abnormal} -> {:error, abnormal}
      error -> error
    end
  after
    :persistent_term.erase({{__MODULE__, id}, datetime})
  end

  @spec child_spec(SiteEncrypt.config()) :: Supervisor.child_spec()
  def child_spec(config) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]},
      type: :supervisor
    }
  end
end
