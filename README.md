# SiteEncrypt

[![Build Status](https://travis-ci.org/sasa1977/site_encrypt.svg?branch=master)](https://travis-ci.org/sasa1977/site_encrypt)

This project aims to provide integrated certification via [Let's encrypt](https://letsencrypt.org/) for sites implemented in Elixir.

Integrated certification means that you don't need to run any other OS process in background. Start your site for the first time, and it will obtain the certificate, and restart the endpoint. The system will also periodically renew the certificate, and when the new certificate is obtained, the endpoint will again be restarted.

The target projects are small-to-medium Elixir based sites which don't sit behind reverse proxies such as nginx.

In addition, the library ships with a basic ACME v2 server to facilitate local development without needing to start a bunch of docker images.

## Status

- The library is tested in a [simple production](https://www.theerlangelist.com), where it has been constantly running since mid 2018.
- The API is not stable. Expect breaking changes in the future.
- The documentation is non-existant.
- The tests are basic.

Use at your own peril :-)

## Dependencies

- [Certbot](https://certbot.eff.org/) >= 0.31 (ACME client used to obtain certificate)

## Using with Phoenix

### Local development

A basic demo Phoenix project is available [here](./demos/phoenix).

First, you need to add the dependency to `mix.exs`:

```elixir
defmodule PhoenixDemo.Mixfile do
  # ...

  defp deps do
    [
      # ...
      {:site_encrypt, github: "sasa1977/site_encrypt"}
    ]
  end
end
```

Don't forget to invoke `mix.deps` after that.

Next, extend your endpoint to implement `SiteEncrypt` behaviour:

```elixir
defmodule PhoenixDemo.Endpoint do
  # ...

  @behaviour SiteEncrypt

  # ...

  @impl SiteEncrypt
  def certification do
    [
      base_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("certbot"),
      cert_folder: Application.app_dir(:phoenix_demo, "priv") |> Path.join("cert"),
      ca_url: {:local_acme_server, port: 4002},
      domain: "localhost",
      email: "admin@foo.bar"
      mode: unquote(if Mix.env() == :test, do: :manual, else: :auto)
    ]
  end

  @impl SiteEncrypt
  def handle_new_cert do
    # Invoked after certificate has been obtained. Consider backing up the content of your base_folder here.
    :ok
  end

  # ...
end
```

Include `plug SiteEncrypt.AcmeChallenge, __MODULE__` in your endpoint. If you have `plug Plug.SSL` specified, it has to be provided after `SiteEncrypt.AcmeChallenge`.

Configure https:

```
defmodule PhoenixDemo.Endpoint do
  # ...

  @impl Phoenix.Endpoint
  def init(_key, config) do
    {:ok, Keyword.merge(config, https: [port: 4001] ++ SiteEncrypt.https_keys(__MODULE__))}
  end

  # ...
end
```

Finally, you need to start the endpoint via `SiteEncrypt`:

```elixir
defmodule PhoenixDemo.Application do
  use Application

  def start(_type, _args) do
    children = [{SiteEncrypt.Phoenix, PhoenixDemo.Endpoint}]
    opts = [strategy: :one_for_one, name: PhoenixDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ...
end
```

And that's it! At this point you can start the system:

```
$ iex -S mix phx.server

22:10:13.938 [info]  Generating a temporary self-signed certificate. This certificate will be used until a proper certificate is issued by the CA server.
22:10:14.321 [info]  Running local ACME server at port 4002
22:10:14.356 [info]  Running PhoenixDemo.Endpoint with cowboy 2.7.0 at 0.0.0.0:4000 (http)
22:10:14.380 [info]  Running PhoenixDemo.Endpoint with cowboy 2.7.0 at 0.0.0.0:4001 (https)

# wait for about 10 seconds

# ...
22:10:20.568 [info]  Obtained new certificate for localhost
```

And visit your certified site at https://localhost:4001

The certificate issued by the integrated ACME server expires after 1000 years. Therefore, if you restart the site, the certificate won't be renewed.

If something goes wrong, usually if you abruptly took down the system in the middle of the certification, the certbot might not work again. In this case, you can just delete the contents of the certbot folder.

Of course, in real production you want to backup this folder after every change, and restore it if something is corrupt.

#### Testing

It's possible to add an automated test of the certification:

```elixir
defmodule PhoenixDemo.EndpointTest do
  use ExUnit.Case, async: false

  test "certification" do
    # This will verify the first certification, as well as renewals.
    SiteEncrypt.Phoenix.Test.verify_certification(PhoenixDemo.Endpoint, [
      ~U[2020-01-01 00:00:00Z],
      ~U[2020-02-01 00:00:00Z]
    ])
  end
end

```

### Production

To make it work in production, you need to own the domain and run your site there.

You need to change some parameters in `certification/1` callback.

```elixir
def certification() do
  [
    ca_url: "https://acme-v02.api.letsencrypt.org/directory",
    domain: "<DOMAIN NAME>",
    email: "<ADMIN EMAIL>"
    # other parameters can remain the same
  ]
end
```

For staging, you can use https://acme-staging-v02.api.letsencrypt.org/directory. Make sure to change the domain name as well.

In both cases (staging and production certification), the site must be publicly reachable at `http://<DOMAIN NAME>`.

Once you have your production cert, make sure to backup the entire contents of the certbot folder. If you're moving to the new machine, you should restore the backup to the certbot folder (see below).

It's up to you to decide how to vary the settings between local development and production.

## Restoring a backup

Restore previous cert and certbot directories. In the certbot directory, there should be symlinks in the subdirectory `certbot/config/live/MY_DOMAIN/`. There should be 4 symlinks to 4 files (cert.pem, fullchain.pem, privkey.pem and chain.pem). If the symlinks are preserved you have nothing more to do. If they are not.

- go check into `certbot/config/archive/MY_DOMAIN/`
- you should see some files, at least cert1.pem fullchain1.pem, privkey1.pem and chain1.pem. They correspond to the initially issued certificate. If your certificate has been renewed, you will find also cert2.pem, fulllchain2.pem... You'll have to make the symlink between the latest of these files and the live directory. So go to `certbot/config/live/`
- type the following (if your certificate has been renewed, replace the 1 with the latest number you have)

```Shell
rm cert.pem chain.pem fullchain.pem privkey.pem
ln -s ../../archive/MY_DOMAIN/cert1.pem cert.pem
ln -s ../../archive/MY_DOMAIN/chain1.pem chain.pem
ln -s ../../archive/MY_DOMAIN/fullchain1.pem fullchain.pem
ln -s ../../archive/MY_DOMAIN/privkey1.pem privkey.pem
```

and you're good to go!

## License

[MIT](./LICENSE)
