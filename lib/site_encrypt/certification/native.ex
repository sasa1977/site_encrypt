defmodule SiteEncrypt.Certification.Native do
  @moduledoc false
  @behaviour SiteEncrypt.Certification.Job

  alias SiteEncrypt.Acme.Client
  alias SiteEncrypt.Certification.Job

  @impl Job
  def pems(config) do
    {:ok,
     Enum.into(
       ~w/privkey cert chain/a,
       %{},
       &{&1, File.read!(Path.join(domain_folder(config), "#{&1}.pem"))}
     )}
  catch
    _, _ ->
      :error
  end

  @impl Job
  def certify(config, opts) do
    case account_key(config) do
      nil -> new_account(config, opts)
      account_key -> new_cert(config, account_key, opts)
    end
  end

  @impl Job
  def full_challenge(_config, _challenge), do: {:error, :not_found}

  defp log(config, msg) do
    SiteEncrypt.log(config, "#{msg} (CA #{URI.parse(SiteEncrypt.directory_url(config)).host})")
  end

  defp session_opts(opts), do: Keyword.take(opts, ~w/verify_server_cert/a)

  defp new_account(config, opts) do
    log(config, "Creating new account")
    session = Client.new_account(config.id, session_opts(opts))
    store_account_key!(config, session.account_key)
    create_certificate(config, session)
  end

  defp new_cert(config, account_key, opts) do
    session = Client.for_existing_account(config.id, account_key, session_opts(opts))
    create_certificate(config, session)
  end

  defp create_certificate(config, session) do
    log(config, "Ordering a new certificate for domain(s) #{SiteEncrypt.domain_names(config)}")
    {pems, _session} = Client.create_certificate(session, config.id)
    store_pems!(config, pems)
    log(config, "New certificate for domain(s) #{SiteEncrypt.domain_names(config)} obtained")
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
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_string()
      |> String.replace(~r/[\- \:\.Z]/, "")

    Enum.each(
      pems,
      fn {type, content} ->
        store_file!(Path.join(domain_folder(config), "#{type}.pem"), content)

        store_file!(
          Path.join([domain_folder(config), "archive", timestamp, "#{type}.pem"]),
          content
        )
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
