defmodule SiteEncrypt.PebbleTest do
  use ExUnit.Case, async: true
  import SiteEncrypt.Phoenix.Test
  alias __MODULE__.TestEndpoint

  @moduletag :pebble

  setup_all do
    start_supervised!({SiteEncrypt.Phoenix, endpoint: TestEndpoint})
    :ok
  end

  test "certification" do
    clean_restart(TestEndpoint)
    cert = get_cert(TestEndpoint)
    assert cert.issuer =~ "Pebble"
  end

  test "renewal" do
    clean_restart(TestEndpoint)
    first_cert = get_cert(TestEndpoint)

    assert SiteEncrypt.force_certify(TestEndpoint) == :ok

    second_cert = get_cert(TestEndpoint)
    refute second_cert == first_cert
    assert second_cert.issuer =~ "Pebble"
  end

  defmodule TestEndpoint do
    @moduledoc false

    use Phoenix.Endpoint, otp_app: :site_encrypt
    use SiteEncrypt.Phoenix

    @impl Phoenix.Endpoint
    def init(_key, config) do
      {:ok,
       config
       |> SiteEncrypt.Phoenix.configure_https(port: 5001)
       |> Keyword.merge(
         url: [scheme: "https", host: "localhost", port: 5001],
         http: [port: 5002]
       )}
    end

    @impl SiteEncrypt
    def certification do
      SiteEncrypt.configure(
        directory_url: "https://localhost:14000/dir",
        domains: ["localhost"],
        emails: ["admin@foo.bar"],
        db_folder:
          Application.app_dir(
            :site_encrypt,
            Path.join(["priv", "site_encrypt_pebble"])
          ),
        backup: Path.join(System.tmp_dir!(), "site_encrypt_pebble_backup.tgz"),
        client: :native
      )
    end
  end
end
