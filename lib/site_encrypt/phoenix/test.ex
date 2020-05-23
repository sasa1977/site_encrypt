defmodule SiteEncrypt.Phoenix.Test do
  import ExUnit.Assertions
  alias SiteEncrypt.{Certifier, Registry}

  @spec verify_certification(SiteEncrypt.id()) :: :ok
  def verify_certification(id) do
    Registry.subscribe(id)
    config = Registry.config(id)

    # stop the site, remove cert folders, and restart the site
    root_pid = Registry.whereis(id, :root)
    Supervisor.terminate_child(root_pid, :site)

    Enum.each(~w/base_folder cert_folder backup/a, &File.rm_rf(Map.fetch!(config, &1)))
    Supervisor.restart_child(root_pid, :site)

    first_cert = await_first_cert(id)

    cert_valid_until = cert_valid_until(first_cert)

    no_renew_on = add_days(cert_valid_until, -(config.renew_before_expires_in_days + 1))
    assert Certifier.tick(id, no_renew_on) == {:error, :job_not_started}
    assert get_cert(id) == first_cert

    renew_on = add_days(cert_valid_until, -(config.renew_before_expires_in_days - 1))
    assert Certifier.tick(id, renew_on) == :ok
    assert get_cert(id) != first_cert
  end

  def await_first_cert(id) do
    assert_receive {:site_encrypt_notification, ^id, {:renew_started, pid}}, :timer.seconds(1)
    mref = Process.monitor(pid)
    assert_receive {:DOWN, ^mref, :process, ^pid, _reason}, :timer.seconds(10)
    get_cert(id)
  end

  defp add_days(datetime, days) do
    date =
      datetime
      |> DateTime.to_date()
      |> Date.add(days)

    Map.merge(datetime, Map.take(date, ~w/year month day/a))
  end

  def get_cert(id) do
    config = Registry.config(id)
    {:ok, socket} = :ssl.connect('localhost', https_port(config), [], :timer.seconds(5))
    {:ok, der_cert} = :ssl.peercert(socket)
    :ssl.close(socket)
    X509.Certificate.from_der!(der_cert)
  end

  defp cert_valid_until(cert) do
    {:Validity, _from, to} = X509.Certificate.validity(cert)
    X509.DateTime.to_datetime(to)
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
