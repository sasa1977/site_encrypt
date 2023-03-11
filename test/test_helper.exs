ex_unit_opts =
  try do
    %{status: 200} =
      SiteEncrypt.HttpClient.request(:get, "https://localhost:14000/dir",
        verify_server_cert: false
      )

    []
  catch
    _, _ ->
      Mix.shell().info("""
      To enable pebble tests, start the local container with the following command:

          docker run --rm -it -e "PEBBLE_VA_NOSLEEP=1" --net=host letsencrypt/pebble:v2.1.0 /usr/bin/pebble --strict
      """)

      [exclude: [:pebble]]
  end

ExUnit.start(ex_unit_opts)
Application.ensure_all_started(:ranch)
Application.ensure_all_started(:bandit)
Application.ensure_all_started(:phoenix)

# Custom test translator which drops the verify_none warning log.
Logger.add_translator({SiteEncrypt.Test.LoggerTranslator, :translate})

defmodule SiteEncrypt.Test.LoggerTranslator do
  def translate(_min_level, _level, _kind, message) do
    # This warning is emitted by the Erlang error logger. In local tests we're not validating
    # the peer, so we're dropping the warning.
    desc = 'Server authenticity is not verified since certificate path validation is not enabled'

    case message do
      {:logger, %{description: ^desc}} -> :skip
      _other -> :none
    end
  end
end
