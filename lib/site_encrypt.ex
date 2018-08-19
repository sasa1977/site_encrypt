defmodule SiteEncrypt do
  require Logger

  @type config :: %{
          run_client?: boolean,
          ca_url: String.t() | {:local_acme_server, %{port: pos_integer, adapter: module}},
          domain: String.t(),
          extra_domains: [String.t()],
          email: String.t(),
          base_folder: String.t(),
          cert_folder: String.t(),
          renew_interval: pos_integer(),
          log_level: log_level
        }

  @type log_level :: nil | Logger.level()

  @callback config() :: config
  @callback handle_new_cert() :: any

  def https_keys(config) do
    [
      keyfile: Path.join(config.cert_folder, "privkey.pem"),
      certfile: Path.join(config.cert_folder, "cert.pem"),
      cacertfile: Path.join(config.cert_folder, "chain.pem")
    ]
  end

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
    |> Stream.map(fn {type, entity} -> {file_name(type), X509.to_pem(entity)} end)
    |> Enum.each(&save_pem!(config, &1))
  end

  defp file_name(:ca_cert), do: "chain.pem"
  defp file_name(:server_cert), do: "cert.pem"
  defp file_name(:server_key), do: "privkey.pem"

  defp save_pem!(config, {file_name, contents}),
    do: File.write!(Path.join(config.cert_folder, file_name), contents)
end
