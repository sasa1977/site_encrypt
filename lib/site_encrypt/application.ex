defmodule SiteEncrypt.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        SiteEncrypt.Registry,
        AcmeServer.Registry,
        # TODO: move this to the client's supervision tree
        AcmeServer.Db
      ],
      strategy: :one_for_one,
      name: SiteEncrypt.Supervisor
    )
  end
end
