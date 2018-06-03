defmodule AcmeServer.Jobs do
  @moduledoc false

  def start_link() do
    # This is the supervision subtree where concurrent jobs of AcmeServer are running.
    # Currently, the only type of job is an http verifier, which issues a challenge
    # request to the site which wants to be certified.

    Supervisor.start_link(
      [
        # Registry is used to register a job under an arbitrary id. This is
        # currently used to ensure that there are no duplicate verifications for
        # the same site.
        AcmeServer.Jobs.Registry,
        # Each job is running as a child of `AcmeServer.Jobs.Supervisor`.
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
