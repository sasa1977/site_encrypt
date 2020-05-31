for {client, index} <- Enum.with_index([:native, :certbot]),
    client != :certbot or System.get_env("CI") == "true" do
  defmodule Module.concat(SiteEncrypt, "#{Macro.camelize(to_string(client))}Test") do
    use ExUnit.Case, async: true
    use ExUnitProperties
    import SiteEncrypt.Phoenix.Test
    alias __MODULE__.TestEndpoint

    setup_all do
      start_supervised!({SiteEncrypt.Phoenix, TestEndpoint})
      :ok
    end

    setup do
      clean_restart(TestEndpoint)
    end

    test "certification" do
      assert get_cert(TestEndpoint).domains == ~w/localhost foo.localhost/
    end

    test "force_renew" do
      first_cert = get_cert(TestEndpoint)
      assert SiteEncrypt.force_renew(TestEndpoint) == :ok
      assert get_cert(TestEndpoint) != first_cert
    end

    test "new_cert" do
      first_cert = get_cert(TestEndpoint)
      assert {:ok, _pems} = SiteEncrypt.new_certificate(TestEndpoint)
      assert get_cert(TestEndpoint) == first_cert
    end

    test "backup and restore" do
      config = SiteEncrypt.Registry.config(TestEndpoint)
      first_cert = get_cert(TestEndpoint)
      assert File.exists?(config.backup)

      # remove db folder and restart the site
      SiteEncrypt.Phoenix.restart_site(TestEndpoint, fn ->
        File.rm_rf!(config.db_folder)
        :ssl.clear_pem_cache()
      end)

      # make sure the cert is restored
      assert get_cert(TestEndpoint) == first_cert

      # make sure that renewal is still working correctly
      assert SiteEncrypt.force_renew(TestEndpoint) == :ok
      refute get_cert(TestEndpoint) == first_cert
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
          domains: ["localhost", "foo.localhost"],
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
  end
end
