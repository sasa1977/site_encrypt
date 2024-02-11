inputs =
  for adapter <- [Phoenix.Endpoint.Cowboy2Adapter, Bandit.PhoenixAdapter],
      client <- [:native, :certbot],
      do: %{adapter: adapter, client: client}

for {input, index} <- Enum.with_index(inputs),
    input.client != :certbot or System.get_env("CI") == "true" do
  http_port = 40000 + 100 * index
  https_port = http_port + 1
  acme_server_port = http_port + 2

  defmodule Module.concat([
              SiteEncrypt,
              input.adapter,
              "#{Macro.camelize(to_string(input.client))}Test"
            ]) do
    # Tests are sync because "backup and restore" fails in an async setting.
    # TODO: investigate why and either fix it or extract that test into a sync case.
    use ExUnit.Case, async: false
    use ExUnitProperties
    import SiteEncrypt.Phoenix.Test
    alias __MODULE__.TestEndpoint

    server_adapter =
      case input.adapter do
        Phoenix.Endpoint.Cowboy2Adapter -> :cowboy
        Bandit.PhoenixAdapter -> :bandit
      end

    setup_all do
      start_supervised!({
        SiteEncrypt.Phoenix,
        endpoint: TestEndpoint,
        endpoint_opts: [
          adapter: unquote(input.adapter),
          http: [port: unquote(http_port)],
          https: [port: unquote(https_port)],
          url: [scheme: "https", host: "localhost", port: unquote(https_port)]
        ]
      })

      :ok
    end

    setup do
      TestEndpoint.clear_domains()
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

    # due to unsafe symlinks, restore doesn't work for certbot client on OTP 23+
    if input.client != :certbot do
      test "backup and restore" do
        config = SiteEncrypt.Registry.config(TestEndpoint)
        first_cert = get_cert(TestEndpoint)
        assert File.exists?(config.backup)

        # remove db folder and restart the site
        SiteEncrypt.Adapter.restart_site(TestEndpoint, fn ->
          :ssl.clear_pem_cache()
          File.rm_rf!(config.db_folder)
        end)

        # make sure the cert is restored
        assert get_cert(TestEndpoint) == first_cert

        # make sure that renewal is still working correctly
        assert SiteEncrypt.force_certify(TestEndpoint) == :ok
        refute get_cert(TestEndpoint) == first_cert
      end
    end

    test "change configuration" do
      first_cert = get_cert(TestEndpoint)

      TestEndpoint.set_domains(TestEndpoint.domains() ++ ["bar.localhost"])
      SiteEncrypt.Adapter.refresh_config(TestEndpoint)

      updated_config = SiteEncrypt.Registry.config(TestEndpoint)
      assert updated_config.domains == first_cert.domains ++ ["bar.localhost"]
      assert SiteEncrypt.certificate_subjects_changed?(updated_config)

      :ok = SiteEncrypt.force_certify(TestEndpoint)
      assert get_cert(TestEndpoint).domains == first_cert.domains ++ ["bar.localhost"]
    end

    defmodule TestEndpoint do
      @moduledoc false

      use Phoenix.Endpoint, otp_app: :site_encrypt
      use SiteEncrypt.Phoenix

      def domains, do: :persistent_term.get({__MODULE__, :domains}, ~w/localhost foo.localhost/)
      def set_domains(domains), do: :persistent_term.put({__MODULE__, :domains}, domains)
      def clear_domains, do: :persistent_term.erase({__MODULE__, :domains})

      @impl SiteEncrypt
      def certification do
        SiteEncrypt.configure(
          directory_url:
            {:internal, port: unquote(acme_server_port), adapter: unquote(server_adapter)},
          domains: domains(),
          emails: ["admin@foo.bar"],
          db_folder:
            Application.app_dir(
              :site_encrypt,
              Path.join([
                "priv",
                "site_encrypt_#{unquote(input.client)}_#{unquote(input.adapter)}"
              ])
            ),
          backup:
            Path.join(System.tmp_dir!(), "site_encrypt_#{unquote(input.client)}_backup.tgz"),
          client: unquote(input.client)
        )
      end
    end
  end
end
