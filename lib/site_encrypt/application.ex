defmodule SiteEncrypt.Application do
  use Application

  def start(_type, _args) do
    :jose.json_module(AcmeServer.JoseJasonAdapter)

    Supervisor.start_link(
      [
        SiteEncrypt.Registry,
        AcmeServer.Registry
      ],
      strategy: :one_for_one,
      name: SiteEncrypt.Supervisor
    )
  end
end
