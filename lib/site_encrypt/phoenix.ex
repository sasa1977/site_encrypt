defmodule SiteEncrypt.Phoenix do
  @moduledoc """
  `SiteEncrypt` adapter for Phoenix endpoints.

  ## Usage

  1. Add `use SiteEncrypt.Phoenix` to your endpoint immediately after `use Phoenix.Endpoint`
  2. Configure https via `configure_https/2`.
  3. Add the implementation of `c:SiteEncrypt.certification/0` to the endpoint (the
    `@behaviour SiteEncrypt` is injected when this module is used).

  """

  @doc false
  use Supervisor

  @doc """
  Merges paths to key and certificates to the `:https` configuration of the endpoint config.

  Invoke this macro from `c:Phoenix.Endpoint.init/2` to complete the https configuration:

      defmodule MyEndpoint do
        # ...

        @impl Phoenix.Endpoint
        def init(_key, config) do
          # this will merge key, cert, and chain into `:https` configuration from config.exs
          {:ok, SiteEncrypt.Phoenix.configure_https(config)}

          # to completely configure https from `init/2`, invoke:
          #   SiteEncrypt.Phoenix.configure_https(config, port: 4001, ...)
        end

        # ...
      end

  The `options` are any valid adapter HTTPS options. For many great tips on configuring HTTPS for
  production refer to the [Plug HTTPS guide](https://hexdocs.pm/plug/https.html#content).
  """
  defmacro configure_https(config, https_opts \\ []) do
    quote bind_quoted: [config: config, https_opts: https_opts] do
      https_config =
        (Keyword.get(config, :https) || [])
        |> Config.Reader.merge(https_opts)
        |> Config.Reader.merge(SiteEncrypt.https_keys(__MODULE__))

      Keyword.put(config, :https, https_config)
    end
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      unless Enum.member?(@behaviour, Phoenix.Endpoint),
        do: raise("SiteEncrypt.Phoenix must be used after Phoenix.Endpoint")

      @behaviour SiteEncrypt
      require SiteEncrypt
      require SiteEncrypt.Phoenix

      plug SiteEncrypt.AcmeChallenge, __MODULE__

      @impl SiteEncrypt
      def handle_new_cert, do: :ok

      defoverridable handle_new_cert: 0
    end
  end

  @doc false
  def start_link(endpoint) do
    config = endpoint.certification()

    # The supervision tree is one layer deeper for easier testing. We're starting the site
    # supervisor as a single child of the root supervisor. All other processes (e.g. endpoint,
    # certification, internal acme server) are running under the site supervisor.
    #
    # This supervision structure allows us to easily stop and restart the entire site by stopping
    # and starting the site supervisor.
    Supervisor.start_link(
      [
        %{
          id: :site,
          type: :supervisor,
          start: {Supervisor, :start_link, [__MODULE__, {config, endpoint}]}
        }
      ],
      strategy: :one_for_one,
      name: SiteEncrypt.Registry.name(config.id, :root)
    )
  end

  @doc false
  def restart_site(id, fun) do
    root_pid = SiteEncrypt.Registry.whereis(id, :root)
    Supervisor.terminate_child(root_pid, :site)
    fun.()
    Supervisor.restart_child(root_pid, :site)
    :ok
  end

  @impl Supervisor
  def init({config, endpoint}) do
    :ok = SiteEncrypt.Registry.register_main_site(config)

    SiteEncrypt.initialize_certs(config)

    Supervisor.init(
      [
        Supervisor.child_spec(endpoint, id: :endpoint),
        # The remaining processes are started via `start_certification`. This is needed so we
        # can get the fully shaped endpoint config, and determine if we need to start certification
        # processes.
        %{
          id: :certification,
          start: {__MODULE__, :start_certification, [config, endpoint]},
          type: :supervisor
        }
      ],
      strategy: :one_for_one
    )
  end

  @doc false
  def start_certification(config, endpoint) do
    server? =
      with nil <- endpoint.config(:server),
           do: Application.get_env(:phoenix, :serve_endpoints, false)

    if server? do
      Supervisor.start_link(
        Enum.reject(
          [acme_server_spec(config, endpoint), {SiteEncrypt.Certification, config}],
          &is_nil/1
        ),
        strategy: :one_for_one
      )
    else
      # we won't start certification if the endpoint is not serving requests
      :ignore
    end
  end

  defp acme_server_spec(%{directory_url: url}, _endpoint) when is_binary(url), do: nil

  defp acme_server_spec(%{directory_url: {:internal, acme_server_config}} = config, endpoint) do
    port = Keyword.fetch!(acme_server_config, :port)
    SiteEncrypt.log(config, "Running local ACME server at port #{port}")

    SiteEncrypt.Acme.Server.Standalone.child_spec(
      adapter: {Plug.Cowboy, options: [port: port]},
      dns: dns(config, endpoint)
    )
  end

  defp dns(config, endpoint) do
    config.domains
    |> Enum.map(&{&1, fn -> "localhost:#{endpoint.config(:http) |> Keyword.fetch!(:port)}" end})
    |> Enum.into(%{})
  end
end
