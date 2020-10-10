defmodule SiteEncrypt.Certification.Job do
  @moduledoc false

  use Parent.GenServer
  require Logger

  @callback pems(SiteEncrypt.config()) :: {:ok, SiteEncrypt.pems()} | :error
  @callback full_challenge(SiteEncrypt.config(), String.t()) :: String.t()

  @callback certify(SiteEncrypt.config(), force_certifyal: boolean) :: :ok | :error

  @spec certify(SiteEncrypt.config()) :: {:ok, SiteEncrypt.pems()} | :error
  def certify(config) do
    opts = [verify_server_cert: not SiteEncrypt.local_ca?(config)]

    case SiteEncrypt.client(config).certify(config, opts) do
      :error ->
        Logger.error("Error obtaining certificate for #{hd(config.domains)}")
        :error

      :ok ->
        SiteEncrypt.client(config).pems(config)
    end
  end

  def start_link(config) do
    Parent.GenServer.start_link(
      __MODULE__,
      config,
      name: SiteEncrypt.Registry.name(config.id, __MODULE__)
    )
  end

  @impl GenServer
  def init(config) do
    Parent.start_child(%{
      id: :job,
      start: {Task, :start_link, [fn -> certify_and_apply(config) end]},
      timeout: :timer.minutes(5),
      restart: :temporary
    })

    {:ok, config}
  end

  @impl Parent.GenServer
  def handle_child_terminated(%{id: :job} = info, state) do
    shutdown_reason = if info.reason == :normal, do: :normal, else: :job_error
    {:stop, shutdown_reason, state}
  end

  defp certify_and_apply(config) do
    with {:ok, pems} <- certify(config) do
      valid_until = SiteEncrypt.Certification.Periodic.cert_valid_until(config)
      renewal_date = SiteEncrypt.Certification.Periodic.renewal_date(config)

      SiteEncrypt.log(config, [
        "Certificate successfully obtained! It is valid until #{valid_until}. ",
        "Next renewal is scheduled for #{renewal_date}. "
      ])

      SiteEncrypt.set_certificate(config.id, pems)
    end
  end
end
