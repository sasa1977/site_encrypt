defmodule SiteEncrypt.Certifier do
  alias SiteEncrypt.{Certbot, Logger}

  @spec child_spec(module) :: Supervisor.child_spec()
  def child_spec(callback) do
    config = callback.config()

    Periodic.child_spec(
      id: __MODULE__,
      run: fn -> get_certs(callback) end,
      initial_delay: 0,
      every: config.renew_interval,
      timeout: max(config.renew_interval - :timer.seconds(5), :timer.minutes(1)),
      overlap?: false,
      log_level: config.log_level,
      log_meta: [periodic_job: "certify #{config.domain}"]
    )
  end

  defp get_certs(callback) do
    config = callback.config()

    if config.run_client? do
      case Certbot.ensure_cert(config) do
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
  end

  defp log(config, output), do: Logger.log(config.log_level, output)
end
