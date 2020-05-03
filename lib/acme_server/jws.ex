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

    case JOSE.JWS.verify(key, data) do
      {true, payload, _jws} -> {:ok, %{payload: Jason.decode!(payload), protected: protected}}
      _ -> :error
    end
  end
end
