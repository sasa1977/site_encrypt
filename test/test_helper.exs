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

        docker run --rm -it -e "PEBBLE_VA_NOSLEEP=1" --net=host letsencrypt/pebble /usr/bin/pebble -strict
      """)

      [exclude: [:pebble]]
  end

ExUnit.start(ex_unit_opts)
Application.ensure_all_started(:ranch)
Application.ensure_all_started(:phoenix)
