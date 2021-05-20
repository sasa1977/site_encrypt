defmodule SiteEncrypt.Certification do
  @moduledoc false
  require Logger
  alias SiteEncrypt.Registry
  alias SiteEncrypt.Certification.Periodic

  def child_specs(id) do
    [
      %{
        id: __MODULE__.InitialRenewal,
        start: {Task, :start_link, [fn -> start_initial_renewal(id) end]},
        restart: :temporary,
        binds_to: [:site]
      },
      Parent.child_spec({Periodic, id}, binds_to: [:site])
    ]
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
          [:compressed, cwd: to_charlist(config.db_folder)]
        )

      with {:ok, pems} <- SiteEncrypt.client(config).pems(config) do
        SiteEncrypt.set_certificate(config.id, pems)
        SiteEncrypt.log(config, "certificates for #{hd(config.domains)} restored")
      end
    end
  catch
    type, error ->
      Logger.error(
        "Error restoring certificates: #{Exception.format(type, error, __STACKTRACE__)}"
      )
  end

  defp start_initial_renewal(id) do
    config = Registry.config(id)

    if config.mode == :auto do
      if Periodic.cert_due_for_renewal?(config) ||
           SiteEncrypt.certificate_subjects_changed?(config) do
        start_renew(config)
      else
        SiteEncrypt.log(config, [
          "Certificate for #{hd(config.domains)} is valid until ",
          "#{Periodic.cert_valid_until(config)}. ",
          "Next renewal is scheduled for #{Periodic.renewal_date(config)}."
        ])
      end
    end
  end

  defp start_renew(config) do
    Parent.Client.start_child(
      Registry.root(config.id),
      {SiteEncrypt.Certification.Job, config}
    )
  end
end
