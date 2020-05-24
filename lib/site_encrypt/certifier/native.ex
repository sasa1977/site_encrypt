defmodule SiteEncrypt.Certifier.Native do
  @behaviour SiteEncrypt.Certifier.Job
  require Logger

  alias SiteEncrypt.Certifier.Job

  @impl Job
  def pems(config) do
    {:ok, Enum.map(~w/privkey cert chain/a, &{&1, load_file!(config, "#{&1}.pem")})}
  catch
    _, _ ->
      :error
  end

  @impl Job
  def certify(config, http_pool, _opts) do
    case account_key(config) do
      nil -> new_account(config, http_pool)
      account_key -> new_cert(config, http_pool, account_key)
    end
  end

  @impl Job
  def full_challenge(_config, _challenge), do: raise("shouldn't land here")

  defp internal_ca?(config), do: match?({:internal, _}, config.directory_url)

  defp new_account(config, http_pool) do
    SiteEncrypt.log(config, "Creating new ACME account for domain #{hd(config.domains)}")
    directory_url = directory_url(config)

    session =
      SiteEncrypt.Acme.Client.new_account(
        http_pool,
        directory_url,
        [config.emails],
        key_length: if(internal_ca?(config), do: 1024, else: 2048)
      )

    store_account_key!(config, session.account_key)
    create_certificate(config, session)
  end

  defp new_cert(config, http_pool, account_key) do
    directory_url = directory_url(config)
    session = SiteEncrypt.Acme.Client.for_existing_account(http_pool, directory_url, account_key)
    create_certificate(config, session)
  end

  defp create_certificate(config, session) do
    id = config.id
    SiteEncrypt.log(config, "Ordering a new certificate for domain #{hd(config.domains)}")

    {pems, _session} =
      SiteEncrypt.Acme.Client.create_certificate(session, %{
        id: config.id,
        domains: config.domains,
        poll_delay: if(internal_ca?(config), do: 50, else: :timer.seconds(2)),
        key_length: if(internal_ca?(config), do: 1024, else: 2048),
        register_challenge: &SiteEncrypt.Registry.register_challenge!(id, &1, &2),
        await_challenge: fn ->
          receive do
            {:got_challenge, ^id} -> true
          after
            :timer.minutes(1) -> false
          end
        end
      })

    store_pems!(config, pems)
    SiteEncrypt.log(config, "New certificate for domain #{hd(config.domains)} obtained")
    :new_cert
  end

  defp account_key(config) do
    config
    |> load_file!("account_key.json")
    |> Jason.decode!()
    |> JOSE.JWK.from_map()
  catch
    _, _ -> nil
  end

  defp store_account_key!(config, account_key) do
    {_, map} = JOSE.JWK.to_map(account_key)
    store_file!(config, "account_key.json", Jason.encode!(map))
  end

  defp store_pems!(config, pems) do
    Enum.each(
      pems,
      fn {type, content} -> store_file!(config, "#{type}.pem", content) end
    )
  end

  defp store_file!(config, name, content) do
    File.mkdir_p(root_folder(config))
    File.write!(Path.join(root_folder(config), name), content)
  end

  defp load_file!(config, name),
    do: File.read!(Path.join(root_folder(config), name))

  defp root_folder(config) do
    Path.join([
      config.db_folder,
      "elixir_acme_client",
      ca_folder(config),
      hd(config.domains)
    ])
  end

  defp ca_folder(config), do: URI.parse(directory_url(config)).host

  defp directory_url(config) do
    with {:internal, opts} <- config.directory_url,
         do: "https://localhost:#{Keyword.fetch!(opts, :port)}/directory"
  end
end
