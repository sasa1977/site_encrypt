defmodule SiteEncryptTest do
  use ExUnit.Case, async: true
  alias __MODULE__.TestEndpoint

  test "certification" do
    File.rm_rf(TestEndpoint.certification_config().base_folder)
    File.rm_rf(TestEndpoint.certification_config().cert_folder)

    start_supervised!({SiteEncrypt.Phoenix, {TestEndpoint, TestEndpoint}})

    # self-signed certificate
    first_cert = get_cert()

    # obtains the first certificate irrespective of the time
    log =
      capture_log(fn ->
        assert SiteEncrypt.Certifier.tick_at(TestEndpoint.Certifier, ~U[2020-01-01 01:02:03Z]) ==
                 :ok
      end)

    assert log =~ "Obtained new certificate for localhost"

    second_cert = get_cert()
    assert second_cert != first_cert

    # renews the certificate at midnight UTC
    log =
      capture_log(fn ->
        assert SiteEncrypt.Certifier.tick_at(TestEndpoint.Certifier, ~U[2020-01-01 00:00:00Z]) ==
                 :ok
      end)

    assert log =~ "Congratulations, all renewals succeeded."
    assert get_cert() not in [first_cert, second_cert]
  end

  defp capture_log(fun) do
    Logger.configure(level: :debug)
    ExUnit.CaptureLog.capture_log(fun)
  after
    Logger.configure(level: :warning)
  end

  defp get_cert do
    {:ok, socket} = :ssl.connect('localhost', 4001, [], :timer.seconds(5))
    {:ok, der_cert} = :ssl.peercert(socket)
    :ssl.close(socket)
    der_cert
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
         https: [port: 4001] ++ https_keys(),
         server: true
       )}
    end

    defp https_keys(), do: SiteEncrypt.https_keys(certification_config())

    @impl SiteEncrypt
    def certification_config() do
      %{
        ca_url: local_acme_server(),
        domain: "localhost",
        extra_domains: [],
        email: "admin@foo.bar",
        base_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("certbot"),
        cert_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("cert"),
        name: __MODULE__.Certifier,
        mode: :manual
      }
    end

    @impl SiteEncrypt
    def handle_new_cert do
      :ok
    end

    defp local_acme_server,
      do: {:local_acme_server, %{adapter: Plug.Adapters.Cowboy, port: 4003}}
  end
end
