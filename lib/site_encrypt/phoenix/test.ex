defmodule SiteEncrypt.Phoenix.Test do
  defmacro __using__(opts) do
    quote bind_quoted: [
            endpoint: Keyword.fetch!(opts, :endpoint),
            async: Keyword.get(opts, :async, false)
          ] do
      use ExUnit.Case, async: async

      setup do
        endpoint = unquote(endpoint)

        SiteEncrypt.Phoenix.restart_site(endpoint, fn ->
          ~w/db_folder backup/a
          |> Stream.map(&Map.fetch!(endpoint.certification(), &1))
          |> Stream.reject(&is_nil/1)
          |> Enum.each(&File.rm_rf/1)

          app = Mix.Project.config() |> Keyword.fetch!(:app)
          endpoint_config = Application.get_env(app, endpoint, [])
          Application.put_env(app, endpoint, Keyword.put(endpoint_config, :server, true))
          on_exit(fn -> Application.put_env(app, endpoint, endpoint_config) end)
        end)

        self_signed_cert = SiteEncrypt.Phoenix.Test.get_cert(endpoint)

        utc_now = DateTime.utc_now()
        midnight = %DateTime{utc_now | hour: 0, minute: 0, second: 0}
        assert SiteEncrypt.Certification.Periodic.tick(endpoint, midnight) == :ok
        new_cert = SiteEncrypt.Phoenix.Test.get_cert(endpoint)
        refute new_cert == self_signed_cert

        :ok
      end

      test "certification" do
        require X509.ASN1

        cert = SiteEncrypt.Phoenix.Test.get_cert(unquote(endpoint))

        domains =
          cert
          |> X509.Certificate.extension(:subject_alt_name)
          |> X509.ASN1.extension(:extnValue)
          |> Keyword.values()
          |> Enum.map(&to_string/1)

        assert domains == SiteEncrypt.Registry.config(unquote(endpoint)).domains
      end
    end
  end

  @spec get_cert(module) :: X509.Certificate.t()
  def get_cert(endpoint) do
    {:ok, socket} = :ssl.connect('localhost', https_port(endpoint), [], :timer.seconds(5))
    {:ok, der_cert} = :ssl.peercert(socket)
    :ssl.close(socket)
    X509.Certificate.from_der!(der_cert)
  end

  defp https_port(endpoint), do: Keyword.fetch!(endpoint.config(:https), :port)
end
