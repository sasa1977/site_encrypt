defmodule AcmeServer.Challenges do
  @moduledoc false

  def child_spec(config) do
    Supervisor.child_spec(
      DynamicSupervisor,
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]}
    )
  end

  def start_link(config),
    do: DynamicSupervisor.start_link(strategy: :one_for_one, name: via(config))

  def start_challenge(config, challenge_data) do
    DynamicSupervisor.start_child(
      via(config),
      {AcmeServer.Challenge, {challenge_data, challenge_name(config, challenge_data)}}
    )
  end

  defp via(config), do: AcmeServer.Registry.via_tuple({__MODULE__, config.site})

  # We'll register each challenge with the registry, using ACME server site and
  # challenge data as the unique key. This ensures that no duplicate challenges
  # are running at the same time.
  defp challenge_name(config, challenge_data),
    do: AcmeServer.Registry.via_tuple({AcmeServer.Challenge, config.site, challenge_data})
end
