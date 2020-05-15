defmodule SiteEncrypt.Phoenix.Test do
  import ExUnit.Assertions
  alias SiteEncrypt.{Certifier, Registry}

  @spec verify_certification(SiteEncrypt.id(), [DateTime.t()]) :: :ok
  def verify_certification(id, expected_times) do
    config = Registry.config(id)

    # stop the site, remove cert folders, and restart the site
    root_pid = Registry.whereis(id, :root)
    Supervisor.terminate_child(root_pid, :site)
    Enum.each(~w/base_folder cert_folder/a, &File.rm_rf(Map.fetch!(config, &1)))
    Supervisor.restart_child(root_pid, :site)

    # self-signed certificate
    first_cert = get_cert(id)

    # obtains the first certificate irrespective of the time
    log = capture_log(fn -> assert Certifier.tick(id, DateTime.utc_now()) == :ok end)

    assert log =~ "Obtained new certificate for localhost"

    second_cert = get_cert(id)
    assert second_cert != first_cert

    Enum.each(
      expected_times,
      fn time ->
        # attempts to renew the certificate at midnight UTC
        log = capture_log(fn -> assert Certifier.tick(id, time) == :ok end)

        assert log =~ "The following certs are not due for renewal yet"
        assert get_cert(id) == second_cert
      end
    )
  end

  def get_cert(id) do
    config = Registry.config(id)
    {:ok, socket} = :ssl.connect('localhost', https_port(config), [], :timer.seconds(5))
    {:ok, der_cert} = :ssl.peercert(socket)
    :ssl.close(socket)
    der_cert
  end

  def capture_log(fun) do
    level = Logger.level()

    try do
      Logger.configure(level: :debug)
      ExUnit.CaptureLog.capture_log(fun)
    after
      Logger.configure(level: level)
    end
  end

  defp https_port(config), do: config.assigns.endpoint.config(:https) |> Keyword.fetch!(:port)
end
