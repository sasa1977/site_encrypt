defmodule SiteEncrypt.Logger do
  require Logger
  @type level :: :debug | :info | :warn | :error
  @type chardata_or_fun :: [binary()] | fun()

  @spec log(:none, any()) :: :ok
  def log(:none, _), do: :ok

  @spec log(level, chardata_or_fun) :: :ok | {:error, any()}
  def log(level, chardata_or_fun), do: Logger.log(level, chardata_or_fun)
end
