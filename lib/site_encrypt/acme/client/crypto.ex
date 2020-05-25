defmodule SiteEncrypt.Acme.Client.Crypto do
  @moduledoc false

  @spec new_private_key(non_neg_integer) :: X509.PrivateKey.t()
  def new_private_key(size), do: X509.PrivateKey.new_rsa(size)

  @spec private_key_to_pem(X509.PrivateKey.t()) :: String.t()
  def private_key_to_pem(private_key),
    do: private_key |> X509.PrivateKey.to_pem() |> normalize_pem()

  @spec csr(X509.PrivateKey.t(), [String.t()]) :: binary
  def csr(private_key, domains) do
    private_key
    |> X509.CSR.new(
      {:rdnSequence, []},
      extension_request: [X509.Certificate.Extension.subject_alt_name(domains)]
    )
    |> X509.CSR.to_der()
  end

  @spec normalize_pem(String.t()) :: String.t()
  def normalize_pem(pem) do
    case String.trim(pem) do
      "" -> ""
      pem -> pem <> "\n"
    end
  end
end
