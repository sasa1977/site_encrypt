defmodule AcmeServer.JoseJasonAdapter do
  @spec encode(term()) :: String.t() | no_return()
  def encode(input), do: Jason.encode!(input)

  @spec decode(iodata()) :: term() | no_return()
  def decode(binary), do: Jason.decode!(binary)
end
