defmodule AcmeServer.Jobs.HttpVerifier do
  use Parent.GenServer, restart: :temporary

  def start_link(verification_data),
    do: Parent.GenServer.start_link(__MODULE__, verification_data, name: via(verification_data))

  @impl GenServer
  def init(verification_data) do
    state = Map.put(verification_data, :parent, self())
    start_verification(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:verification_succeeded, state), do: {:stop, :normal, state}

  def handle_info(:verification_failed, state) do
    Process.send_after(self(), :start_verification, :timer.seconds(5))
    {:noreply, state}
  end

  def handle_info(:start_verification, state) do
    start_verification(state)
    {:noreply, state}
  end

  def handle_info(other, state), do: super(other, state)

  @impl Parent.GenServer
  def handle_child_terminated(:verification, _meta, _pid, :normal, state), do: {:noreply, state}

  def handle_child_terminated(:verification, _meta, _pid, _abnormal_reason, state) do
    start_verification(state)
    {:noreply, state}
  end

  defp start_verification(state) do
    Parent.GenServer.start_child(%{
      id: :verification,
      start: {Task, :start_link, [fn -> verify(state) end]}
    })
  end

  defp verify(state) do
    if state.order.domains
       |> verify_domains(state.order.token, state.dns, state.key_thumbprint)
       |> Enum.all?(&(&1 == :ok)) do
      AcmeServer.Account.update_order(state.account_id, %{state.order | status: :valid})
      send(state.parent, :verification_succeeded)
    else
      send(state.parent, :verification_failed)
    end
  end

  defp verify_domains(domains, token, dns, key_thumbprint) do
    domains
    |> Task.async_stream(&verify_domain(http_server(&1, dns), token, key_thumbprint))
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

  defp verify_domain(url, token, key_thumbprint) do
    with {:ok, {{_, 200, _}, _headers, response}} <- http_request(url, token),
         ^response <- "#{token}.#{key_thumbprint}" do
      :ok
    else
      _ -> :error
    end
  end

  defp http_request(server, token) do
    :httpc.request(
      :get,
      {'http://#{server}/.well-known/acme-challenge/#{token}', []},
      [],
      body_format: :binary
    )
  end

  defp via(data), do: AcmeServer.Jobs.Registry.via({__MODULE__, data})
end
