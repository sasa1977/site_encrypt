defmodule SiteEncrypt.Acme.Server.Standalone do
  @moduledoc false

  def child_spec(opts) do
    port = Keyword.fetch!(opts, :port)

    config =
      SiteEncrypt.Acme.Server.config(
        site: "https://localhost:#{port}",
        dns: Keyword.fetch!(opts, :dns)
      )

    key = X509.PrivateKey.new_rsa(1024)
    cert = X509.Certificate.self_signed(key, "/C=US/ST=CA/O=Acme/CN=ECDSA Root CA")

    adapter_opts = [
      plug: {SiteEncrypt.Acme.Server.Plug, config},
      scheme: :https,
      key: {:PrivateKeyInfo, X509.PrivateKey.to_der(key, wrap: true)},
      cert: X509.Certificate.to_der(cert),
      transport_options: [num_acceptors: 1],
      ref: :"#{__MODULE__}_#{port}",
      options: [port: port]
    ]

    SiteEncrypt.Acme.Server.child_spec(
      config: config,
      endpoint: Plug.Cowboy.child_spec(adapter_opts)
    )
  end
end
