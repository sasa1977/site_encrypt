defmodule AcmeServer.Jobs do
  def start_link() do
    Supervisor.start_link(
      [
        AcmeServer.Jobs.Registry,
        AcmeServer.Jobs.Supervisor
      ],
      strategy: :rest_for_one,
      name: __MODULE__
    )
  end

  def start_http_verifier(data),
    do: AcmeServer.Jobs.Supervisor.start_job({AcmeServer.Jobs.HttpVerifier, data})

  def child_spec(_),
    do: %{id: __MODULE__, type: :supervisor, start: {__MODULE__, :start_link, []}}
end
