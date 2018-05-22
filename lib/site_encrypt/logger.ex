defmodule SiteEncrypt.Logger do
  require Logger

  def log(:none, _), do: :ok
  def log(level, chardata_or_fun), do: Logger.log(level, chardata_or_fun)
end
