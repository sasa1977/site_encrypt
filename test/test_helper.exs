{:ok, http} = SiteEncrypt.Acme.Client.Http.start_link(verify_server_cert: false)

dir_status =
  SiteEncrypt.Acme.Client.Http.request(http, :get, "https://localhost:14000/dir", [], "")

ex_unit_opts =
  if match?({:ok, %{status: 200}}, dir_status) do
    []
  else
    Mix.shell().info("""
    To enable pebble tests, start the local container with the following command:

      docker run --rm -it -e "PEBBLE_VA_NOSLEEP=1" --net=host letsencrypt/pebble /usr/bin/pebble -strict
    """)

    [exclude: [:pebble]]
  end

ExUnit.start(ex_unit_opts)
Application.ensure_all_started(:ranch)
Application.ensure_all_started(:phoenix)
