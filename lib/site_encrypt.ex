defmodule SiteEncrypt do
  require Logger

  @type config :: %{
          id: id,
          directory_url: directory_url,
          domains: nonempty_list(String.t()),
          emails: nonempty_list(String.t()),
          db_folder: String.t(),
          renew_before_expires_in_days: pos_integer(),
          log_level: log_level,
          mode: :auto | :manual,
          certifier: SiteEncrypt.Native | SiteEncrypt.Certbot,
          backup: String.t() | nil,
          callback: module
        }

  @type id :: any
  @type directory_url :: String.t() | {:internal, [port: pos_integer]}
  @type log_level :: Logger.level()

  @callback certification() :: config()
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

  def log(config, chardata_or_fun), do: Logger.log(config.log_level, chardata_or_fun)

  defmacro configure(opts) do
    quote do
      unquote(__MODULE__).normalized_config(unquote(opts), __MODULE__, unquote(Mix.env()))
    end
  end

  @doc false
  @spec normalized_config(Keyword.t(), module, :dev | :test | :prod) :: config
  def normalized_config(opts, callback, mix_env) do
    config = Map.merge(defaults(callback, mix_env), Map.new(opts))

    if Enum.empty?(config.domains),
      do: raise("You need to provide at least one domain in `:domains` option")

    if Enum.empty?(config.emails),
      do: raise("You need to provide at least one email in `:emails` option")

    config
  end

  defp defaults(callback, mix_env) do
    %{
      id: callback,
      renew_before_expires_in_days: 30,
      domains: [],
      log_level: :info,
      mode: if(mix_env == :test, do: :manual, else: :auto),
      backup: nil,
      certifier: SiteEncrypt.Certbot,
      callback: callback
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
    log(
      config,
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
