defmodule AcmeServer.Jobs.Supervisor do
  def start_link(), do: DynamicSupervisor.start_link(strategy: :one_for_one, name: __MODULE__)

  def start_job(job_spec), do: DynamicSupervisor.start_child(__MODULE__, job_spec)

  def child_spec(_) do
    Supervisor.child_spec(
      DynamicSupervisor,
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    )
  end
end
