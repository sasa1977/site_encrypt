defmodule SiteEncrypt.Phoenix.Test do
  @moduledoc """
  Helper for testing the certification.

  ## Usage

      defmodule MyEndpoint.CertificationTest do
        use ExUnit.Case, async: false
        import SiteEncrypt.Phoenix.Test

        test "certification" do
          clean_restart(MyEndpoint)
          cert = get_cert(MyEndpoint)
          assert cert.domains == ~w/mysite.com www.mysite.com/
        end
      end

  For this to work, you need to use the internal ACME server during tests.
  Refer to `SiteEncrypt.configure/1` for details.

  Also note that this test will restart the endpoint. In addition, it will configure Phoenix to
  serve the traffic. Therefore, make sure you pick a different set of ports in test, if you want
  to be able to run the tests while the system is started.

  Due to endpoint being restarted, the test case has to be marked as `async: false`.
  """

  require X509.ASN1

  @doc """
  Restarts the endpoint, removing all site_encrypt folders in the process.

  After the restart, the new certificate will be obtained.
  """
  @spec clean_restart(module) :: :ok
  def clean_restart(endpoint) do
    SiteEncrypt.Phoenix.restart_site(endpoint, fn ->
      ~w/db_folder backup/a
      |> Stream.map(&Map.fetch!(endpoint.certification(), &1))
      |> Stream.reject(&is_nil/1)
      |> Enum.each(&File.rm_rf/1)

      app = Mix.Project.config() |> Keyword.fetch!(:app)
      endpoint_config = Application.get_env(app, endpoint, [])
      Application.put_env(app, endpoint, Keyword.put(endpoint_config, :server, true))
      ExUnit.Callbacks.on_exit(fn -> Application.put_env(app, endpoint, endpoint_config) end)
    end)

    SiteEncrypt.force_renew(endpoint)
  end

  @doc """
  Obtains the certificate for the given endpoint.

  The certificate is obtained by establishing an SSL connection. Therefore, for this function to
  work, the endpoint has to be serving traffic. This will happen if you previously invoked
  `clean_restart/1`.
  """
  @spec get_cert(module) :: %{der: binary, issuer: String.t(), domains: [String.t()]}
  def get_cert(endpoint) do
    {:ok, socket} = :ssl.connect('localhost', https_port(endpoint), [], :timer.seconds(5))
    {:ok, der_cert} = :ssl.peercert(socket)
    :ssl.close(socket)
    cert = X509.Certificate.from_der!(der_cert)

    domains =
      cert
      |> X509.Certificate.extension(:subject_alt_name)
      |> X509.ASN1.extension(:extnValue)
      |> Keyword.values()
      |> Enum.map(&to_string/1)

    [issuer] = cert |> X509.Certificate.issuer() |> X509.RDNSequence.get_attr("commonName")

    %{der: der_cert, domains: domains, issuer: issuer}
  end

  defp https_port(endpoint), do: Keyword.fetch!(endpoint.config(:https), :port)
end
