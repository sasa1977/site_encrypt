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
        mode: :manual
      ]
    end

    @impl SiteEncrypt
    def handle_new_cert do
      :ok
    end

    defp local_acme_server, do: {:local_acme_server, port: 4003}
  end
end
