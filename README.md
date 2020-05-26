# SiteEncrypt

[![hex.pm](https://img.shields.io/hexpm/v/parent.svg?style=flat-square)](https://hex.pm/packages/site_encrypt)
[![hexdocs.pm](https://img.shields.io/badge/docs-latest-green.svg?style=flat-square)](https://hexdocs.pm/site_encrypt/)
![Build Status](https://github.com/sasa1977/site_encrypt/workflows/site_encrypt/badge.svg)

This project aims to provide integrated certification via [Let's encrypt](https://letsencrypt.org/) for sites implemented in Elixir.

Integrated certification means that you don't need to run any other OS process in background. Start your site for the first time, and the system will obtain the certificate, and periodically renew it before it expires.

The target projects are small-to-medium Elixir based sites which don't sit behind reverse proxies such as nginx.

## Status

- The library is tested in a [simple production](https://www.theerlangelist.com), where it has been constantly running since mid 2018.
- Native Elixir client is very new, and not considered stable. If you prefer reliable behaviour, use the Certbot client. This will require installing [Certbot](https://certbot.eff.org/) >= 0.31
- The API is not stable. Expect breaking changes in the future.

## Quick start

A basic demo Phoenix project is available [here](https://github.com/sasa1977/site_encrypt/tree/master/demos/phoenix).

1. Add the dependency to `mix.exs`:

    ```elixir
    defmodule PhoenixDemo.Mixfile do
      # ...

      defp deps do
        [
          # ...
          {:site_encrypt, "~> 0.1.0"}
        ]
      end
    end
    ```

    Don't forget to invoke `mix.deps` after that.

1. Expand your endpoint

    ```elixir
    defmodule PhoenixDemo.Endpoint do
      # ...

      # add this after `use Phoenix.Endpoint`
      use SiteEncrypt.Phoenix

      # ...

      @impl SiteEncrypt
      def certification do
        SiteEncrypt.configure(
          # Note that native client is very immature. If you want a more stable behaviour, you can
          # provide `:certbot` instead. Note that in this case certbot needs to be installed on the
          # host machine.
          client: :native,

          domains: ["mysite.com", "www.mysite.com"],
          emails: ["contact@abc.org", "another_contact@abc.org"],

          db_folder: Application.app_dir(:phoenix_demo, Path.join(~w/priv site_encrypt/)),

          # set OS env var MODE to "staging" or "production" on staging/production hosts
          directory_url:
            case System.get_env("MODE", "local") do
              "local" -> {:internal, port: 4002}
              "staging" -> "https://acme-staging-v02.api.letsencrypt.org/directory"
              "production" -> "https://acme-v02.api.letsencrypt.org/directory"
            end
        )
      end

      # ...
    end
    ```

1. Configure https:

    ```elixir
    defmodule PhoenixDemo.Endpoint do
      # ...

      @impl Phoenix.Endpoint
      def init(_key, config) do
        # this will merge key, cert, and chain into `:https` configuration from config.exs
        {:ok, SiteEncrypt.Phoenix.configure_https(config)}

        # to completely configure https from `init/2`, invoke:
        #   SiteEncrypt.Phoenix.configure_https(config, port: 4001, ...)
      end

      # ...
    end
    ```

1. Start the endpoint via `SiteEncrypt`:

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

```text
$ iex -S mix phx.server

[info]  Generating a temporary self-signed certificate. This certificate will be used until a proper certificate is issued by the CA server.
[info]  Running PhoenixDemo.Endpoint with cowboy 2.7.0 at 0.0.0.0:4000 (http)
[info]  Running PhoenixDemo.Endpoint with cowboy 2.7.0 at 0.0.0.0:4001 (https)
[info]  Running local ACME server at port 4002
[info]  Ordering a new certificate for domain mysite.com
[info]  New certificate for domain mysite.com obtained
[info]  Certificate successfully obtained! It is valid until 3019-09-27. Next renewal is scheduled for 3019-08-28.
```

And visit your certified site at https://localhost:4001

## License

[MIT](./LICENSE)
