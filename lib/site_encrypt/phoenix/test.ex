defmodule SiteEncrypt.Phoenix.Test do
  import ExUnit.Assertions
  require X509.ASN1
  alias SiteEncrypt.Registry

  @spec verify_certification(SiteEncrypt.id()) :: :ok
  def verify_certification(id) do
    Registry.subscribe(id)
    config = Registry.config(id)

    # stop the site, remove cert folders, and restart the site
    root_pid = Registry.whereis(id, :root)
    Supervisor.terminate_child(root_pid, :site)

    Enum.each(~w/db_folder backup/a, &File.rm_rf(Map.fetch!(config, &1)))
    Supervisor.restart_child(root_pid, :site)

    cert = await_first_cert(id)

    domains =
      cert
      |> X509.Certificate.extension(:subject_alt_name)
      |> X509.ASN1.extension(:extnValue)
      |> Keyword.values()
      |> Enum.map(&to_string/1)

    assert domains == config.domains
  end

  def await_first_cert(id) do
    assert_receive {:site_encrypt_notification, ^id, {:renew_started, pid}}, :timer.seconds(1)
    mref = Process.monitor(pid)
    assert_receive {:DOWN, ^mref, :process, ^pid, _reason}, :timer.seconds(10)
    get_cert(id)
  end

  def get_cert(id) do
    {:ok, socket} = :ssl.connect('localhost', https_port(id), [], :timer.seconds(5))
    {:ok, der_cert} = :ssl.peercert(socket)
    :ssl.close(socket)
    X509.Certificate.from_der!(der_cert)
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

  defp https_port(endpoint), do: Keyword.fetch!(endpoint.config(:https), :port)
end
