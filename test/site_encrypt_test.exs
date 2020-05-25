for client <- [:native, :certbot],
    client != :certbot or System.get_env("CI") == "true" do
  defmodule Module.concat(SiteEncrypt, "#{Macro.camelize(to_string(client))}Test") do
    use SiteEncrypt.Phoenix.Test, endpoint: __MODULE__.TestEndpoint
    use ExUnitProperties
    import SiteEncrypt.Phoenix.Test
    alias __MODULE__.TestEndpoint

    setup_all do
      start_supervised!({SiteEncrypt.Phoenix, TestEndpoint})
      :ok
    end

    test "force_renew" do
      first_cert = get_cert(TestEndpoint)
      assert SiteEncrypt.force_renew(TestEndpoint) == :ok
      assert get_cert(TestEndpoint) != first_cert
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

      @impl Phoenix.Endpoint
      def init(_key, config) do
        {:ok,
         config
         |> SiteEncrypt.Phoenix.configure_https(port: 4001)
         |> Keyword.merge(
           url: [scheme: "https", host: "localhost", port: 4001],
           http: [port: 4000]
         )}
      end

      @impl SiteEncrypt
      def certification do
        SiteEncrypt.configure(
          directory_url: internal(),
          domains: ["localhost", "foo.localhost"],
          emails: ["admin@foo.bar"],
          db_folder:
            Application.app_dir(
              :site_encrypt,
              Path.join(["priv", "site_encrypt_#{unquote(client)}"])
            ),
          backup: Path.join(System.tmp_dir!(), "site_encrypt_backup.tgz"),
          client: unquote(client)
        )
      end

      defp internal, do: {:internal, port: 4003}
    end
  end
end
