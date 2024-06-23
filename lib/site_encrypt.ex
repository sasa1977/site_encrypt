defmodule SiteEncrypt do
  @moduledoc "Functions for interacting with sites managed by SiteEncrypt."

  require Logger

  alias SiteEncrypt.Certification

  @opaque certification :: config

  @typedoc false
  @type config :: %{
          id: id,
          directory_url: directory_url,
          domains: nonempty_list(String.t()),
          emails: nonempty_list(String.t()),
          db_folder: String.t(),
          days_to_renew: pos_integer(),
          log_level: Logger.level(),
          mode: :auto | :manual,
          client: :native | :certbot,
          backup: String.t() | nil,
          callback: module,
          key_size: pos_integer,
          periodic_offset: Certification.Periodic.offset()
        }

  @type pems :: %{privkey: String.t(), cert: String.t(), chain: String.t()}

  @typedoc """
  Uniquely identifies the site certified via site_encrypt.

  The actual value is determined by the adapter used to start the site. For example, if
  `SiteEncrypt.Phoenix` is used, the site id is the endpoint module.
  """
  @type id :: any

  @typedoc false
  @type directory_url :: String.t() | {:internal, [port: pos_integer]}

  @doc """
  Invoked during startup to obtain certification info.

  See `configure/1` for details.
  """
  @callback certification() :: certification()

  @doc "Invoked after the new certificate has been obtained."
  @callback handle_new_cert() :: any

  @certification_schema [
    client: [
      type: {:in, [:native, :certbot]},
      required: true,
      doc: """
          Can be either `:native` or `:certbot`.

          The native client requires no extra OS-level dependencies, and it runs faster, which is
          especially useful in a local development and tests. However, this client is very immature,
          possibly buggy, and incomplete.

          The certbot client is a wrapper around the [certbot](https://certbot.eff.org/) tool, which has
          to be installed on the host machine. This client is much more reliable than the native client,
          but it is also significantly slower.

          As a compromise between these two choices, you can consider running certbot client in
          production and during CI tests, while using the native client for local development and local
          tests.
      """
    ],
    domains: [
      type: {:custom, __MODULE__, :validate_non_empty_string_list, []},
      required: true,
      doc: "The list of domains for which the certificate will be obtained. Must
      contain at least one element."
    ],
    emails: [
      type: {:custom, __MODULE__, :validate_non_empty_string_list, []},
      required: true,
      doc: "The list of email addresses which will be passed to the CA when
      creating the new account."
    ],
    db_folder: [
      type: :string,
      required: true,
      doc: "The folder where site_encrypt stores its data, such as certificates
      and account keys."
    ],
    directory_url: [
      type: {:custom, __MODULE__, :validate_directory_url, []},
      required: true,
      doc: """
      The URL to CA directory resource. It can be either a string
      (e.g. `"https://acme-v02.api.letsencrypt.org/directory"`) or a tuple in the shape of
      `{:internal, port: local_acme_server_port}`. In the latter case, an internal ACME server
      will be started at the given port. This is useful for local development and testing.
      """
    ],
    backup: [
      type: :string,
      doc: """
      Path to the backup file. If this option is provided, site_encrypt
      will backup the entire content of the `:db_folder` to the given path after every successful
      certification. When the system is being started, if the backup file exists while the
      `:db_folder` is empty, the system will perform a restore. The generated file will be a
      zipped tarball. If this option is not provided no backup will be generated.
      """
    ],
    days_to_renew: [
      type: :pos_integer,
      default: 30,
      doc: """
      A positive integer which determines the next renewal attempt. For example, if this value is
      30, the certificate will be renewed if it expires in 30 days or less.
      """
    ],
    log_level: [
      type: {:in, Logger.levels()},
      default: :info,
      doc: "Logger level for info messages."
    ],
    key_size: [
      type: :pos_integer,
      default: 4096,
      doc: "The size used for generating private keys."
    ],
    mode: [
      type: {:in, [:auto, :manual]},
      default: :auto,
      doc: """
      When set to `:auto`, the certificate will be automatically created or renewed when needed.

      When set to `:manual`, you need to start the certification manually, using functions such as
      `SiteEncrypt.force_certify/1` or `SiteEncrypt.dry_certify/2`. This can be useful for the
      first deploy, where you want to manually test the certification. In `:test` mix environment
      the mode is always `:manual`.
      """
    ]
  ]

  @doc """
  Invoke this macro from `certification/0` to return the fully shaped configuration.

  The minimal implementation of `certification/0` looks as follows:

      @impl SiteEncrypt
      def certification do
        SiteEncrypt.configure(
          client: :native,
          domains: ["mysite.com", "www.mysite.com"],
          emails: ["contact@abc.org", "another_contact@abc.org"],

          # By default the certs will be stored in tmp/site_encrypt_db, which is convenient for
          # local development. Make sure that tmp folder is gitignored.
          #
          # Set OS env var SITE_ENCRYPT_DB on staging/production hosts to some absolute path
          # outside of the deployment folder. Otherwise, the deploy may delete the db_folder,
          # which will effectively remove the generated key and certificate files.
          db_folder:
            System.get_env("SITE_ENCRYPT_DB", Path.join("tmp", "site_encrypt_db")),

          # set OS env var CERT_MODE to "staging" or "production" on staging/production hosts
          directory_url:
            case System.get_env("CERT_MODE", "local") do
              "local" -> {:internal, port: 4002}
              "staging" -> "https://acme-staging-v02.api.letsencrypt.org/directory"
              "production" -> "https://acme-v02.api.letsencrypt.org/directory"
            end
        )
      end

  ## Options

  #{NimbleOptions.docs(@certification_schema)}
  """
  defmacro configure(opts) do
    overrides = if Mix.env() == :test, do: %{mode: :manual}, else: %{}

    # adding a suffix in test env to avoid removal of dev certificates during tests
    db_folder_suffix = if Mix.env() == :test, do: "test", else: ""

    quote do
      defaults = %{id: __MODULE__, backup: nil}

      user_config =
        unquote(opts)
        |> NimbleOptions.validate!(unquote(Macro.escape(@certification_schema)))
        |> Map.new()
        |> Map.update!(:db_folder, &(&1 |> Path.join(unquote(db_folder_suffix)) |> Path.expand()))

      config =
        defaults
        |> Map.merge(user_config)
        |> Map.merge(%{callback: __MODULE__, periodic_offset: Certification.Periodic.offset()})
        |> Map.merge(unquote(Macro.escape(overrides)))
        |> Map.update!(:backup, &(&1 && Path.expand(&1)))

      if SiteEncrypt.local_ca?(config), do: %{config | key_size: 2048}, else: config
    end
  end

  @doc "Returns the paths to the certificates and the key for the given site."
  @spec https_keys(id) :: [keyfile: Path.t(), certfile: Path.t(), cacertfile: Path.t()]
  def https_keys(id) do
    config = SiteEncrypt.Registry.config(id)

    [
      keyfile: Path.join(cert_folder(config), "privkey.pem"),
      certfile: Path.join(cert_folder(config), "cert.pem"),
      cacertfile: Path.join(cert_folder(config), "chain.pem")
    ]
  end

  @doc """
  Unconditionally obtains the new certificate for the site.

  Be very careful when invoking this function in production, because you might trip some rate
  limit at the CA server (see [here](https://letsencrypt.org/docs/rate-limits/) for Let's
  Encrypt limits).
  """
  @spec force_certify(id) :: :ok | :error
  def force_certify(id), do: Certification.run_renew(SiteEncrypt.Registry.config(id))

  @doc """
  Generates a new throwaway certificate for the given site.

  This function will perform the full certification at the given CA server. The new certificate
  won't be used by the site, nor stored on disk. This is mostly useful to test the certification
  through the staging CA server from the production server, which can be done as follows:

      SiteEncrypt.dry_certify(
        MySystemWeb.Endpoint,
        directory_url: "https://acme-staging-v02.api.letsencrypt.org/directory"
      )

  If for some reasons you want to apply the certificate to the site, you can pass the returned
  pems to `set_certificate/2`.
  """
  @spec dry_certify(id, directory_url: String.t()) :: {:ok, pems} | :error
  def dry_certify(id, opts \\ []) do
    id
    |> SiteEncrypt.Registry.config()
    |> Map.update!(:directory_url, &Keyword.get(opts, :directory_url, &1))
    |> SiteEncrypt.Certification.Job.certify()
  end

  @doc """
  Sets the new site certificate.

  This operation doesn't persist the certificate in the client storage. As a result, if the client
  previously obtained and stored a valid certificate, that certificate will be used after the
  endpoint is restarted.
  """
  @spec set_certificate(id, pems) :: :ok
  def set_certificate(id, pems) do
    config = SiteEncrypt.Registry.config(id)
    store_pems(config, pems)
    :ssl.clear_pem_cache()

    unless is_nil(config.backup), do: SiteEncrypt.Certification.backup(config)
    config.callback.handle_new_cert()

    :ok
  end

  @doc false
  @spec log(config, iodata) :: :ok
  def log(config, chardata_or_fun), do: Logger.log(config.log_level, chardata_or_fun)

  @doc false
  @spec directory_url(config) :: String.t()
  def directory_url(config) do
    with {:internal, opts} <- config.directory_url,
         do: "https://localhost:#{Keyword.fetch!(opts, :port)}/directory"
  end

  @doc false
  @spec local_ca?(config) :: boolean
  def local_ca?(config), do: URI.parse(directory_url(config)).host == "localhost"

  @doc false
  def client(%{client: :native}), do: Certification.Native
  def client(%{client: :certbot}), do: Certification.Certbot

  @doc false
  def initialize_certs(config) do
    Certification.restore(config)
    unless is_nil(config.backup) or File.exists?(config.backup), do: Certification.backup(config)

    File.mkdir_p!(cert_folder(config))
    File.chmod!(config.db_folder, 0o700)

    case SiteEncrypt.client(config).pems(config) do
      {:ok, keys} -> store_pems(config, keys)
      :error -> unless certificates_exist?(config), do: generate_self_signed_certificate!(config)
    end
  end

  defp store_pems(config, keys) do
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
    |> SiteEncrypt.Acme.Server.Crypto.self_signed_chain()
    |> Stream.map(fn {type, pem} -> {file_name(type), pem} end)
    |> Enum.each(&save_pem!(config, &1))
  end

  defp file_name(:ca_cert), do: "chain.pem"
  defp file_name(:server_cert), do: "cert.pem"
  defp file_name(:server_key), do: "privkey.pem"

  defp save_pem!(config, {file_name, contents}),
    do: File.write!(Path.join(cert_folder(config), file_name), contents)

  defp cert_folder(config),
    do: Path.join([config.db_folder, "certs", hd(config.domains)])

  @doc false
  def validate_non_empty_string_list(list) do
    cond do
      not is_list(list) -> {:error, "expected a list"}
      Enum.empty?(list) -> {:error, "expected a non-empty list"}
      Enum.any?(list, &(not String.valid?(&1))) -> {:error, "expected a list of strings"}
      true -> {:ok, list}
    end
  end

  @doc false
  def validate_directory_url({:internal, opts} = internal) do
    port = Keyword.get(opts, :port)

    cond do
      is_nil(port) -> {:error, "missing port for the internal CA server"}
      not is_integer(port) -> {:error, "port for the internal CA server must be an integer"}
      port <= 0 -> {:error, "port for the internal CA server must be a positive integer"}
      true -> {:ok, internal}
    end
  end

  def validate_directory_url(string) do
    if String.valid?(string),
      do: {:ok, string},
      else: {:error, ":directory_url must be a string or an `:internal` tuple"}
  end

  @doc false
  def certificate_subjects_changed?(config) do
    with {:ok, pems} <- client(config).pems(config),
         {:ok, certified_domains} <- certified_domains(pems.cert),
         do: MapSet.new(config.domains) != MapSet.new(certified_domains),
         else: (:error -> false)
  end

  defp certified_domains(cert) do
    certificate = X509.Certificate.from_pem!(cert)

    case X509.Certificate.extension(certificate, :subject_alt_name) do
      {:Extension, _, _, dns_names} ->
        {:ok, Enum.map(dns_names, fn {_, dns_name} -> to_string(dns_name) end)}

      _ ->
        :error
    end
  end

  @doc """
  Refresh the configuration for a given endpoint.

  Use this if your endpoint is dynamically retrieving the list of domains from the database for example and you want to
  update the configuration in the registry. In most cases it makes sense to call `SiteEncrypt.force_certify/1` after
  the config has been refreshed.
  """
  def refresh_config(id) do
    SiteEncrypt.Adapter.refresh_config(id)
  end
end
