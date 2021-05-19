for {client, index} <- Enum.with_index([:native, :certbot]),
    client != :certbot or System.get_env("CI") == "true" do
  defmodule Module.concat(SiteEncrypt, "#{Macro.camelize(to_string(client))}Test") do
    use ExUnit.Case, async: true
    use ExUnitProperties
    import SiteEncrypt.Phoenix.Test
    alias __MODULE__.{TestEndpoint, TestDomainProvider}

    setup_all do
      start_supervised!(TestDomainProvider)
      start_supervised!({SiteEncrypt.Phoenix, TestEndpoint})
      :ok
    end

    setup do
      clean_restart(TestEndpoint)
    end

    test "certification" do
      assert get_cert(TestEndpoint).domains == ~w/localhost foo.localhost/
    end

    test "force_certify" do
      first_cert = get_cert(TestEndpoint)
      assert SiteEncrypt.force_certify(TestEndpoint) == :ok
      assert get_cert(TestEndpoint) != first_cert
    end

    test "new_cert" do
      first_cert = get_cert(TestEndpoint)
      assert {:ok, _pems} = SiteEncrypt.dry_certify(TestEndpoint)
      assert get_cert(TestEndpoint) == first_cert
    end

    test "backup and restore" do
      config = SiteEncrypt.Registry.config(TestEndpoint)
      first_cert = get_cert(TestEndpoint)
      assert File.exists?(config.backup)

      # remove db folder and restart the site
      SiteEncrypt.Adapter.restart_site(TestEndpoint, fn ->
        File.rm_rf!(config.db_folder)
        :ssl.clear_pem_cache()
      end)

      # make sure the cert is restored
      assert get_cert(TestEndpoint) == first_cert

      # make sure that renewal is still working correctly
      assert SiteEncrypt.force_certify(TestEndpoint) == :ok
      refute get_cert(TestEndpoint) == first_cert
    end

    test "detect change in domains" do
      config = SiteEncrypt.Registry.config(TestEndpoint)
      updated_config = config |> update_in([:domains], fn domains -> domains ++ ["bar.localhost"] end)
      
      assert true == SiteEncrypt.certificate_subjects_changed?(updated_config)
    end

    test "change configuration" do
      config = SiteEncrypt.Registry.config(TestEndpoint)
      TestDomainProvider.set(config.domains ++ ["bar.localhost"])

      SiteEncrypt.Adapter.refresh_config(TestEndpoint)

      updated_config = SiteEncrypt.Registry.config(TestEndpoint)

      TestDomainProvider.set(config.domains)
      SiteEncrypt.Adapter.refresh_config(TestEndpoint)

      assert config != updated_config
    end

    defmodule TestEndpoint do
      @moduledoc false

      use Phoenix.Endpoint, otp_app: :site_encrypt
      use SiteEncrypt.Phoenix

      @base_port 4000 + 100 * index

      @impl Phoenix.Endpoint
      def init(_key, config) do
        {:ok,
         config
         |> SiteEncrypt.Phoenix.configure_https(port: @base_port + 1)
         |> Keyword.merge(
           url: [scheme: "https", host: "localhost", port: @base_port + 1],
           http: [port: @base_port]
         )}
      end

      @impl SiteEncrypt
      def certification do
        SiteEncrypt.configure(
          directory_url: {:internal, port: @base_port + 2},
          domains: TestDomainProvider.get(),
          emails: ["admin@foo.bar"],
          db_folder:
            Application.app_dir(
              :site_encrypt,
              Path.join(["priv", "site_encrypt_#{unquote(client)}"])
            ),
          backup: Path.join(System.tmp_dir!(), "site_encrypt_#{unquote(client)}_backup.tgz"),
          client: unquote(client)
        )
      end
    end

    defmodule TestDomainProvider do
      use GenServer

      def start_link(_args) do
        GenServer.start_link(__MODULE__, ["localhost", "foo.localhost"], name: __MODULE__)
      end

      def get() do
        GenServer.call(__MODULE__, :get)
      end

      def init(init_arg) do
        {:ok, init_arg}
      end

      def set(domains) do
        GenServer.call(__MODULE__, {:set, domains})
      end

      def handle_call(:get, _from, state) do
        {:reply, state, state}
      end

      def handle_call({:set, domains}, _from, _state) do
        {:reply, domains, domains}
      end
    end
  end
end
