defmodule AcmeServer.JoseJasonAdapter do
  def encode(input), do: Jason.encode!(input)
  def decode(binary), do: Jason.decode!(binary)
end
