defmodule SiteEncrypt.Certifier do
  alias SiteEncrypt.{Certbot, Logger}

  def force_renew(callback),
    do: do_get_cert(callback, callback.config(), force_renewal: true)

  @spec child_spec(module) :: Supervisor.child_spec()
  def child_spec(callback) do
    config = callback.config()

    Periodic.child_spec(
      id: __MODULE__,
      run: fn -> get_cert(callback) end,
      initial_delay: 0,
      every: config.renew_interval,
      on_overlap: :stop_previous
    )
  end

  defp get_cert(callback) do
    config = callback.config()
    if config.run_client?, do: do_get_cert(callback, config)
  end

  defp do_get_cert(callback, config, opts \\ []) do
    case Certbot.ensure_cert(config, opts) do
      {:error, output} ->
        Logger.log(:error, "Error obtaining certificate for #{config.domain}:\n#{output}")

      {:new_cert, output} ->
        log(config, output)
        log(config, "Obtained new certificate for #{config.domain}")

        SiteEncrypt.initialize_certs(config)
        :ssl.clear_pem_cache()
        callback.handle_new_cert()

      {:no_change, output} ->
        log(config, output)
        :ok
    end
  end

  defp log(config, output), do: Logger.log(config.log_level, output)
end
