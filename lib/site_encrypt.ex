defmodule SiteEncrypt do
  require Logger

  @type config :: %{
          required(:ca_url) => ca_url,
          required(:domain) => String.t(),
          optional(:extra_domains) => [String.t()],
          required(:email) => String.t(),
          required(:base_folder) => String.t(),
          required(:cert_folder) => String.t(),
          optional(:renew_interval) => pos_integer(),
          optional(:log_level) => log_level,
          optional(:name) => GenServer.name(),
          optional(:mode) => :auto | :manual
        }

  @type ca_url :: String.t() | {:local_acme_server, [port: pos_integer]}
  @type log_level :: Logger.level()

  @callback certification_config() :: config
  @callback handle_new_cert() :: any

  @spec https_keys(module) :: [keyfile: Path.t(), certfile: Path.t(), cacertfile: Path.t()]
  def https_keys(callback) do
    config = SiteEncrypt.Registry.config(callback)

    [
      keyfile: Path.join(config.cert_folder, "privkey.pem"),
      certfile: Path.join(config.cert_folder, "cert.pem"),
      cacertfile: Path.join(config.cert_folder, "chain.pem")
    ]
  end

  @doc false
  def initialize_certs(config) do
    File.mkdir_p!(config.cert_folder)

    case SiteEncrypt.Certbot.https_keys(config) do
      {:ok, keys} -> copy_keys_to_cert_folder(config, keys)
      :error -> unless certificates_exist?(config), do: generate_self_signed_certificate!(config)
    end
  end

  defp copy_keys_to_cert_folder(config, keys) do
    keys
    |> Keyword.values()
    |> Stream.map(&Path.basename/1)
    |> Stream.map(&Path.join(config.cert_folder, &1))
    |> Stream.zip(keys)
    |> Enum.each(fn {dest, {_role, src}} -> File.cp!(src, dest) end)
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
