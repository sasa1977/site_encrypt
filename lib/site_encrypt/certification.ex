defmodule SiteEncrypt.Certification do
  alias SiteEncrypt.Registry

  def start_link(config) do
    with {:ok, pid} <-
           Supervisor.start_link(
             [
               job_parent_spec(config),
               {SiteEncrypt.Certification.Periodic, config}
             ],
             strategy: :one_for_one
           ) do
      if config.mode == :auto and SiteEncrypt.client(config).pems(config) == :error,
        do: start_renew(config)

      {:ok, pid}
    end
  end

  @spec run_renew(SiteEncrypt.config()) :: :ok
  def run_renew(config) do
    pid =
      case start_renew(config) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    mref = Process.monitor(pid)

    receive do
      {:DOWN, ^mref, :process, ^pid, _reason} -> :ok
    end
  end

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

      with {:ok, _keys} <- SiteEncrypt.client(config).pems(config) do
        SiteEncrypt.Certification.Job.post_certify(config)
        SiteEncrypt.log(config, "certificates for #{hd(config.domains)} restored")
      end
    end
  end

  defp job_parent_spec(config) do
    {
      DynamicSupervisor,
      strategy: :one_for_one, name: Registry.name(config.id, __MODULE__.JobParent)
    }
  end

  defp start_renew(config) do
    DynamicSupervisor.start_child(
      Registry.name(config.id, __MODULE__.JobParent),
      Supervisor.child_spec({SiteEncrypt.Certification.Job, config}, restart: :temporary)
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
