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
      {AcmeServer.Challenge, {config, challenge_data}}
    )
  end

  defp via(config), do: AcmeServer.Registry.via_tuple({__MODULE__, config.site})
end
