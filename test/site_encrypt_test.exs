defmodule SiteEncryptTest do
  use ExUnit.Case, async: true
  alias __MODULE__.TestEndpoint
  import SiteEncrypt.Phoenix.Test

  test "certification" do
    start_supervised!({SiteEncrypt.Phoenix, TestEndpoint}, restart: :permanent)

    verify_certification(TestEndpoint, [
      ~U[2020-01-01 00:00:00Z],
      ~U[2020-02-01 00:00:00Z]
    ])
  end

  test "force_renew" do
    start_supervised!({SiteEncrypt.Phoenix, TestEndpoint}, restart: :permanent)
    first_cert = get_cert(TestEndpoint)

    log =
      capture_log(fn ->
        assert SiteEncrypt.Certifier.force_renew(TestEndpoint) == :ok
        assert get_cert(TestEndpoint) != first_cert
      end)

    assert log =~ "Obtained new certificate for localhost"
  end

  test "backup and restore" do
    start_supervised!({SiteEncrypt.Phoenix, TestEndpoint}, restart: :permanent)
    config = SiteEncrypt.Registry.config(TestEndpoint)

    # force renew and verify that backup is made
    :ok = SiteEncrypt.Certifier.force_renew(TestEndpoint)
    assert File.exists?(config.backup)

    backed_up_cert = get_cert(TestEndpoint)

    # stop the site and remove all cert folders
    stop_supervised!(SiteEncrypt.Phoenix)

    File.rm_rf!(config.base_folder)
    File.rm_rf!(config.cert_folder)
    :ssl.clear_pem_cache()

    # restart the site
    log =
      capture_log(fn ->
        start_supervised!({SiteEncrypt.Phoenix, TestEndpoint}, restart: :permanent)
      end)

    assert log =~ "certificates for localhost restored"

    # make sure the cert is restored
    assert get_cert(TestEndpoint) == backed_up_cert

    # make sure that renewal is still working correctly
    assert :ok = SiteEncrypt.Certifier.force_renew(TestEndpoint)
    refute get_cert(TestEndpoint) == backed_up_cert

    # double check that the certifier ticks after the restore
    log =
      capture_log(fn ->
        assert SiteEncrypt.Certifier.tick(TestEndpoint, ~U[2020-01-01 00:00:00Z]) == :ok
      end)

    assert log =~ "The following certs are not due for renewal yet"
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
         http: [port: 4000],
         https: [port: 4001] ++ SiteEncrypt.https_keys(__MODULE__),
         server: true
       )}
    end

    @impl SiteEncrypt
    def certification do
      [
        ca_url: local_acme_server(),
        domain: "localhost",
        extra_domains: [],
        email: "admin@foo.bar",
        base_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("certbot"),
        cert_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("cert"),
        mode: :manual,
        backup: Path.join(System.tmp_dir!(), "site_encrypt_backup.tgz")
      ]
    end

    @impl SiteEncrypt
    def handle_new_cert do
      :ok
    end

    defp local_acme_server, do: {:local_acme_server, port: 4003}
  end
end
