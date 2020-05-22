defmodule SiteEncrypt.Certifier.Job do
  use Parent.GenServer
  alias SiteEncrypt.Logger
  require Logger

  @type pems :: [privkey: String.t(), cert: String.t(), chain: String.t()]

  @callback pems(SiteEncrypt.config()) :: {:ok, pems} | :error
  @callback full_challenge(SiteEncrypt.config(), String.t()) :: String.t()

  @callback certify(SiteEncrypt.config(), http_pool :: pid, force_renewal: boolean) ::
              :new_cert | :no_change | :error

  def start_link({config, opts}) do
    Parent.GenServer.start_link(
      __MODULE__,
      {config, opts},
      name: SiteEncrypt.Registry.name(config.id, __MODULE__)
    )
  end

  def post_certify(config) do
    SiteEncrypt.initialize_certs(config)
    :ssl.clear_pem_cache()

    unless is_nil(config.backup), do: backup(config)
    config.callback.handle_new_cert()

    :ok
  end

  @impl GenServer
  def init({config, opts}) do
    opts =
      if match?({:local_acme_server, _}, config.ca_url),
        do: [{:verify_server_cert, false} | opts],
        else: opts

    {:ok, http_pool} = Parent.GenServer.start_child({AcmeClient.Http, opts})

    Parent.GenServer.start_child(%{
      id: :job,
      start: {Task, :start_link, [fn -> certify(config, http_pool, opts) end]},
      timeout: :timer.minutes(5)
    })

    {:ok, config}
  end

  @impl Parent.GenServer
  def handle_child_terminated(:job, _meta, _pid, _reason, state), do: {:stop, :normal, state}

  defp certify(config, http_pool, opts) do
    case config.certifier.certify(config, http_pool, opts) do
      :error -> Logger.log(:error, "Error obtaining certificate for #{config.domain}")
      :new_cert -> post_certify(config)
      :no_change -> :ok
    end
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
      Logger.log(
        :error,
        "Error backing up certificate: #{Exception.format(type, error, __STACKTRACE__)}"
      )
  end
end
