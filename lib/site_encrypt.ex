defmodule SiteEncrypt do
  require Logger

  config_type = [
    id: quote(do: id),
    ca_url: quote(do: ca_url),
    domain: quote(do: String.t()),
    extra_domains: quote(do: [String.t()]),
    email: quote(do: String.t()),
    base_folder: quote(do: String.t()),
    cert_folder: quote(do: String.t()),
    renew_interval: quote(do: pos_integer()),
    log_level: quote(do: log_level),
    mode: quote(do: :auto | :manual),
    callback: quote(do: __MODULE__),
    assigns: quote(do: map),
    backup: quote(do: String.t()),
    certifier: quote(do: SiteEncrypt.Native | SiteEncrypt.Certbot)
  ]

  @typedoc false
  @type config :: %{
          unquote_splicing(Keyword.drop(config_type, ~w/backup/a)),
          backup: String.t() | nil
        }

  @type certification :: unquote(Keyword.drop(config_type, ~w/callback assigns/a))

  @type id :: any
  @type ca_url :: String.t() | {:local_acme_server, [port: pos_integer]}
  @type log_level :: Logger.level()

  @callback certification() :: certification()
  @callback handle_new_cert() :: any

  @spec https_keys(id) :: [keyfile: Path.t(), certfile: Path.t(), cacertfile: Path.t()]
  def https_keys(id) do
    config = SiteEncrypt.Registry.config(id)

    [
      keyfile: Path.join(config.cert_folder, "privkey.pem"),
      certfile: Path.join(config.cert_folder, "cert.pem"),
      cacertfile: Path.join(config.cert_folder, "chain.pem")
    ]
  end

  @doc false
  @spec normalized_config(module, certification) :: config
  def normalized_config(callback, defaults \\ []) do
    config =
      defaults()
      |> Map.merge(Map.new(defaults))
      |> Map.merge(Map.new(callback.certification()))

    if rem(config.renew_interval, 1000) != 0,
      do: raise("renew interval must be divisible by 1000 (i.e. expressed in seconds)")

    if config.renew_interval < 1000,
      do: raise("renew interval must be larger than 1 second")

    Map.put(config, :callback, callback)
  end

  defp defaults do
    %{
      renew_interval: :timer.hours(24),
      extra_domains: [],
      log_level: :info,
      mode: :auto,
      assigns: %{},
      backup: nil,
      certifier: SiteEncrypt.Certbot
    }
  end

  @doc false
  def initialize_certs(config) do
    File.mkdir_p!(config.cert_folder)
    SiteEncrypt.Certifier.restore(config)

    case config.certifier.pems(config) do
      {:ok, keys} -> store_pems(config, keys)
      :error -> unless certificates_exist?(config), do: generate_self_signed_certificate!(config)
    end
  end

  defp store_pems(config, keys) do
    Enum.each(
      keys,
      fn {name, content} ->
        File.write!(Path.join(config.cert_folder, "#{name}.pem"), content)
      end
    )
  end

  defp certificates_exist?(config) do
    ~w(privkey.pem cert.pem chain.pem)
    |> Stream.map(&Path.join(config.cert_folder, &1))
    |> Enum.all?(&File.exists?/1)
  end

  defp generate_self_signed_certificate!(config) do
    Logger.info(
      "Generating a temporary self-signed certificate. " <>
        "This certificate will be used until a proper certificate is issued by the CA server."
    )

    [config.domain | config.extra_domains]
    |> AcmeServer.Crypto.self_signed_chain()
    |> Stream.map(fn {type, pem} -> {file_name(type), pem} end)
    |> Enum.each(&save_pem!(config, &1))
  end

  defp file_name(:ca_cert), do: "chain.pem"
  defp file_name(:server_cert), do: "cert.pem"
  defp file_name(:server_key), do: "privkey.pem"

  defp save_pem!(config, {file_name, contents}),
    do: File.write!(Path.join(config.cert_folder, file_name), contents)
end
