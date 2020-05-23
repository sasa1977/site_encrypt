for certifier <- [Native, Certbot],
    certifier != Certbot or System.get_env("CI") == "true" do
  defmodule Module.concat(SiteEncrypt, "#{certifier}Test") do
    use ExUnit.Case, async: false
    alias __MODULE__.TestEndpoint
    import SiteEncrypt.Phoenix.Test

    setup do
      config = TestEndpoint.certification()
      File.rm_rf(Keyword.fetch!(config, :base_folder))
      File.rm_rf(Keyword.fetch!(config, :cert_folder))
      File.rm_rf(Keyword.fetch!(config, :backup))
      :ok
    end

    test "certification" do
      start_site()
      verify_certification(TestEndpoint)
    end

    test "force_renew" do
      SiteEncrypt.Registry.subscribe(TestEndpoint)
      start_site()
      first_cert = await_first_cert(TestEndpoint)

      assert SiteEncrypt.Certifier.force_renew(TestEndpoint) == :finished
      assert get_cert(TestEndpoint) != first_cert
    end

    test "backup and restore" do
      SiteEncrypt.Registry.subscribe(TestEndpoint)
      start_site()
      config = SiteEncrypt.Registry.config(TestEndpoint)

      first_cert = await_first_cert(TestEndpoint)
      assert File.exists?(config.backup)

      # stop the site and remove all cert folders
      stop_supervised!(SiteEncrypt.Phoenix)

      File.rm_rf!(config.base_folder)
      File.rm_rf!(config.cert_folder)
      :ssl.clear_pem_cache()

      # restart the site
      SiteEncrypt.Registry.subscribe(TestEndpoint)
      start_site()

      # check that first certification didn't start
      refute_receive {:site_encrypt_notification, TestEndpoint, {:renew_started, _}}

      # make sure the cert is restored
      assert get_cert(TestEndpoint) == first_cert

      # make sure that renewal is still working correctly
      assert :finished = SiteEncrypt.Certifier.force_renew(TestEndpoint)
      refute get_cert(TestEndpoint) == first_cert
    end

    defp start_site do
      start_supervised!(
        {SiteEncrypt.Phoenix, TestEndpoint},
        restart: :permanent
      )
    end

    defmodule TestEndpoint do
      @moduledoc false

      use Phoenix.Endpoint, otp_app: :site_encrypt
      @behaviour SiteEncrypt

      plug SiteEncrypt.AcmeChallenge, __MODULE__

      @impl Phoenix.Endpoint
      def init(_key, config) do
        {:ok,
         Keyword.merge(config,
           url: [scheme: "https", host: "localhost", port: 4001],
           http: [port: 5002],
           https: [port: 4001] ++ SiteEncrypt.https_keys(__MODULE__),
           server: true
         )}
      end

      @impl SiteEncrypt
      def certification do
        [
          ca_url: local_acme_server(),
          domain: "localhost",
          extra_domains: ["foo.localhost"],
          email: "admin@foo.bar",
          base_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("certbot"),
          cert_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("cert"),
          mode: :manual,
          backup: Path.join(System.tmp_dir!(), "site_encrypt_backup.tgz"),
          certifier: unquote(Module.concat(SiteEncrypt, certifier))
        ]
      end

      @impl SiteEncrypt
      def handle_new_cert do
        :ok
      end

      defp local_acme_server, do: {:local_acme_server, port: 4003}
    end
  end
end
