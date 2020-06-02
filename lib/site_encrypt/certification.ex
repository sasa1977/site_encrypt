defmodule SiteEncrypt.Certification do
  @moduledoc false
  require Logger
  alias SiteEncrypt.Registry
  alias SiteEncrypt.Certification.Periodic

  def start_link(config) do
    with {:ok, pid} <-
           Supervisor.start_link(
             [job_parent_spec(config), {Periodic, config}],
             strategy: :one_for_one
           ) do
      if config.mode == :auto do
        if Periodic.cert_due_for_renewal?(config) do
          start_renew(config)
        else
          SiteEncrypt.log(config, [
            "Certificate for #{hd(config.domains)} is valid until ",
            "#{Periodic.cert_valid_until(config)}. ",
            "Next renewal is scheduled for #{Periodic.renewal_date(config)}."
          ])
        end
      end

      {:ok, pid}
    end
  end

  @spec run_renew(SiteEncrypt.config()) :: :ok | :error
  def run_renew(config) do
    pid =
      case start_renew(config) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    mref = Process.monitor(pid)

    receive do
      {:DOWN, ^mref, :process, ^pid, reason} ->
        if reason == :normal, do: :ok, else: :error
    end
  end

  @spec backup(SiteEncrypt.config()) :: :ok
  def backup(config) do
    {:ok, tar} = :erl_tar.open(to_charlist(config.backup), [:write, :compressed])

    config.db_folder
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      :ok =
        :erl_tar.add(
          tar,
          to_charlist(path),
          to_charlist(Path.relative_to(path, config.db_folder)),
          []
        )
    end)

    :ok = :erl_tar.close(tar)
    File.chmod!(config.backup, 0o600)
  catch
    type, error ->
      Logger.error(
        "Error backing up certificates: #{Exception.format(type, error, __STACKTRACE__)}"
      )
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
  catch
    type, error ->
      Logger.error(
        "Error restoring certificates: #{Exception.format(type, error, __STACKTRACE__)}"
      )
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
