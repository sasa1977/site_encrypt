defmodule SiteEncrypt.Certifier do
  use Parent.GenServer
  alias SiteEncrypt.{Certbot, Logger}

  def start_link(callback) do
    Parent.GenServer.start_link(
      __MODULE__,
      callback,
      name: name(callback.config().domain)
    )
  end

  defp name(domain), do: SiteEncrypt.Registry.via_tuple({__MODULE__, domain})

  @impl GenServer
  def init(callback) do
    start_fetch(callback)
    {:ok, %{callback: callback}}
  end

  @impl GenServer
  def handle_info(:start_fetch, state) do
    start_fetch(state.callback)
    {:noreply, state}
  end

  def handle_info(other, state), do: super(other, state)

  @impl Parent.GenServer
  def handle_child_terminated(:fetcher, _pid, _reason, state) do
    config = state.callback.config()
    log(config, "Certbot finished")
    Process.send_after(self(), :start_fetch, config.renew_interval())
    {:noreply, state}
  end

  defp start_fetch(callback) do
    config = callback.config()

    if config.run_client? and not Parent.GenServer.child?(:fetcher) do
      log(config, "Starting certbot")

      Parent.GenServer.start_child(%{
        id: :fetcher,
        start: {Task, :start_link, [fn -> get_certs(callback, config) end]}
      })
    end
  end

  defp get_certs(callback, config) do
    case Certbot.ensure_cert(config) do
      {:error, output} ->
        Logger.log(:error, "Error obtaining certificate:\n#{output}")

      {:new_cert, output} ->
        log(config, output)
        log(config, "Obtained new certificate, restarting endpoint")

        callback.handle_new_cert(config)

      {:no_change, output} ->
        log(config, output)
        :ok
    end
  end

  defp log(config, output), do: Logger.log(config.log_level, output)
end
