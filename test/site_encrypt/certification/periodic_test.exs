defmodule SiteEncrypt.Certification.PeriodicTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import SiteEncrypt.Phoenix.Test
  import StreamData
  import SiteEncrypt.Phoenix.Test

  alias __MODULE__.TestEndpoint
  alias SiteEncrypt.Certification.Periodic

  setup_all do
    start_supervised!(TestEndpoint)
    :ok
  end

  setup do
    clean_restart(TestEndpoint)
  end

  test "is scheduled for the desired date" do
    assert Date.diff(cert_valid_until(), renewal_date()) ==
             config().days_to_renew
  end

  test "happens on the given date at target times" do
    first_cert = get_cert(TestEndpoint)
    config = SiteEncrypt.Registry.config(TestEndpoint)
    hour = config.periodic_offset.hour

    Enum.reduce(
      [hour, hour + 8, hour + 16],
      first_cert,
      fn hour, previous_cert ->
        {:ok, time} =
          Time.new(
            hour,
            config.periodic_offset.minute,
            config.periodic_offset.second
          )

        {:ok, now} = NaiveDateTime.new(renewal_date(), time)
        now = DateTime.from_naive!(now, "Etc/UTC")
        assert Periodic.tick(TestEndpoint, now) == :ok
        new_cert = get_cert(TestEndpoint)
        assert new_cert != previous_cert
        new_cert
      end
    )
  end

  test "may happen after the given date" do
    first_cert = get_cert(TestEndpoint)
    date = Date.add(renewal_date(), 1)
    config = SiteEncrypt.Registry.config(TestEndpoint)

    {:ok, time} =
      Time.new(
        config.periodic_offset.hour,
        config.periodic_offset.minute,
        config.periodic_offset.second
      )

    {:ok, now} = NaiveDateTime.new(date, time)
    now = DateTime.from_naive!(now, "Etc/UTC")
    assert Periodic.tick(TestEndpoint, now) == :ok
    assert get_cert(TestEndpoint) != first_cert
  end

  test "doesn't happens before the given date" do
    first_cert = get_cert(TestEndpoint)
    date = Date.add(renewal_date(), -1)

    {:ok, time} = Time.new(0, 0, 0)
    {:ok, now} = NaiveDateTime.new(date, time)
    now = DateTime.from_naive!(now, "Etc/UTC")
    assert Periodic.tick(TestEndpoint, now) == {:error, :job_not_started}
    assert get_cert(TestEndpoint) == first_cert
  end

  property "doesn't happen outside of target times" do
    check all hour <- integer(0..23),
              minute <- integer(0..59),
              second <- integer(0..59),
              rem(hour, 8) != 0 or minute != 0 or second != 0 do
      {:ok, time} = Time.new(hour, minute, second)
      {:ok, now} = NaiveDateTime.new(renewal_date(), time)
      now = DateTime.from_naive!(now, "Etc/UTC")
      assert Periodic.tick(TestEndpoint, now) == {:error, :job_not_started}
    end
  end

  defp cert_valid_until, do: Periodic.cert_valid_until(config())
  defp renewal_date, do: Periodic.renewal_date(config())
  defp config, do: TestEndpoint.certification()

  defmodule TestEndpoint do
    @moduledoc false

    use SiteEncrypt.Phoenix.Endpoint,
      otp_app: :site_encrypt,
      endpoint_opts: [
        http: [port: 4200],
        https: [port: 4201],
        url: [scheme: "https", host: "localhost", port: 4201]
      ]

    @impl SiteEncrypt
    def certification do
      SiteEncrypt.configure(
        directory_url: internal(),
        domains: ["localhost", "foo.localhost"],
        emails: ["admin@foo.bar"],
        db_folder: Application.app_dir(:site_encrypt, "priv") |> Path.join("periodic_test"),
        backup: Path.join(System.tmp_dir!(), "periodic_site_encrypt_backup.tgz"),
        client: :native
      )
    end

    defp internal, do: {:internal, port: 4202}
  end
end
