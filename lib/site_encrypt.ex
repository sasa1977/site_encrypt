defmodule SiteEncrypt do
  require Logger

  config_type = [
    id: quote(do: id),
    ca_url: quote(do: ca_url),
    domains: quote(do: nonempty_list(String.t())),
    email: quote(do: String.t()),
    db_folder: quote(do: String.t()),
    renew_before_expires_in_days: quote(do: pos_integer()),
    log_level: quote(do: log_level),
    mode: quote(do: :auto | :manual),
    callback: quote(do: __MODULE__),
    backup: quote(do: String.t()),
    certifier: quote(do: SiteEncrypt.Native | SiteEncrypt.Certbot)
  ]

  @typedoc false
  @type config :: %{
          unquote_splicing(Keyword.drop(config_type, ~w/backup/a)),
          backup: String.t() | nil
        }

  @type certification :: unquote(Keyword.drop(config_type, ~w/callback/a))

  @type id :: any
  @type ca_url :: String.t() | {:local_acme_server, [port: pos_integer]}
  @type log_level :: Logger.level()

  @callback certification() :: certification()
  @callback handle_new_cert() :: any

  @spec https_keys(id) :: [keyfile: Path.t(), certfile: Path.t(), cacertfile: Path.t()]
  def https_keys(id) do
    config = SiteEncrypt.Registry.config(id)

    [
      keyfile: Path.join(cert_folder(config), "privkey.pem"),
      certfile: Path.join(cert_folder(config), "cert.pem"),
      cacertfile: Path.join(cert_folder(config), "chain.pem")
    ]
  end

  @doc false
  @spec normalized_config(module, certification) :: config
  def normalized_config(callback, adapter_defaults \\ []) do
    config =
      defaults()
      |> Map.merge(Map.new(adapter_defaults))
      |> Map.merge(Map.new(callback.certification()))
      |> Map.put(:callback, callback)

    if Enum.empty?(config.domains),
      do: raise("You need to provide at least one domain in `:domains` option")

    config
  end

  defp defaults do
    %{
      renew_before_expires_in_days: 30,
      domains: [],
      log_level: :info,
      mode: :auto,
      backup: nil,
      certifier: SiteEncrypt.Certbot
    }
  end

  @doc false
  def initialize_certs(config) do
    SiteEncrypt.Certifier.restore(config)
    File.mkdir_p!(cert_folder(config))

    case config.certifier.pems(config) do
      {:ok, keys} -> store_pems(config, keys)
      :error -> unless certificates_exist?(config), do: generate_self_signed_certificate!(config)
    end
  end

  @doc false
  def store_pems(config, keys) do
    Enum.each(
      keys,
      fn {name, content} ->
        File.write!(Path.join(cert_folder(config), "#{name}.pem"), content)
      end
    )
  end

  defp certificates_exist?(config) do
    ~w(privkey.pem cert.pem chain.pem)
    |> Stream.map(&Path.join(cert_folder(config), &1))
    |> Enum.all?(&File.exists?/1)
  end

  defp generate_self_signed_certificate!(config) do
    Logger.info(
      "Generating a temporary self-signed certificate. " <>
        "This certificate will be used until a proper certificate is issued by the CA server."
    )

    config.domains
    |> AcmeServer.Crypto.self_signed_chain()
    |> Stream.map(fn {type, pem} -> {file_name(type), pem} end)
    |> Enum.each(&save_pem!(config, &1))
  end

  defp file_name(:ca_cert), do: "chain.pem"
  defp file_name(:server_cert), do: "cert.pem"
  defp file_name(:server_key), do: "privkey.pem"

  defp save_pem!(config, {file_name, contents}),
    do: File.write!(Path.join(cert_folder(config), file_name), contents)

  defp cert_folder(config),
    do: Path.join(config.db_folder, "certs/")
end
