defmodule AcmeClient.Crypto do
  def new_private_key(size, opts \\ []), do: X509.PrivateKey.new_rsa(size, opts)

  def private_key_to_pem(private_key),
    do: private_key |> X509.PrivateKey.to_pem() |> normalize_pem()

  def csr(private_key, domains) do
    private_key
    |> X509.CSR.new(
      {:rdnSequence, []},
      extension_request: [X509.Certificate.Extension.subject_alt_name(domains)]
    )
    |> X509.CSR.to_der()
  end

  def normalize_pem(pem) do
    case String.trim(pem) do
      "" -> ""
      pem -> pem <> "\n"
    end
  end
end
