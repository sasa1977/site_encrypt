defmodule SiteEncrypt.Certifier do
  require Logger
  alias SiteEncrypt.{Certbot, Logger, Registry}

  @spec force_renew(SiteEncrypt.id()) :: :ok | {:error, String.t()}
  def force_renew(id) do
    with_periodic_certification_paused(id, fn ->
      get_cert(Registry.config(id), force_renewal: true)
    end)
  end

  @spec restore(SiteEncrypt.id(), Path.t()) :: :ok
  def restore(id, source) do
    with_periodic_certification_paused(id, fn ->
      config = Registry.config(id)

      if File.exists?(config.base_folder),
        do: raise("#{config.base_folder} already exists, aborting restore")

      File.mkdir_p!(config.base_folder)

      :ok =
        :erl_tar.extract(to_charlist(source), [:compressed, cwd: to_char_list(config.base_folder)])

      post_cert_renew(config)
    end)
  end

  defp with_periodic_certification_paused(id, fun) do
    Supervisor.terminate_child(Registry.whereis(id, :site), __MODULE__)

    try do
      fun.()
    after
      Supervisor.restart_child(Registry.whereis(id, :site), __MODULE__)
    end
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
      job_shutdown: :timer.minutes(1),
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
        post_cert_renew(config)

      {:no_change, output} ->
        log(config, output)
        :ok
    end
  end

  defp log(config, output), do: Logger.log(config.log_level, output)

  defp post_cert_renew(config) do
    SiteEncrypt.initialize_certs(config)
    :ssl.clear_pem_cache()

    unless is_nil(config.backup), do: backup(config)
    config.callback.handle_new_cert()

    :ok
  end

  defp backup(config) do
    {:ok, tar} = :erl_tar.open(to_charlist(config.backup), [:write, :compressed])

    config.base_folder
    |> Path.join("*")
    |> Path.wildcard()
    |> Enum.each(fn path ->
      :ok =
        :erl_tar.add(
          tar,
          to_charlist(path),
          to_charlist(Path.relative_to(path, config.base_folder)),
          []
        )
    end)

    :ok = :erl_tar.close(tar)
  catch
    type, error ->
      Elixir.Logger.error(
        "Error backing up certificate: #{Exception.format(type, error, __STACKTRACE__)}"
      )
  end

  @doc false
  def tick(id, datetime) do
    :persistent_term.put({__MODULE__, id}, datetime)

    case Periodic.Test.sync_tick(Registry.name(id, :certifier), :infinity) do
      {:ok, :normal} -> :ok
      {:ok, abnormal} -> {:error, abnormal}
      error -> error
    end
  after
    :persistent_term.erase({{__MODULE__, id}, datetime})
  end
end
