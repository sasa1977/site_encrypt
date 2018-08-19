defmodule AcmeServer.Crypto do
  alias X509.{CSR, PrivateKey, PublicKey, Certificate}
  alias X509.Certificate.Extension

  @spec sign_csr!(binary(), AcmeServer.domains()) :: binary() | no_return()
  def sign_csr!(der, domains) do
    csr = X509.from_der(der, :CertificationRequest)
    unless CSR.valid?(csr), do: raise("CSR validation failed")

    ca_key = PrivateKey.new_rsa(4096)
    ca_cert = Certificate.self_signed(ca_key, "/O=Site Encrypt/CN=Acme Server CA", template: :ca)

    csr
    |> CSR.public_key()
    |> Certificate.new(
      "/O=Site Encrypt/CN=#{hd(domains)}",
      ca_cert,
      ca_key,
      validity: 1,
      extensions: [subject_alt_name: Extension.subject_alt_name(domains)]
    )
    |> X509.to_pem()
  end

  def self_signed_chain(domains) do
    ca_key = PrivateKey.new_rsa(4096)
    ca_cert = Certificate.self_signed(ca_key, "/O=Site Encrypt/CN=Acme Server CA", template: :ca)

    server_key = PrivateKey.new_rsa(4096)

    server_cert =
      server_key
      |> PublicKey.derive()
      |> Certificate.new(
        "/O=Site Encrypt/CN=#{hd(domains)}",
        ca_cert,
        ca_key,
        validity: 1,
        extensions: [
          subject_alt_name: Extension.subject_alt_name(domains)
        ]
      )

    %{ca_cert: ca_cert, server_cert: server_cert, server_key: server_key}
  end
end
