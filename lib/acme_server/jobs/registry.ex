defmodule AcmeServer.Jobs.Registry do
  def child_spec(_) do
    Supervisor.child_spec(
      {Registry, keys: :unique, name: __MODULE__},
      id: __MODULE__
    )
  end

  def via(name), do: {:via, Registry, {__MODULE__, name}}
end
