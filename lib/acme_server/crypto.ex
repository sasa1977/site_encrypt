defmodule AcmeServer.Crypto do
  alias X509.{CSR, PrivateKey, PublicKey, Certificate}
  alias X509.Certificate.Extension

  @spec sign_csr!(binary(), AcmeServer.domains()) :: binary() | no_return()
  def sign_csr!(der, domains) do
    csr = CSR.from_der!(der)
    unless CSR.valid?(csr), do: raise("CSR validation failed")

    {ca_key, ca_cert} = ca_key_and_cert()

    csr
    |> CSR.public_key()
    |> server_cert(ca_key, ca_cert, domains)
    |> Certificate.to_pem()
  end

  def self_signed_chain(domains) do
    {ca_key, ca_cert} = ca_key_and_cert()

    server_key = PrivateKey.new_rsa(4096)

    server_cert =
      server_key
      |> PublicKey.derive()
      |> server_cert(ca_key, ca_cert, domains)

    %{
      ca_cert: Certificate.to_pem(ca_cert),
      server_cert: Certificate.to_pem(server_cert),
      server_key: PrivateKey.to_pem(server_key)
    }
  end

  defp ca_key_and_cert() do
    ca_key = PrivateKey.new_rsa(4096)
    ca_cert = Certificate.self_signed(ca_key, "/O=Site Encrypt/CN=Acme Server CA", template: :ca)
    {ca_key, ca_cert}
  end

  defp server_cert(public_key, ca_key, ca_cert, domains) do
    Certificate.new(
      public_key,
      "/O=Site Encrypt/CN=#{hd(domains)}",
      ca_cert,
      ca_key,
      validity: 1,
      extensions: [subject_alt_name: Extension.subject_alt_name(domains)]
    )
  end
end
