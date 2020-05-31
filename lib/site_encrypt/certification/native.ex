defmodule SiteEncrypt.Certification.Native do
  @moduledoc false
  @behaviour SiteEncrypt.Certification.Job

  alias SiteEncrypt.Acme.Client
  alias SiteEncrypt.Certification.Job

  @impl Job
  def pems(config) do
    {:ok,
     Enum.map(
       ~w/privkey cert chain/a,
       &{&1, File.read!(Path.join(domain_folder(config), "#{&1}.pem"))}
     )}
  catch
    _, _ ->
      :error
  end

  @impl Job
  def certify(config, opts) do
    {:ok, http_pool} = Client.Http.start_link(Keyword.take(opts, [:verify_server_cert]))

    try do
      case account_key(config) do
        nil -> new_account(config, http_pool)
        account_key -> new_cert(config, http_pool, account_key)
      end
    after
      Client.Http.stop(http_pool)
    end
  end

  @impl Job
  def full_challenge(_config, _challenge), do: raise("unknown challenge")

  defp log(config, msg) do
    SiteEncrypt.log(config, "#{msg} (CA #{URI.parse(SiteEncrypt.directory_url(config)).host})")
  end

  defp new_account(config, http_pool) do
    log(config, "Creating new account")
    session = Client.new_account(http_pool, config.id, SiteEncrypt.directory_url(config))
    store_account_key!(config, session.account_key)
    create_certificate(config, session)
  end

  defp new_cert(config, http_pool, account_key) do
    directory_url = SiteEncrypt.directory_url(config)
    session = Client.for_existing_account(http_pool, directory_url, account_key)
    create_certificate(config, session)
  end

  defp create_certificate(config, session) do
    log(config, "Ordering a new certificate for domain #{hd(config.domains)}")
    {pems, _session} = Client.create_certificate(session, config.id)
    store_pems!(config, pems)
    log(config, "New certificate for domain #{hd(config.domains)} obtained")
  end

  defp account_key(config) do
    File.read!(Path.join(ca_folder(config), "account_key.json"))
    |> Jason.decode!()
    |> JOSE.JWK.from_map()
  catch
    _, _ -> nil
  end

  defp store_account_key!(config, account_key) do
    {_, map} = JOSE.JWK.to_map(account_key)
    store_file!(Path.join(ca_folder(config), "account_key.json"), Jason.encode!(map))
  end

  defp store_pems!(config, pems) do
    Enum.each(
      pems,
      fn {type, content} ->
        store_file!(Path.join(domain_folder(config), "#{type}.pem"), content)
      end
    )
  end

  defp store_file!(path, content) do
    File.mkdir_p(Path.dirname(path))
    File.write!(path, content)
    File.chmod!(path, 0o600)
  end

  defp domain_folder(config),
    do: Path.join([ca_folder(config), "domains", hd(config.domains)])

  defp ca_folder(config) do
    Path.join([
      config.db_folder,
      "native",
      "authorities",
      case URI.parse(SiteEncrypt.directory_url(config)) do
        %URI{host: host, port: 443} -> host
        %URI{host: host, port: port} -> "#{host}_#{port}"
      end
    ])
  end
end
