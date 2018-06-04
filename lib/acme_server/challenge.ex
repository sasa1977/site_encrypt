defmodule AcmeServer.Challenge do
  @moduledoc false

  # This module powers a single process, which issues an http challenge to the
  # server. If the challenge succeeds, the job updates the account info.
  #
  # Each challenge is running as a separate process, which ensure proper error
  # isolation. Failure or blockage of while challenging one site won't affect
  # other challenges.
  #
  # A challenge process is a Parent.GenServer which makes the actual request
  # in a child task. This approach is chosen for better control of error
  # handling. The parent process can apply delay and retry logic, and give
  # up after some number of retries.
  #
  # Because failure of one challenge request shouldn't affect other challenges,
  # the restart strategy is temporary. In principle, the Parent.GenServer has
  # minimal logic, since most of the action is happening in the child task, so
  # it shouldn't crash. But even if it does, we don't want to trip up the
  # restart intensity, and crash other challenges.

  # We'll retry at most 12 times, with 5 seconds delay between each retry.
  # Each challenge request must return in 5 seconds. Therefore, in total
  # we're challenging for at most 1 minute 55 seconds (12 timeouts of 5 seconds
  # plus 11 delays of 5 seconds).
  @max_retries 12
  @retry_delay :timer.seconds(5)
  @http_request_timeout :timer.seconds(5)

  use Parent.GenServer, restart: :temporary

  def start_link({challenge_data, registered_name}),
    # We're registering the job under the jobs registry to make sure no duplicate
    # registrations for the same site are running.
    do: Parent.GenServer.start_link(__MODULE__, challenge_data, name: registered_name)

  @impl GenServer
  def init(challenge_data) do
    state = Map.merge(challenge_data, %{parent: self(), attempts: 1})
    start_challenge(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:challenge_succeeded, state), do: {:stop, :normal, state}
  def handle_info(:challenge_failed, state), do: retry_challenge(state)

  def handle_info(:start_challenge, state) do
    start_challenge(state)
    {:noreply, state}
  end

  def handle_info(other, state), do: super(other, state)

  @impl Parent.GenServer
  def handle_child_terminated(:challenge, _meta, _pid, :normal, state), do: {:noreply, state}

  def handle_child_terminated(:challenge, _meta, _pid, _abnormal_reason, state),
    do: retry_challenge(state)

  defp retry_challenge(state) do
    if(state.attempts == @max_retries) do
      {:stop, {:error, :max_failures}, state}
    else
      Process.send_after(self(), :start_challenge, @retry_delay)
      {:noreply, update_in(state.attempts, &(&1 + 1))}
    end
  end

  defp start_challenge(state) do
    Parent.GenServer.start_child(%{
      id: :challenge,
      start: {Task, :start_link, [fn -> challenge(state) end]}
    })
  end

  defp challenge(state) do
    if state.order.domains
       |> challenge_domains(state.order.token, state.dns, state.key_thumbprint)
       |> Enum.all?(&(&1 == :ok)) do
      AcmeServer.Account.update_order(state.account_id, %{state.order | status: :valid})
      send(state.parent, :challenge_succeeded)
    else
      send(state.parent, :challenge_failed)
    end
  end

  defp challenge_domains(domains, token, dns, key_thumbprint) do
    domains
    |> Task.async_stream(&challenge_domain(http_server(&1, dns), token, key_thumbprint))
    |> Enum.map(fn
      {:ok, result} -> result
      _ -> :error
    end)
  end

  defp http_server(domain, dns) do
    case Map.fetch(dns, domain) do
      {:ok, resolver} -> resolver.()
      :error -> domain
    end
  end

  defp challenge_domain(url, token, key_thumbprint) do
    with {:ok, {{_, 200, _}, _headers, response}} <- http_request(url, token),
         ^response <- "#{token}.#{key_thumbprint}" do
      :ok
    else
      _ -> :error
    end
  end

  defp http_request(server, token) do
    # Using httpc, because it doesn't require external dependency. Httpc is not
    # suitable for production, but AcmeServer is not meant to be used in
    # production anyway.
    :httpc.request(
      :get,
      {'http://#{server}/.well-known/acme-challenge/#{token}', []},
      [timeout: @http_request_timeout],
      body_format: :binary
    )
  end
end
