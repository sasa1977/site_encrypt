defmodule SiteEncrypt.Certification.Job do
  @moduledoc false

  use Parent.GenServer
  require Logger

  @callback pems(SiteEncrypt.config()) :: {:ok, SiteEncrypt.pems()} | :error
  @callback full_challenge(SiteEncrypt.config(), String.t()) :: String.t()

  @callback certify(SiteEncrypt.config(), force_renewal: boolean) :: :ok | :error

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

  @spec post_certify(SiteEncrypt.config()) :: :ok
  def post_certify(config) do
    {:ok, keys} = SiteEncrypt.client(config).pems(config)
    SiteEncrypt.store_pems(config, keys)
    :ssl.clear_pem_cache()

    unless is_nil(config.backup), do: SiteEncrypt.Certification.backup(config)
    config.callback.handle_new_cert()

    :ok
  end

  @impl GenServer
  def init(config) do
    Parent.GenServer.start_child(%{
      id: :job,
      start: {Task, :start_link, [fn -> certify_and_apply(config) end]},
      timeout: :timer.minutes(5)
    })

    {:ok, config}
  end

  @impl Parent.GenServer
  def handle_child_terminated(:job, _meta, _pid, _reason, state), do: {:stop, :normal, state}

  defp certify_and_apply(config) do
    with {:ok, _pems} <- certify(config) do
      valid_until = SiteEncrypt.Certification.Periodic.cert_valid_until(config)
      renewal_date = SiteEncrypt.Certification.Periodic.renewal_date(config)

      SiteEncrypt.log(config, [
        "Certificate successfully obtained! It is valid until #{valid_until}. ",
        "Next renewal is scheduled for #{renewal_date}. "
      ])

      post_certify(config)
    end
  end
end
