for certifier <- [Native, Certbot],
    certifier != Certbot or System.get_env("CI") == "true" do
  defmodule Module.concat(SiteEncrypt, "#{certifier}Test") do
    use SiteEncrypt.Phoenix.Test, endpoint: __MODULE__.TestEndpoint
    alias __MODULE__.TestEndpoint
    import SiteEncrypt.Phoenix.Test

    setup_all do
      start_supervised!({SiteEncrypt.Phoenix, TestEndpoint})
      :ok
    end

    test "automatic renewal" do
      config = SiteEncrypt.Registry.config(TestEndpoint)
      first_cert = get_cert(TestEndpoint)
      cert_valid_until = cert_valid_until(first_cert)

      no_renew_on =
        midnight(add_days(cert_valid_until, -(config.renew_before_expires_in_days + 2)))

      assert SiteEncrypt.Certifier.tick(TestEndpoint, no_renew_on) == {:error, :job_not_started}
      assert get_cert(TestEndpoint) == first_cert

      renew_on = midnight(add_days(cert_valid_until, -(config.renew_before_expires_in_days - 2)))
      assert SiteEncrypt.Certifier.tick(TestEndpoint, renew_on) == :ok
      assert get_cert(TestEndpoint) != first_cert
    end

    test "force_renew" do
      first_cert = get_cert(TestEndpoint)
      assert SiteEncrypt.Certifier.force_renew(TestEndpoint) == :finished
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
      assert :finished = SiteEncrypt.Certifier.force_renew(TestEndpoint)
      refute get_cert(TestEndpoint) == first_cert
    end

    defp cert_valid_until(cert) do
      {:Validity, _from, to} = X509.Certificate.validity(cert)
      X509.DateTime.to_datetime(to)
    end

    defp add_days(datetime, days) do
      date =
        datetime
        |> DateTime.to_date()
        |> Date.add(days)

      Map.merge(datetime, Map.take(date, ~w/year month day/a))
    end

    defp midnight(datetime), do: %DateTime{datetime | hour: 0, minute: 0, second: 0}

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
          ca_url: local_acme_server(),
          domains: ["localhost", "foo.localhost"],
          emails: ["admin@foo.bar"],
          db_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("db"),
          backup: Path.join(System.tmp_dir!(), "site_encrypt_backup.tgz"),
          certifier: unquote(Module.concat(SiteEncrypt, certifier))
        )
      end

      defp local_acme_server, do: {:local_acme_server, port: 4003}
    end
  end
end
