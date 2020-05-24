defmodule SiteEncrypt.Acme.Server.JWS do
  @spec decode(iodata()) :: {:ok, map()} | :error
  def decode(body) do
    data = Jason.decode!(body)

    protected =
      data
      |> Map.fetch!("protected")
      |> Base.decode64!(padding: false)
      |> Jason.decode!()

    jwk =
      Map.get_lazy(protected, "jwk", fn ->
        "/account/" <> account_id =
          protected
          |> Map.fetch!("kid")
          |> URI.parse()
          |> Map.fetch!(:path)

        SiteEncrypt.Acme.Server.Account.client_key(account_id)
      end)

    key = JOSE.JWK.from(jwk)

    case JOSE.JWS.verify(key, data) do
      {true, payload, _jws} ->
        {:ok, %{payload: decode_payload(payload), protected: protected, jwk: jwk}}

      _ ->
        :error
    end
  end

  defp decode_payload(""), do: ""
  defp decode_payload(payload), do: Jason.decode!(payload)
end
