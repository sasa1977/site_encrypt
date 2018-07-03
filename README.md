# SiteEncrypt

[![Build Status](https://travis-ci.org/sasa1977/site_encrypt.svg?branch=master)](https://travis-ci.org/sasa1977/site_encrypt)

This project aims to provide integrated certification via [Let's encrypt](https://letsencrypt.org/) for sites implemented in Elixir.

Integrated certification means that you don't need to run any other OS process in background. Start your site for the first time, and it will obtain the certificate, and restart the endpoint. The system will also periodically renew the certificate, and when the new certificate is obtained, the endpoint will again be restarted.

The target projects are small-to-medium Elixir based sites which don't sit behind reverse proxies such as nginx.

In addition, the library ships with a basic ACME v2 server to facilitate local development without needing to start a bunch of docker images.

## Status

Extreme alpha. It's highly unstable, unfinished, there's no documentation, no tests, and the API can change radically. Use at your own peril :-)

## Dependencies

- [Certbot](https://certbot.eff.org/) >= 0.22 (ACME client used to obtain certificate)

I have plans to replace Certbot with a native implementation in Elixir, but can't promise when will that happen, or if it will happen at all.


## Using with Phoenix

### Local development

A basic demo Phoenix project is available [here](https://github.com/sasa1977/site_encrypt/tree/master/phoenix_demo). The commit which adds the support for local development can be found [here](https://github.com/sasa1977/site_encrypt/commit/412d640b73e88a2fccea8af3aa87acb32001b4eb).

In a nutshell, you need to do the following things:

- Add the dependency
- Create the certbot callback module
- Add ACME challenge plug into the plug pipeline
- Adapt endpoint configuration
- Start your endpoint through SiteEncrypt

Let's break this one step at a time.

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

Next, you need to create the module which provides the certbot client configuration:

```elixir
defmodule PhoenixDemoWeb.Certbot do
  @behaviour SiteEncrypt

  def ssl_keys(), do: SiteEncrypt.Certbot.https_keys(config())

  def folder(), do: Application.app_dir(:phoenix_demo, "priv") |> Path.join("certbot")

  @impl SiteEncrypt
  def config() do
    %{
      run_client?: unquote(Mix.env() != :test),
      ca_url: local_acme_server(),
      domain: "foo.bar",
      extra_domains: ["www.foo.bar", "blog.foo.bar"],
      email: "admin@foo.bar",
      base_folder: folder(),
      renew_interval: :timer.hours(6),
      log_level: :info
    }
  end

  @impl SiteEncrypt
  def handle_new_cert(certbot_config) do
    # restarts the endpoint when the cert has been changed
    SiteEncrypt.Phoenix.restart_endpoint(certbot_config)

    # optionally backup the contents of the folder specified with folder/1
  end

  defp local_acme_server(), do: {:local_acme_server, %{adapter: Plug.Adapters.Cowboy, port: 4002}}
end
```

Then, add the ACME challenge plug in your endpoint. I recommend to add it immediately after the logger plug:

```elixir
defmodule PhoenixDemoWeb.Endpoint do
  # ...

  plug Plug.Logger

  plug SiteEncrypt.AcmeChallenge, PhoenixDemoWeb.Certbot.folder()

  # ...
end
```

In your endpoint you need to configure HTTPS if the cert is present:

```elixir
defmodule PhoenixDemoWeb.Endpoint do
  # ...

  def init(_key, config) do
    # add HTTPS config
    config = configure_https(config)

    # ...
  end

  defp configure_https(config) do
    case PhoenixDemoWeb.Certbot.ssl_keys() do
      {:ok, keys} -> Keyword.put(config, :https, [port: 4001] ++ keys)
      :error -> Keyword.put(config, :https, false)
    end
  end
end
```

And finally, you need to start the endpoint via `SiteEncrypt`:

```elixir
defmodule PhoenixDemo.Application do
  use Application

  def start(_type, _args) do
    children = [
      SiteEncrypt.Phoenix.child_spec({PhoenixDemoWeb.Certbot, PhoenixDemoWeb.Endpoint})
    ]

    opts = [strategy: :one_for_one, name: PhoenixDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ...
end
```

And that's it! At this point you can start the system:

```
$ iex -S mix phx.server

[info] Running local ACME server at port 4002
[info] Running PhoenixDemoWeb.Endpoint with Cowboy using http://0.0.0.0:4000
[info] Starting certbot
...
[info] Obtained new certificate, restarting endpoint
[info] Running PhoenixDemoWeb.Endpoint with Cowboy using http://0.0.0.0:4000
[info] Running PhoenixDemoWeb.Endpoint with Cowboy using https://0.0.0.0:4001
[info] Certbot finished
```

And visit your certified site at https://localhost:4001

The certificate issued by the integrated ACME server expires after one day. Therefore, if you restart the site, it will be renewed.

If something goes wrong, usually if you abruptly took down the system in the middle of the certification, the certbot might not work again. In this case, you can just delete the contents of the certbot folder (as defined in `PhoenixDemoWeb.Certbot.folder/1`).

Of course, in real production you want to backup this folder after every change, and restore it if something is corrupt.

### Production

To make it work in production, you need to own the domain and run your site there.

You need to change some parameters in `config/1` in the certbot module:

```elixir
def config() do
  %{
    ca_url: proper_url,
    domain: your_domain,
    extra_domains: other_domains,
    email: your_email,

    # other parameters can remain the same
  }
end
```

For `ca_url`, you can provide https://acme-staging-v02.api.letsencrypt.org/directory (staging) or https://acme-v02.api.letsencrypt.org/directory (production). Provide the complete URL.

I strongly advise to try it with the staging version first. If that works, then you can switch `ca_url` to production. Before you make that switch, you'll need to remove the certbot folder defined in `PhoenixDemoWeb.Certbot.folder/1`.

You can also consider trying with a locally running [boulder server](https://github.com/letsencrypt/boulder) first. Setting it up requires a couple of manual steps, but it was relatively straightforward. Ping me if you get stuck here.

Once you have your proper cert, make sure to backup the entire contents of the certbot folder. If you're moving to the new machine, you should probably restore the backup to the certbot folder.

Don't use a small `renew_interval`, because you might trip the [rate limit](https://letsencrypt.org/docs/rate-limits/).

It's up to you to decide how to vary the settings between local development and production. Personally, I use OS env vars, so I can run the `:prod` version which self-certifies on a local machine. The relevant code is available [here](https://github.com/sasa1977/erlangelist/blob/master/site/lib/erlangelist_web/site.ex).

## Warning

At the moment, I wouldn't advise using this for any critical production, because it's highly untested. I do use it myself to certify [my blog](https://www.theerlangelist.com/), but it's just been used for a few days, and so there are probably many uncovered issues.


## License

[MIT](./LICENSE)
