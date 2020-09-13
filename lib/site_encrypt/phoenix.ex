defmodule SiteEncrypt.Phoenix do
  @moduledoc """
  `SiteEncrypt` adapter for Phoenix endpoints.

  ## Usage

  1. Add `use SiteEncrypt.Phoenix` to your endpoint immediately after `use Phoenix.Endpoint`
  2. Configure https via `configure_https/2`.
  3. Add the implementation of `c:SiteEncrypt.certification/0` to the endpoint (the
    `@behaviour SiteEncrypt` is injected when this module is used).

  """

  use Parent.Supervisor
  alias SiteEncrypt.{Acme, Registry}

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
    Parent.Supervisor.start_link(
      children(endpoint),
      name: {:via, Elixir.Registry, {Registry, endpoint}}
    )
  end

  @doc false
  def restart_site(endpoint, fun) do
    root = Registry.root(endpoint)
    Parent.Client.shutdown_all(root)
    fun.()
    Enum.each(children(endpoint), fn spec -> {:ok, _} = Parent.Client.start_child(root, spec) end)
  end

  defp children(endpoint) do
    [
      Parent.child_spec(endpoint, id: :endpoint, start: fn -> start_endpoint(endpoint) end),
      Parent.child_spec(Acme.Server,
        start: fn -> start_acme_server(endpoint) end,
        binds_to: [:endpoint]
      )
    ] ++ SiteEncrypt.Certification.child_specs(endpoint)
  end

  defp start_endpoint(endpoint) do
    config = endpoint.certification()
    Registry.store_config(endpoint, config)
    SiteEncrypt.initialize_certs(config)
    endpoint.start_link([])
  end

  defp start_acme_server(endpoint) do
    config = Registry.config(endpoint)

    with endpoint_port when not is_nil(endpoint_port) <- endpoint_port(config),
         port when not is_nil(port) <- acme_server_port(config) do
      dns = dns(config, endpoint_port)
      Acme.Server.start_link(config.id, port, dns, log_level: config.log_level)
    else
      _ -> :ignore
    end
  end

  defp endpoint_port(%{id: endpoint}) do
    if server?(endpoint), do: endpoint.config(:http) |> Keyword.fetch!(:port)
  end

  defp server?(endpoint) do
    with nil <- endpoint.config(:server),
         do: Application.get_env(:phoenix, :serve_endpoints, false)
  end

  defp dns(config, endpoint_port),
    do: Enum.into(config.domains, %{}, &{&1, fn -> "localhost:#{endpoint_port}" end})

  defp acme_server_port(%{directory_url: {:internal, acme_server_opts}}),
    do: Keyword.get(acme_server_opts, :port)

  defp acme_server_port(_), do: nil
end
