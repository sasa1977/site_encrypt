defmodule SiteEncrypt.Certifier do
  alias SiteEncrypt.{Logger, Registry}

  def start_link(config) do
    with {:ok, pid} <-
           Supervisor.start_link(
             [job_parent_spec(config), periodic_scheduler_spec(config)],
             strategy: :one_for_one
           ) do
      if config.mode == :auto and config.certifier.pems(config) == :error,
        do: start_renew(config)

      {:ok, pid}
    end
  end

  @spec force_renew(SiteEncrypt.id()) :: :already_started | :finished
  def force_renew(id), do: run_renew(Registry.config(id))

  @spec restore(SiteEncrypt.config()) :: :ok
  def restore(config) do
    if not is_nil(config.backup) and
         File.exists?(config.backup) and
         not File.exists?(config.db_folder) do
      Logger.log(:info, "restoring certificates for #{hd(config.domains)}")
      File.mkdir_p!(config.db_folder)

      :ok =
        :erl_tar.extract(
          to_charlist(config.backup),
          [:compressed, cwd: to_char_list(config.db_folder)]
        )

      SiteEncrypt.Certifier.Job.post_certify(config)
      Logger.log(:info, "certificates for #{hd(config.domains)} restored")
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
      run: fn -> run_renew(config) end,
      every: :timer.seconds(1),
      when: fn -> time_to_renew?(config) end,
      on_overlap: :ignore,
      mode: config.mode,
      name: Registry.name(config.id, __MODULE__.Scheduler)
    )
  end

  defp time_to_renew?(config) do
    now = utc_now(config.id)
    midnight? = now.hour == 0 and now.minute == 0 and now.second == 0

    case {midnight?, config.certifier.pems(config)} do
      {false, _} ->
        false

      {true, :error} ->
        true

      {true, {:ok, pems}} ->
        cert_valid_until = pems |> Keyword.fetch!(:cert) |> cert_valid_until()
        DateTime.diff(cert_valid_until, now) < config.renew_before_expires_in_days * 24 * 60 * 60
    end
  end

  defp utc_now(id), do: :persistent_term.get({__MODULE__, id}, DateTime.utc_now())

  defp run_renew(config) do
    case start_renew(config) do
      {:ok, pid} ->
        mref = Process.monitor(pid)

        receive do
          {:DOWN, ^mref, :process, ^pid, _reason} -> :finished
        end

      {:error, {:already_started, _pid}} ->
        :already_started
    end
  end

  defp start_renew(config) do
    DynamicSupervisor.start_child(
      Registry.name(config.id, __MODULE__.JobParent),
      Supervisor.child_spec({SiteEncrypt.Certifier.Job, config}, restart: :temporary)
    )
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

  defp cert_valid_until(pem) do
    {:Validity, _from, to} =
      pem
      |> X509.Certificate.from_pem!()
      |> X509.Certificate.validity()

    X509.DateTime.to_datetime(to)
  end
end
