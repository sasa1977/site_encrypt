defmodule AcmeServer.JWS do
  @spec decode(iodata()) :: {:ok, map()} | :error
  def decode(body) do
    data = Jason.decode!(body)

    protected =
      data
      |> Map.fetch!("protected")
      |> Base.decode64!(padding: false)
      |> Jason.decode!()

    key = JOSE.JWK.from(Map.fetch!(protected, "jwk"))

    verification_data = %{
      "payload" => Map.fetch!(data, "payload"),
      "signatures" => [
        %{
          "protected" => Map.fetch!(data, "protected"),
          "signature" => Map.fetch!(data, "signature")
        }
      ]
    }

    case JOSE.JWS.verify([key], verification_data) do
      [{_jwk, [{true, payload, _jws}]}] ->
        {:ok, %{payload: Jason.decode!(payload), protected: protected}}

        error -> error
    end
  end
end
