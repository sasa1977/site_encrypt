defmodule SiteEncrypt.Certifier do
  alias SiteEncrypt.Registry

  def start_link(config) do
    with {:ok, pid} <-
           Supervisor.start_link(
             [job_parent_spec(config), {SiteEncrypt.Certifier.PeriodicRefresh, config}],
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
      SiteEncrypt.log(config, "restoring certificates for #{hd(config.domains)}")
      File.mkdir_p!(config.db_folder)

      :ok =
        :erl_tar.extract(
          to_charlist(config.backup),
          [:compressed, cwd: to_char_list(config.db_folder)]
        )

      SiteEncrypt.Certifier.Job.post_certify(config)
      SiteEncrypt.log(config, "certificates for #{hd(config.domains)} restored")
    end
  end

  defp job_parent_spec(config) do
    {
      DynamicSupervisor,
      strategy: :one_for_one, name: Registry.name(config.id, __MODULE__.JobParent)
    }
  end

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

  @spec child_spec(SiteEncrypt.config()) :: Supervisor.child_spec()
  def child_spec(config) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]},
      type: :supervisor
    }
  end
end
