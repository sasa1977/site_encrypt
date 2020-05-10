# PhoenixDemo

Minimum example of a Phoenix site powered by site_encrypt. [Certbot](https://certbot.eff.org/) >= 0.31 must be installed and in path.

Start the site with `iex -S mix`, wait until the certification is done, and in another shell session invoke `curl -k https://localhost:4001`.
On restart, the generated certificate will be used. The system will attempt to renew its certificate exactly at midnight UTC. If you want to force the certificate regeneration, you can clean the project with `mix clean` and start it again.
