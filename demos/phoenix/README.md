# PhoenixDemo

Minimum example of a Phoenix site powered by site_encrypt.

Start the site with `iex -S mix`, wait until the certification is done, and in another shell session invoke `curl -k https://localhost:4001`.
On restart, the generated certificate will be used. If you want to force the certificate regeneration, you can clean the project with `rm -rf tmp/site_encrypt_db` and start it again.

You can also run the certification test with `mix test`.
