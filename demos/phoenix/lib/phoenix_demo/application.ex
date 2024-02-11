defmodule PhoenixDemo.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {
          SiteEncrypt.Phoenix,
          endpoint: PhoenixDemo.Endpoint,
          endpoint_opts: [
            http: [port: 4000],
            https: [port: 4001],
            url: [scheme: "https", host: "localhost", port: 4001]
          ]
        }
      ],
      strategy: :one_for_one,
      name: __MODULE__
    )
  end
end
