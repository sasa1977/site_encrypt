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

  @type pems :: [privkey: String.t(), cert: String.t(), chain: String.t()]

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
      type: {:one_of, [:native, :certbot]},
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
      type: {:one_of, [:debug, :info, :warn, :error]},
      default: :info,
      doc: "Logger level for info messages."
    ],
    key_size: [
      type: :pos_integer,
      default: 4096,
      doc: "The size used for generating private keys."
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
          db_folder: Application.app_dir(:phoenix_demo, Path.join(~w/priv site_encrypt/))

          # set OS env var MODE to "staging" or "production" on staging/production hosts
          directory_url:
            case System.get_env("MODE", "local") do
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
    mode = if Mix.env() == :test, do: :manual, else: :auto

    # adding a suffix in test env to avoid removal of dev certificates during tests
    db_folder_suffix = if Mix.env() == :test, do: "test", else: ""

    quote do
      config =
        unquote(opts)
        |> NimbleOptions.validate!(unquote(Macro.escape(@certification_schema)))
        |> Map.new()
        |> Map.update!(:db_folder, &Path.join(&1, unquote(db_folder_suffix)))
        |> Map.put_new(:backup, nil)
        |> Map.put_new(:id, __MODULE__)
        |> Map.merge(%{mode: unquote(mode), callback: __MODULE__})
        |> Map.put(:periodic_offset, Certification.Periodic.offset())

      if SiteEncrypt.local_ca?(config), do: %{config | key_size: 1024}, else: config
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
  Force renews the certificate for the given site.

  Be very careful when invoking this function in production, because you might trip some rate
  limit at the CA server (see [here](https://letsencrypt.org/docs/rate-limits/) for Let's
  Encrypt limits).
  """
  @spec force_renew(id) :: :ok
  def force_renew(id), do: Certification.run_renew(SiteEncrypt.Registry.config(id))

  @doc """
  Generates a new certificate for the given site without applying it.

  You can optionally provide a different directory_url. This can be useful to test certification
  through another CA or through Let's Encrypt staging site.
  """
  @spec new_certificate(id, directory_url: String.t()) :: {:ok, pems} | :error
  def new_certificate(id, opts \\ []) do
    id
    |> SiteEncrypt.Registry.config()
    |> Map.update!(:directory_url, &Keyword.get(opts, :directory_url, &1))
    |> SiteEncrypt.Certification.Job.certify()
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
      is_nil(port) -> "missing port for the internal CA server"
      not is_integer(port) -> "port for the internal CA server must be an integer"
      port <= 0 -> "port for the internal CA server must be a positive integer"
      true -> {:ok, internal}
    end
  end

  def validate_directory_url(string) do
    if String.valid?(string),
      do: {:ok, string},
      else: {:error, ":directory_url must be a string or an `:internal` tuple"}
  end
end
